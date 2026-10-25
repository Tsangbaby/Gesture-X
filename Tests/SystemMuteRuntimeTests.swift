import Foundation
import CoreFoundation
import ObjectiveC
import Darwin

#if !SYSTEM_MUTE_BASELINE
// Fresh project-owned classes only; never replace registered method metadata.
private enum SystemMuteFixture {
    static let lockName = "TLSystemMuteLockFixture"
    static let appName = "TLSystemMuteApplicationFixture"
    static let workspaceName = "TLSystemMuteWorkspaceFixture"
    static let ringerName = "TLSystemMuteRingerFixture"
    static var lockType: AnyClass = NSObject.self, appType: AnyClass = NSObject.self
    static var workspaceType: AnyClass = NSObject.self, ringerType: AnyClass = NSObject.self
    static var lock: NSObject?, application: NSObject?, workspace: NSObject?, controller: NSObject?, directValue: NSObject?
    static var serial = 0
    static var events: [String] = [], submitted: [Bool] = [], hudArguments: [Int32] = []
    static var old = false, locked = false, visible = false, unlocking = false
    static var wrongReceiver = false, wrongSelector = false, allOnMain = true
    // Void calls deliberately leave observed state and HUD visibility unchanged.
    static var hudVisible = false
    static let lockTrace = ["lock.getter", "lock.locked", "lock.visible", "lock.unlocking"]
    struct Entry { let name: String; let encoding: String; let body: IMP }
    static func record(_ event: String, _ receiver: AnyObject, _ selector: Selector,
                       expected: AnyObject?, name: String) {
        events.append(event); allOnMain = allOnMain && Thread.isMainThread
        wrongSelector = wrongSelector || NSStringFromSelector(selector) != name
        if let expected = expected {
            wrongReceiver = wrongReceiver || ObjectIdentifier(receiver) != ObjectIdentifier(expected)
        } else { wrongReceiver = true }
    }
    static let lockGetter: @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>? = { receiver, selector in
        record("lock.getter", receiver, selector, expected: lockType as AnyObject, name: "sharedInstanceIfExists")
        return lock.map { Unmanaged.passUnretained($0 as AnyObject) }
    }
    static let appGetter: @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>? = { receiver, selector in
        record("app.getter", receiver, selector, expected: appType as AnyObject, name: "sharedApplication")
        return application.map { Unmanaged.passUnretained($0 as AnyObject) }
    }
    static let workspaceGetter: @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>? = { receiver, selector in
        record("workspace.getter", receiver, selector, expected: workspaceType as AnyObject, name: "sharedInstanceIfExists")
        return workspace.map { Unmanaged.passUnretained($0 as AnyObject) }
    }
    static let directGetter: @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>? = { receiver, selector in
        record("app.ringer", receiver, selector, expected: application, name: "ringerControl")
        return directValue.map { Unmanaged.passUnretained($0 as AnyObject) }
    }
    static let indirectGetter: @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>? = { receiver, selector in
        record("workspace.ringer", receiver, selector, expected: workspace, name: "ringerControl")
        return controller.map { Unmanaged.passUnretained($0 as AnyObject) }
    }
    static let lockState: @convention(c) (AnyObject, Selector) -> Bool = { receiver, selector in
        switch NSStringFromSelector(selector) {
        case "isUILocked": record("lock.locked", receiver, selector, expected: lock, name: "isUILocked"); return locked
        case "isLockScreenVisible": record("lock.visible", receiver, selector, expected: lock, name: "isLockScreenVisible"); return visible
        case "isUIUnlocking": record("lock.unlocking", receiver, selector, expected: lock, name: "isUIUnlocking"); return unlocking
        default: wrongSelector = true; return true
        }
    }
    static let readMuted: @convention(c) (AnyObject, Selector) -> Bool = { receiver, selector in
        record("read", receiver, selector, expected: controller, name: "isRingerMuted"); return old
    }
    static let setMuted: @convention(c) (AnyObject, Selector, Bool) -> Void = { receiver, selector, value in
        record("set", receiver, selector, expected: controller, name: "setRingerMuted:"); submitted.append(value)
    }
    static let showHUD: @convention(c) (AnyObject, Selector, Int32) -> Void = { receiver, selector, value in
        record("hud", receiver, selector, expected: controller, name: "activateRingerHUDFromMuteSwitch:"); hudArguments.append(value)
    }
    static func install(_ entries: [Entry], in type: AnyClass) {
        for e in entries {
            let selector = NSSelectorFromString(e.name)
            SystemMuteRuntimeTests.require(class_addMethod(type, selector, e.body, e.encoding), "fixture registration failed")
            guard let method = class_getInstanceMethod(type, selector), let raw = method_getTypeEncoding(method) else {
                SystemMuteRuntimeTests.fail("fixture metadata missing")
            }
            SystemMuteRuntimeTests.require(String(cString: raw) == e.encoding, "fixture encoding readback differs")
        }
    }
    static func allocate(_ name: String, superclass: AnyClass) -> AnyClass {
        SystemMuteRuntimeTests.require(NSClassFromString(name) == nil, "fixture identity collision: " + name)
        guard let type = objc_allocateClassPair(superclass, name, 0) else { SystemMuteRuntimeTests.fail("fixture allocation failed") }
        return type
    }
    static func instance(_ type: AnyClass) -> NSObject {
        guard let value = class_createInstance(type, 0) as? NSObject else { SystemMuteRuntimeTests.fail("instance allocation failed") }
        return value
    }
    static func root(_ name: String, getter: String? = nil, encoding: String? = "@@:", imp: IMP? = nil) -> AnyClass {
        let type = allocate(name, superclass: NSObject.self)
        if let getter = getter, let encoding = encoding, let imp = imp {
            guard let meta = object_getClass(type as AnyObject) else { SystemMuteRuntimeTests.fail("metaclass missing") }
            install([Entry(name: getter, encoding: encoding, body: imp)], in: meta)
        }
        objc_registerClassPair(type)
        SystemMuteRuntimeTests.require(NSClassFromString(name).map { ObjectIdentifier($0) } == ObjectIdentifier(type), "resolved wrong fixture class")
        return type
    }
    static func subclass(_ root: AnyClass, _ entries: [Entry]) -> NSObject {
        serial += 1
        let type = allocate("TLSystemMuteDisposable_\(serial)", superclass: root)
        install(entries, in: type); objc_registerClassPair(type)
        return instance(type)
    }
    static func makeLock(overrides: [String: String] = [:], missing: Set<String> = []) -> NSObject {
        subclass(lockType, ["isUILocked", "isLockScreenVisible", "isUIUnlocking"].filter { !missing.contains($0) }.map {
            Entry(name: $0, encoding: overrides[$0] ?? "B@:", body: unsafeBitCast(lockState, to: IMP.self))
        })
    }
    static func makeApp(encoding: String? = "@@:") -> NSObject {
        subclass(appType, encoding.map { [Entry(name: "ringerControl", encoding: $0, body: unsafeBitCast(directGetter, to: IMP.self))] } ?? [])
    }
    static func makeWorkspace(encoding: String? = "@@:") -> NSObject {
        subclass(workspaceType, encoding.map { [Entry(name: "ringerControl", encoding: $0, body: unsafeBitCast(indirectGetter, to: IMP.self))] } ?? [])
    }
    static func makeController(overrides: [String: String] = [:], missing: Set<String> = []) -> NSObject {
        let entries = [Entry(name: "isRingerMuted", encoding: "B@:", body: unsafeBitCast(readMuted, to: IMP.self)),
                       Entry(name: "setRingerMuted:", encoding: "v@:B", body: unsafeBitCast(setMuted, to: IMP.self)),
                       Entry(name: "activateRingerHUDFromMuteSwitch:", encoding: "v@:i", body: unsafeBitCast(showHUD, to: IMP.self))]
        return subclass(ringerType, entries.filter { !missing.contains($0.name) }.map {
            Entry(name: $0.name, encoding: overrides[$0.name] ?? $0.encoding, body: $0.body)
        })
    }
    static func reset() {
        events = []; submitted = []; hudArguments = []; wrongReceiver = false; wrongSelector = false; allOnMain = true
    }
    static func noStateOrEffects() -> Bool {
        !events.contains { ["read", "set", "hud"].contains($0) } && submitted.isEmpty && hudArguments.isEmpty && !hudVisible
    }
    static func integrity() {
        SystemMuteRuntimeTests.require(!wrongReceiver && !wrongSelector && allOnMain, "receiver/selector/main-thread mismatch")
    }
    static func setup(role: String = "", encoding: String? = "@@:") {
        if role.isEmpty {
            reset(); SystemMuteRuntimeTests.require(!SystemMuteAction.toggle() && events.isEmpty, "missing lock class admitted")
        }
        lockType = root(lockName, getter: "sharedInstanceIfExists", encoding: role == "lock" ? encoding : "@@:", imp: unsafeBitCast(lockGetter, to: IMP.self))
        lock = makeLock()
        if role.isEmpty {
            reset(); SystemMuteRuntimeTests.require(!SystemMuteAction.toggle() && events == lockTrace, "missing application class admitted")
        }
        appType = root(appName, getter: "sharedApplication", encoding: role == "app" ? encoding : "@@:", imp: unsafeBitCast(appGetter, to: IMP.self))
        application = makeApp(encoding: nil)
        if role.isEmpty {
            reset(); SystemMuteRuntimeTests.require(!SystemMuteAction.toggle() && events == lockTrace + ["app.getter"], "missing workspace class admitted")
        }
        workspaceType = root(workspaceName, getter: "sharedInstanceIfExists", encoding: role == "workspace" ? encoding : "@@:", imp: unsafeBitCast(workspaceGetter, to: IMP.self))
        workspace = makeWorkspace(); controller = NSObject()
        if role.isEmpty {
            reset(); SystemMuteRuntimeTests.require(!SystemMuteAction.toggle() && noStateOrEffects(), "missing ringer class admitted")
        }
        ringerType = root(ringerName)
        recover(direct: role != "workspace")
    }
    static func recover(direct: Bool = true) {
        lock = makeLock(); application = makeApp(encoding: direct ? "@@:" : nil); workspace = makeWorkspace()
        controller = makeController(); directValue = controller
        locked = false; visible = false; unlocking = false
    }
}
#endif

