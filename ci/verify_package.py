#!/usr/bin/env python3
"""Inspect the actual RootHide deb; signatures are structural, not device proof.

Run on macOS or Linux with dpkg-deb. SHA256SUMS.txt is emitted by build.sh.
"""
import argparse
import hashlib
import json
import plistlib
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
S_MOD_INIT_FUNC_POINTERS = 0x9
S_INIT_FUNC_OFFSETS = 0x16


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command(*args):
    return subprocess.check_output(args, text=True)


def control_fields(text):
    return dict(line.split(": ", 1) for line in text.splitlines()
                if ": " in line and not line[0].isspace())


def macho(data):
    """Bound all FAT slices, load commands and embedded signature containers."""
    if data[:4] == b"\xca\xfe\xba\xbe":
        count = struct.unpack_from(">I", data, 4)[0]
        require(0 < count <= 8 and len(data) >= 8 + 20 * count, "Invalid FAT table")
        regions = []
        for i in range(count):
            _, _, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + 20 * i)
            require(offset >= 8 + 20 * count and size >= 32 and
                    offset + size <= len(data), "Invalid FAT slice bounds")
            require(all(offset + size <= a or a + b <= offset for a, b in regions),
                    "Overlapping FAT slices")
            regions.append((offset, size))
    else:
        regions = [(0, len(data))]
    results = []
    for offset, size in regions:
        block = data[offset:offset + size]
        require(len(block) >= 32 and block[:4] == b"\xcf\xfa\xed\xfe", "Expected MH_MAGIC_64")
        _, cpu, subtype, _, ncmds, cmdbytes, _, _ = struct.unpack_from("<8I", block)
        require(cpu == 0x0100000C, "Not ARM64")
        subtype &= 0x00FFFFFF
        require(subtype in (0, 2), "Unexpected ARM64 subtype")
        require(ncmds <= 4096 and 32 + cmdbytes <= len(block), "Bad load-command bounds")
        cursor = 32
        minimum = None
        signed = False
        dependencies = []
        sections = []
        for _ in range(ncmds):
            require(cursor + 8 <= 32 + cmdbytes, "Truncated load command")
            cmd, length = struct.unpack_from("<II", block, cursor)
            end = cursor + length
            require(length >= 8 and end <= 32 + cmdbytes, "Bad command length")
            if cmd == 0x19:  # LC_SEGMENT_64
                require(length >= 72, "Truncated 64-bit segment")
                nsects = struct.unpack_from("<I", block, cursor + 64)[0]
                require(72 + 80 * nsects <= length, "Truncated section table")
                for index in range(nsects):
                    section = cursor + 72 + 80 * index
                    (sectname, segname, address, secsize, fileoff, align,
                     reloff, nreloc, flags, reserved1, reserved2,
                     reserved3) = struct.unpack_from(
                         "<16s16sQQIIIIIIII", block, section)
                    sections.append({
                        "segment": segname.split(b"\0", 1)[0].decode(),
                        "name": sectname.split(b"\0", 1)[0].decode(),
                        "address": address,
                        "size": secsize,
                        "file_offset": fileoff,
                        "type": flags & 0xFF,
                    })
            elif cmd == 0x32:  # LC_BUILD_VERSION
                require(length >= 24, "Truncated build version")
                platform, minimum = struct.unpack_from("<II", block, cursor + 8)
                require(platform == 2, "Not an iOS device binary")
            elif cmd == 0x25:  # LC_VERSION_MIN_IPHONEOS
                require(length >= 16, "Truncated minimum OS")
                minimum = struct.unpack_from("<I", block, cursor + 8)[0]
            elif cmd == 0x1D:  # LC_CODE_SIGNATURE
                require(length >= 16, "Truncated signature command")
                start, sigsize = struct.unpack_from("<II", block, cursor + 8)
                require(sigsize >= 12 and start >= 32 + cmdbytes and
                        start + sigsize <= len(block), "Out-of-bounds signature")
                magic, declared, count = struct.unpack_from(">III", block, start)
                require(magic == 0xFADE0CC0 and 12 + count * 8 <= declared <= sigsize,
                        "Invalid embedded signature SuperBlob")
                code_directory = False
                for i in range(count):
                    _, rel = struct.unpack_from(">II", block, start + 12 + 8 * i)
                    require(rel >= 12 + count * 8 and rel + 8 <= declared,
                            "Bad signature child offset")
                    childmagic, childsize = struct.unpack_from(">II", block, start + rel)
                    require(8 <= childsize <= declared - rel, "Bad signature child length")
                    code_directory |= childmagic == 0xFADE0C02
                require(code_directory, "Missing CodeDirectory")
                signed = True
            elif cmd in (0xC, 0x18, 0x80000018, 0x8000001F):
                require(length >= 24, "Truncated dylib command")
                nameoff = struct.unpack_from("<I", block, cursor + 8)[0]
                require(24 <= nameoff < length, "Bad dependency offset")
                name = block[cursor + nameoff:end].split(b"\0", 1)[0].decode()
                require(not name.startswith("/var/jb/"), "Rootless dependency in RootHide binary")
                dependencies.append(name)
            cursor = end
        require(cursor == 32 + cmdbytes, "Load-command count mismatch")
        require(minimum == 0x000F0000, "Expected compiled iOS 15.0 minimum")
        require(signed, "Missing embedded signature")
        initializers = []
        for section in sections:
            if section["type"] not in (S_MOD_INIT_FUNC_POINTERS, S_INIT_FUNC_OFFSETS):
                continue
            width = 8 if section["type"] == S_MOD_INIT_FUNC_POINTERS else 4
            start, count_bytes = section["file_offset"], section["size"]
            require(count_bytes > 0 and count_bytes % width == 0,
                    "Invalid initializer element size")
            require(start >= 32 + cmdbytes and start + count_bytes <= len(block),
                    "Out-of-bounds initializer table")
            require(any(block[start:start + count_bytes]), "Empty initializer table")
            initializers.append(dict(section, count=count_bytes // width))
        results.append({"arch": "arm64e" if subtype == 2 else "arm64",
                        "slice_offset": offset, "slice_bytes": size,
                        "minimum_os": "15.0", "structural_signature": True,
                        "dependencies": dependencies, "sections": sections,
                        "initializers": initializers})
    require(sorted(x["arch"] for x in results) == ["arm64", "arm64e"],
            "Expected one arm64 and one arm64e slice")
    return results


def require_selector_per_slice(data, records, selector):
    for record in records:
        start, size = record["slice_offset"], record["slice_bytes"]
        require(selector in data[start:start + size],
                f"Required selector missing from {record['arch']} slice: {selector!r}")


def verify_settings_reference_resource(payload, expected):
    require(payload == expected, "Settings reference resource does not match exact source bytes")
    reference = json.loads(payload)
    require(reference["schemaVersion"] == 1, "Wrong Settings reference schema version")
    home_controls = sum(len(section["rows"]) for section in reference["homeSections"])
    categories = len(reference["actionCategories"])
    basic_catalog = len(reference["basicActions"])
    require((home_controls, categories, basic_catalog) == (21, 6, 68),
            "Incomplete original Settings reference resource")
    return {"sha256": hashlib.sha256(payload).hexdigest(), "home_controls": home_controls,
            "categories": categories, "basic_catalog": basic_catalog}


def verify(package):
    fields = control_fields(command("dpkg-deb", "-f", str(package)))
    expected = control_fields((ROOT / "control").read_text())
    for key in ("Package", "Name", "Version"):
        require(fields.get(key) == expected[key], f"Wrong {key}: {fields.get(key)}")
    require(fields["Architecture"] == "iphoneos-arm64e", "Not a RootHide package")
    depends = fields.get("Depends", "")
    require("${" not in depends and "mobilesubstrate" in depends.lower() and
            "preferenceloader" in depends and "firmware (>= 15.0)" in depends,
            f"Unresolved/missing runtime dependencies: {depends}")
    listing = command("dpkg-deb", "-c", str(package))
    require("./var/jb/" not in listing, "Rootless payload in RootHide package")
    require(not any(name in listing for name in
                    ("NativeHookFixture", "NativeHookReactivation", "NativeStartupApp", "MediaRemoteFixture", "MediaPlayPauseRuntimeTests", "FlashlightRuntimeTests")),
            "Simulator fixture leaked into package")
    with tempfile.TemporaryDirectory(prefix="taplock-verify-") as directory:
        dest = Path(directory)
        command("dpkg-deb", "-x", str(package), str(dest))
        command("dpkg-deb", "-e", str(package), str(dest / "DEBIAN"))
        required = ["Library/MobileSubstrate/DynamicLibraries/TapLock.dylib",
                    "Library/MobileSubstrate/DynamicLibraries/TapLock.plist",
                    "Library/PreferenceBundles/TapLockPrefs.bundle/TapLockPrefs",
                    "Library/PreferenceBundles/TapLockPrefs.bundle/Info.plist",
                    "Library/PreferenceLoader/Preferences/TapLock.plist",
                    "Library/PreferenceBundles/TapLockPrefs.bundle/SettingsReference.json"]
        for name in required:
            require((dest / name).is_file(), f"Missing payload: {name}")
        tweak = plistlib.loads((dest / required[1]).read_bytes())
        info = plistlib.loads((dest / required[3]).read_bytes())
        entry = plistlib.loads((dest / required[4]).read_bytes())["entry"]
        settings_reference = verify_settings_reference_resource((dest / required[5]).read_bytes(),
            (ROOT / "Preferences/Resources/SettingsReference.json").read_bytes())
        require(tweak["Filter"] == {"Bundles": ["com.apple.springboard"]}, "Wrong injection filter")
        require(info["NSPrincipalClass"] == entry["detail"] == "TapLockSettingsController",
                "Settings detail/principal mismatch")
        require(info["CFBundleIdentifier"] == "com.tsangbaby.taplock.preferences", "Wrong bundle ID")
        require(info["CFBundleExecutable"] == entry["bundle"] == "TapLockPrefs", "Wrong bundle executable")
        require(info["CFBundleVersion"] == info["CFBundleShortVersionString"] == expected["Version"],
                "Wrong Settings version")
        for script in (dest / "DEBIAN").iterdir():
            if script.name in ("postinst", "preinst", "prerm", "postrm"):
                require(script.stat().st_mode & 0o777 == 0o755, f"Non-executable {script.name}")
        binaries = {name: macho((dest / name).read_bytes()) for name in (required[0], required[2])}
        tweak_bytes = (dest / required[0]).read_bytes()
        for forbidden in (b"LSApplicationWorkspace", b"LSApplicationProxy", b"LSApplicationRecord",
                          b"openApplicationWithBundleID:",
                          b"_applicationIconImageForBundleIdentifier:format:scale:"):
            require(forbidden not in tweak_bytes, f"Settings/client API leaked into SpringBoard binary: {forbidden!r}")
        require_selector_per_slice(tweak_bytes, binaries[required[0]],
                                   b"launchApplicationWithIdentifier:suspended:")
        control_center_names = (b"SBControlCenterController", b"presentAnimated:",
                                b"isPresentedOrDismissing", b"canBePresented")
        # Optimized Swift small strings need not exist as contiguous bytes
        # (also true of the accepted isUILocked/isUIUnlocking getters).
        # Executed Swift tests cover every ABI gate; the binary footprint gate
        # independently requires all long native lookup names in both slices.
        for name in control_center_names:
            if len(name) > 15:
                require_selector_per_slice(tweak_bytes, binaries[required[0]], name)
        require(b"SBControlCenterController" not in (dest / required[2]).read_bytes(),
                "Control Center provider leaked into Settings binary")
        notification_center_names = (b"SBCoverSheetPresentationManager",
                                     b"setCoverSheetPresented:animated:withCompletion:",
                                     b"coverSheetCanTransitionToPresented:")
        for name in notification_center_names:
            require_selector_per_slice(tweak_bytes, binaries[required[0]], name)
        require(b"SBCoverSheetPresentationManager" not in (dest / required[2]).read_bytes(),
                "Notification Center provider leaked into Settings binary")
        # takeScreenshot is a short Swift lookup string and need not remain
        # contiguous in optimized code; Apple target compilation and executed
        # production receiver/ABI tests are its positive membership evidence.
        require(b"takeScreenshot" not in (dest / required[2]).read_bytes(),
                "Screenshot provider leaked into Settings binary")
        app_switcher_selector = b"activateMainSwitcherNoninteractivelyWithSource:animated:"
        require_selector_per_slice(tweak_bytes, binaries[required[0]], app_switcher_selector)
        require(app_switcher_selector not in (dest / required[2]).read_bytes(),
                "App Switcher provider leaked into Settings binary")
        media_names = (b"MRMediaRemoteSendCommand",
                       b"/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote")
        for name in media_names:
            require_selector_per_slice(tweak_bytes, binaries[required[0]], name)
            require(name not in (dest / required[2]).read_bytes(),
                    "Media provider leaked into Settings binary")
        for name in (b"SBUIFlashlightController", b"_loadFlashlightLevel"):
            require(name not in (dest / required[2]).read_bytes(),
                    "Flashlight provider leaked into Settings binary")
        for name in (b"TLFlashlight", b"FLASHLIGHT_RUNTIME_", b"FLASHLIGHT_NATIVE_"):
            require(all(name not in (dest / path).read_bytes() for path in binaries),
                    "Flashlight test fixture leaked into shipped binary")
        require_selector_per_slice((dest / required[2]).read_bytes(), binaries[required[2]],
                                   b"_applicationIconImageForBundleIdentifier:format:scale:")
        for record in binaries[required[0]]:
            require(not any("Orion.framework" in item for item in record["dependencies"]),
                    "Retired Orion dependency in tweak")
            require(any(item.endswith("/usr/lib/libsubstrate.dylib")
                        for item in record["dependencies"]),
                    "Missing RootHide substrate runtime link")
            require(record["initializers"], "Missing retained native initializer (__mod_init_func / __init_offsets)")
    return {"file": package.name, "bytes": package.stat().st_size,
            "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
            "control": fields, "required_files": required, "binaries": binaries,
            "launch_boundary": "native SpringBoard selector present; LS client/catalog absent from tweak; icon loader in Settings only",
            "control_center_binary_long_names": [name.decode() for name in control_center_names if len(name) > 15],
            "notification_center_binary_long_names": [name.decode() for name in notification_center_names],
            "app_switcher_binary_selector": app_switcher_selector.decode(),
            "media_binary_lookup_names": [name.decode() for name in media_names],
            "settings_reference_resource": settings_reference,
            "device_tested": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    packages = list(args.package.glob("*.deb")) if args.package.is_dir() else [args.package]
    require(len(packages) == 1, f"Expected exactly one deb, got {len(packages)}")
    report = verify(packages[0])
    text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.report:
        args.report.write_text(text)
    print(text, end="")


if __name__ == "__main__":
    main()
