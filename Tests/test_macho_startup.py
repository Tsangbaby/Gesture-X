"""Synthetic parser fixtures only; real compiled/dlopen proof runs on Apple CI."""
import importlib.util
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("verify_package", ROOT / "ci/verify_package.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


def fixture(*, kind=9, section_size=8, file_offset=None):
    """Minimal FAT containers for bounds/name tests, NOT installable binaries."""
    slices = []
    for subtype in (0, 2):
        segment_size = 72 + 80
        commands_size = segment_size + 24 + 16
        data_offset = 32 + commands_size
        signature_offset = data_offset + 8
        section = struct.pack("<16s16sQQIIIIIIII", b"__mod_init_func", b"__DATA",
                              0x1000, section_size,
                              data_offset if file_offset is None else file_offset,
                              3, 0, 0, kind, 0, 0, 0)
        segment = struct.pack("<II16sQQQQIIII", 0x19, segment_size, b"__DATA",
                              0x1000, 8, data_offset, 8, 3, 3, 1, 0) + section
        minimum = struct.pack("<6I", 0x32, 24, 2, 0x000F0000, 0x000F0000, 0)
        signature = struct.pack("<4I", 0x1D, 16, signature_offset, 28)
        header = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, subtype, 6,
                             3, commands_size, 0, 0)
        # Intentionally skeletal signature: tests parser structure, not signer trust.
        blob = struct.pack(">7I", 0xFADE0CC0, 28, 1, 0, 20, 0xFADE0C02, 8)
        slices.append(header + segment + minimum + signature + struct.pack("<Q", 0x2000) + blob)
    first = 8 + 2 * 20
    return (struct.pack(">II", 0xCAFEBABE, 2) +
            struct.pack(">5I", 0x0100000C, 0, first, len(slices[0]), 0) +
            struct.pack(">5I", 0x0100000C, 2, first + len(slices[0]), len(slices[1]), 0) +
            b"".join(slices))


class MachOStartupParserTests(unittest.TestCase):
    def test_nul_padded_names_and_each_arch_initializer(self):
        records = verifier.macho(fixture())
        self.assertEqual([r["arch"] for r in records], ["arm64", "arm64e"])
        for record in records:
            self.assertEqual(record["sections"][0]["segment"], "__DATA")
            self.assertEqual(record["sections"][0]["name"], "__mod_init_func")
            self.assertEqual(record["initializers"][0]["count"], 1)

    def test_initializer_file_range_is_bounded(self):
        with self.assertRaisesRegex(ValueError, "initializer"):
            verifier.macho(fixture(file_offset=0x100000))

    def test_initializer_element_size_is_checked(self):
        with self.assertRaisesRegex(ValueError, "initializer"):
            verifier.macho(fixture(section_size=7))

    def test_section_name_alone_is_not_a_dyld_initializer(self):
        for record in verifier.macho(fixture(kind=0)):
            self.assertEqual(record.get("initializers"), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