@main
struct SystemMuteRuntimeTests {
    static var assertions = 0
    static var cleanup: (() -> Bool)?
    static func fail(_ message: String) -> Never {
        let restore = cleanup; cleanup = nil
        if restore?() == false { print("SYSTEM_MUTE_RUNTIME_FAIL: preference restoration failed"); fflush(stdout); exit(2) }
        print("SYSTEM_MUTE_RUNTIME_FAIL: " + message); fflush(stdout); exit(1)
    }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }; assertions += 1
    }
    static func same(_ left: CFPropertyList?, _ right: CFPropertyList?) -> Bool {
        switch (left, right) { case (nil, nil): return true; case let (a?, b?): return CFEqual(a, b); default: return false }
    }
    static func sync() -> Bool {
        CFPreferencesSynchronize(TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    static func stored(_ key: String) -> CFPropertyList? {
        CFPreferencesCopyValue(key as CFString, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    static func raw(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetValue(key as CFString, value, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        require(sync(), "fixture preference write failed")
    }
    #if !SYSTEM_MUTE_BASELINE
    static func preferences() {
        let actions: [(TapLockPreferences.Action, [String: String])] = [
            (.lock, ["kind": "lock"]), (.openApp("com.example.systemmutefixture"), ["kind": "openApp", "bundleIdentifier": "com.example.systemmutefixture"]),
            (.controlCenter, ["kind": "controlCenter"]), (.notificationCenter, ["kind": "notificationCenter"]),
            (.screenshot, ["kind": "screenshot"]), (.appSwitcher, ["kind": "appSwitcher"]),
            (.playPause, ["kind": "playPause"]), (.previousTrack, ["kind": "previousTrack"]),
            (.nextTrack, ["kind": "nextTrack"]), (.flashlight, ["kind": "flashlight"]), (.systemMute, ["kind": "systemMute"])]
        require(actions.count == 11, "incomplete single-action matrix")
        for enabled in [nil, kCFBooleanFalse, kCFBooleanTrue] as [CFPropertyList?] {
            raw(TapLockPreferences.enabledKey, enabled)
            require(TapLockPreferences.readEnabled() == (enabled.map { CFEqual($0, kCFBooleanTrue) } ?? false), "enable/default changed")
            for (before, record) in actions {
                for (after, replacement) in actions {
                    raw(TapLockPreferences.actionKey, record as CFDictionary)
                    require(TapLockPreferences.readAction() == before, "old action decode changed")
                    require(TapLockPreferences.writeAction(after), "action replacement failed")
                    require(TapLockPreferences.readAction() == after, "replacement roundtrip failed")
                    require(same(stored(TapLockPreferences.actionKey), replacement as CFDictionary), "stale action/App target retained")
                    require(same(stored(TapLockPreferences.enabledKey), enabled), "selection changed enable state")
                }
            }
        }
        var malformed: [CFPropertyList] = [[: ] as CFDictionary, "systemMute" as CFString, ["systemMute"] as CFArray, NSNumber(value: true), NSNumber(value: 1)]
        let wrongKinds: [Any] = [true, 1, ["systemMute"], ["nested": true], "SystemMute", "SYSTEMMUTE", " systemMute", "systemMute ", "systemMute\n", "siri"]
        for value in wrongKinds {
            malformed.append(["kind": value] as CFDictionary)
        }
        for key in ["bundleIdentifier", "extra", "target", "enabled", "actions"] {
            malformed.append(["kind": "systemMute", key: "bad"] as CFDictionary)
        }
        let enabled = stored(TapLockPreferences.enabledKey)
        for value in malformed {
            raw(TapLockPreferences.actionKey, value)
            require(TapLockPreferences.readAction() == .unavailable, "malformed systemMute admitted")
            require(same(stored(TapLockPreferences.actionKey), value) && same(stored(TapLockPreferences.enabledKey), enabled), "invalid read mutated preferences")
        }
        raw(TapLockPreferences.actionKey, nil)
        require(TapLockPreferences.readAction() == .lock && stored(TapLockPreferences.actionKey) == nil && !TapLockPreferences.defaultEnabled, "missing-action/default changed")
        require(TapLockPreferences.writeAction(.systemMute), "valid selection did not recover")
        let selected = stored(TapLockPreferences.actionKey)
        require(!TapLockPreferences.writeAction(.unavailable) && !TapLockPreferences.writeAction(.openApp("")), "invalid write admitted")
        require(same(stored(TapLockPreferences.actionKey), selected) && same(stored(TapLockPreferences.enabledKey), enabled), "rejected write mutated storage")
    }
    static func reject(_ trace: [String], _ label: String) {
        SystemMuteFixture.reset()
        require(!SystemMuteAction.toggle(), "refusal admitted: " + label)
        require(SystemMuteFixture.events == trace && SystemMuteFixture.noStateOrEffects(), "refusal read state/effected/fell back: " + label)
        SystemMuteFixture.integrity()
    }
    static func accepted(direct: Bool, old: Bool) {
        SystemMuteFixture.recover(direct: direct); SystemMuteFixture.old = old; SystemMuteFixture.reset()
        for _ in 0..<3 { require(SystemMuteAction.toggle(), "valid void attempt rejected") }
        let trace = SystemMuteFixture.lockTrace + ["app.getter"] +
            (direct ? ["app.ringer"] : ["workspace.getter", "workspace.ringer"]) + ["read", "set", "hud"]
        require(SystemMuteFixture.events == Array(repeating: trace, count: 3).flatMap { $0 }, "old/set/HUD order or multiplicity changed")
        require(SystemMuteFixture.submitted == Array(repeating: !old, count: 3), "setter Bool argument changed")
        require(SystemMuteFixture.hudArguments == Array(repeating: Int32(old ? 1 : 0), count: 3), "HUD Int32 old-state argument changed")
        require(SystemMuteFixture.old == old && !SystemMuteFixture.hudVisible, "void call confused with observed state/HUD proof")
        SystemMuteFixture.integrity()
    }
    static let badGetters = ["q@:", "Q@:", "B@:", "i@:", "d@:", "v@:", "@@:i", "@i:", "@@i"]
    static func owners() {
        let base = SystemMuteFixture.lockTrace + ["app.getter"]
        for value in [nil, NSObject()] as [NSObject?] {
            SystemMuteFixture.recover(); SystemMuteFixture.application = value; reject(base, "application identity")
        }
        for direct in [true, false] {
            for value in [nil, NSObject()] as [NSObject?] {
                SystemMuteFixture.recover(direct: direct)
                if direct { SystemMuteFixture.directValue = value }
                else { SystemMuteFixture.workspace = value }
                reject(base + (direct ? ["app.ringer"] : ["workspace.getter"]), "direct nil/wrong class or workspace identity")
            }
            for encoding in badGetters {
                SystemMuteFixture.recover(direct: direct)
                if direct { SystemMuteFixture.application = SystemMuteFixture.makeApp(encoding: encoding) }
                else { SystemMuteFixture.workspace = SystemMuteFixture.makeWorkspace(encoding: encoding) }
                reject(base + (direct ? [] : ["workspace.getter"]), "owner getter ABI; no direct fallback")
            }
            if !direct {
                SystemMuteFixture.recover(direct: false); SystemMuteFixture.workspace = SystemMuteFixture.makeWorkspace(encoding: nil)
                reject(base + ["workspace.getter"], "missing workspace ringer getter")
            }
            accepted(direct: direct, old: false)
        }
    }
    static func ringerABI() {
        let shapes = [("isRingerMuted", "B", ""), ("setRingerMuted:", "v", "B"), ("activateRingerHUDFromMuteSwitch:", "v", "i")]
        for direct in [true, false] {
            let trace = SystemMuteFixture.lockTrace + ["app.getter"] + (direct ? ["app.ringer"] : ["workspace.getter", "workspace.ringer"])
            func bad(_ value: NSObject?) {
                for old in [false, true] {
                    SystemMuteFixture.recover(direct: direct); SystemMuteFixture.old = old
                    SystemMuteFixture.controller = value; SystemMuteFixture.directValue = value
                    reject(trace, "ringer ABI/identity")
                }
            }
            bad(nil); bad(NSObject()); bad(SystemMuteFixture.instance(SystemMuteFixture.ringerType))
            for (name, result, argument) in shapes {
                bad(SystemMuteFixture.makeController(missing: [name]))
                for wrong in ["q", "Q", "B", "i", "@", "d", "v"] where wrong != result {
                    bad(SystemMuteFixture.makeController(overrides: [name: wrong + "@:" + argument]))
                }
                for encoding in [result + "i:" + argument, result + "#:" + argument, result + "@i" + argument, result + "@@" + argument, result + "@:" + argument + "i", result + "@:"] where encoding != result + "@:" + argument {
                    bad(SystemMuteFixture.makeController(overrides: [name: encoding]))
                }
                if !argument.isEmpty {
                    for wrong in ["q", "Q", "B", "i", "c", "@", "d"] where wrong != argument {
                        bad(SystemMuteFixture.makeController(overrides: [name: result + "@:" + wrong]))
                    }
                }
            }
            accepted(direct: direct, old: true)
        }
    }
    private final class ThreadResult: @unchecked Sendable { var admitted = true; var main = true }
    static func admission() {
        SystemMuteFixture.recover(); SystemMuteFixture.reset()
        let result = ThreadResult(), done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { result.main = Thread.isMainThread; result.admitted = SystemMuteAction.toggle(); done.signal() }
        require(done.wait(timeout: .now() + 5) == .success && !result.main && !result.admitted, "off-main request admitted/timed out")
        require(SystemMuteFixture.events.isEmpty && SystemMuteFixture.noStateOrEffects(), "off-main touched owner")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        require(SystemMuteFixture.events.isEmpty, "off-main queued work")
        for mask in 1..<8 {
            SystemMuteFixture.recover(); SystemMuteFixture.locked = mask & 1 != 0
            SystemMuteFixture.visible = mask & 2 != 0; SystemMuteFixture.unlocking = mask & 4 != 0
            let length = SystemMuteFixture.locked ? 2 : (SystemMuteFixture.visible ? 3 : 4)
            reject(Array(SystemMuteFixture.lockTrace.prefix(length)), "lock state")
        }
        for value in [nil, NSObject(), SystemMuteFixture.instance(SystemMuteFixture.lockType)] as [NSObject?] {
            SystemMuteFixture.recover(); SystemMuteFixture.lock = value; reject(["lock.getter"], "lock receiver")
        }
        for (index, name) in ["isUILocked", "isLockScreenVisible", "isUIUnlocking"].enumerated() {
            for encoding in badGetters + ["B@:i"] where encoding != "B@:" {
                SystemMuteFixture.recover(); SystemMuteFixture.lock = SystemMuteFixture.makeLock(overrides: [name: encoding])
                reject(Array(SystemMuteFixture.lockTrace.prefix(index + 1)), "lock ABI")
            }
            SystemMuteFixture.recover(); SystemMuteFixture.lock = SystemMuteFixture.makeLock(missing: [name])
            reject(Array(SystemMuteFixture.lockTrace.prefix(index + 1)), "missing lock state")
        }
        accepted(direct: true, old: false)
    }
    static func getterProbe(role: String, shape: String) {
        require(["lock", "app", "workspace"].contains(role), "invalid root probe role")
        let encoding: String? = shape == "missing" ? nil : shape
        require(shape == "missing" || badGetters.contains(shape), "invalid root probe shape")
        SystemMuteFixture.setup(role: role, encoding: encoding)
        let trace = role == "lock" ? [] : (SystemMuteFixture.lockTrace + (role == "workspace" ? ["app.getter"] : []))
        reject(trace, "class singleton getter ABI")
        print("SYSTEM_MUTE_GETTER_PROBE_PASS: \(assertions) assertions; role=\(role); shape=\(shape)"); fflush(stdout)
    }
    static func isolatedGetters() {
        for role in ["lock", "app", "workspace"] {
            for shape in ["missing"] + badGetters {
                let process = Process(), output = Pipe()
                process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = ["--getter-probe", role, shape]
                process.standardOutput = output; process.standardError = output
                do { try process.run() } catch { fail("isolated getter process failed: \(error)") }
                let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                let pattern = "\\ASYSTEM_MUTE_GETTER_PROBE_PASS: [1-9][0-9]* assertions; role=" + role + "; shape=" + NSRegularExpression.escapedPattern(for: shape) + "\n\\z"
                require(process.terminationReason == .exit && process.terminationStatus == 0 && text.range(of: pattern, options: .regularExpression) != nil, "isolated getter failed: " + text)
            }
        }
    }
    static func runtime() {
        require(Thread.isMainThread, "runtime must begin on main")
        let snapshot = CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        SystemMuteFixture.setup(); admission(); owners(); ringerABI()
        for direct in [true, false] { for old in [false, true] { accepted(direct: direct, old: old) } }
        isolatedGetters()
        require(sync() && same(CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost), snapshot), "provider mutated preferences")
    }
    #endif
    static func main() {
        let args = CommandLine.arguments
        #if !SYSTEM_MUTE_BASELINE
        if args.count == 4 && args[1] == "--getter-probe" { getterProbe(role: args[2], shape: args[3]); return }
        #endif
        require(TapLockPreferences.domain == "com.tsangbaby.taplock" && TapLockPreferences.actionKey == "DoubleTapAction" && TapLockPreferences.enabledKey == "Enabled", "namespace changed")
        require(sync(), "initial synchronization failed")
        let action = stored(TapLockPreferences.actionKey), enabled = stored(TapLockPreferences.enabledKey)
        cleanup = {
            for (key, value) in [(TapLockPreferences.actionKey, action), (TapLockPreferences.enabledKey, enabled)] {
                CFPreferencesSetValue(key as CFString, value, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            }
            return sync() && same(stored(TapLockPreferences.actionKey), action) && same(stored(TapLockPreferences.enabledKey), enabled)
        }
        #if SYSTEM_MUTE_BASELINE
        require(args.count == 2 && args[1] == "--baseline", "expected exact baseline mode")
        raw(TapLockPreferences.actionKey, ["kind": "systemMute"] as CFDictionary)
        // Compiles only old Preferences: no new case or provider reference here.
        require(TapLockPreferences.readAction() != .unavailable, "persisted systemMute action is unavailable")
        require(cleanup?() == true, "preference restoration failed"); cleanup = nil
        print("SYSTEM_MUTE_BASELINE_UNEXPECTED_SUCCESS")
        #else
        require(args.count == 2 && args[1] == "--current", "expected exact current mode")
        preferences(); runtime()
        require(cleanup?() == true, "preference restoration failed"); cleanup = nil
        print("SYSTEM_MUTE_RUNTIME_PASS: \(assertions) assertions; mode=--current; actual production Swift/Objective-C fixtures, NOT handset ringer/HUD proof")
        #endif
        fflush(stdout)
    }
}
