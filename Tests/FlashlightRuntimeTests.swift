import Foundation
import CoreFoundation
import ObjectiveC
import Darwin

#if !FLASHLIGHT_BASELINE
// Only these project-owned Objective-C identities replace unavailable OS lookups.
// No Swift/system registered method metadata is replaced or mutated. Every bad
// signature is installed on a newly allocated disposable fixture class.
private enum FlashlightFixture {
    static let lockName = "TLFlashlightLockManagerFixture"
    static let controllerName = "TLFlashlightControllerFixture"
    static var lockType: AnyClass = NSObject.self
    static var controllerType: AnyClass = NSObject.self
    static var lock: NSObject?
    static var controller: NSObject?
    static var serial = 0
    static var events: [String] = []
    static var wrongReceiver = false
    static var wrongSelector = false
    static var allOnMain = true
    static var locked = false, visible = false, unlocking = false
    static var level: UInt64 = 0
    static var savedLevel: UInt64 = 4
    static var submittedLevels: [UInt64] = []
    // Deliberately never changed by the void effect implementations. Local true
    // and recorded requests must not be confused with observed hardware state.
    static var lightIsOn = false
    static let lockTrace = ["lock.getter", "lock.locked", "lock.visible", "lock.unlocking"]

    struct Entry {
        let name: String
        let encoding: String
        let body: IMP
    }
    static func record(_ event: String, _ receiver: AnyObject, expected: AnyObject?) {
        events.append(event)
        allOnMain = allOnMain && Thread.isMainThread
        if let expected = expected {
            wrongReceiver = wrongReceiver || ObjectIdentifier(receiver) != ObjectIdentifier(expected)
        } else { wrongReceiver = true }
    }
    static let lockGetter: @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>? = { receiver, selector in
        record("lock.getter", receiver, expected: lockType as AnyObject)
        wrongSelector = wrongSelector || NSStringFromSelector(selector) != "sharedInstanceIfExists"
        return lock.map { Unmanaged.passUnretained($0 as AnyObject) }
    }
    static let controllerGetter: @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>? = { receiver, selector in
        record("flashlight.getter", receiver, expected: controllerType as AnyObject)
        wrongSelector = wrongSelector || NSStringFromSelector(selector) != "sharedInstance"
        return controller.map { Unmanaged.passUnretained($0 as AnyObject) }
    }
    static let lockState: @convention(c) (AnyObject, Selector) -> Bool = { receiver, selector in
        let name = NSStringFromSelector(selector)
        switch name {
        case "isUILocked": record("lock.locked", receiver, expected: lock); return locked
        case "isLockScreenVisible": record("lock.visible", receiver, expected: lock); return visible
        case "isUIUnlocking": record("lock.unlocking", receiver, expected: lock); return unlocking
        default: wrongSelector = true; return true
        }
    }
    static let readLevel: @convention(c) (AnyObject, Selector) -> UInt64 = { receiver, selector in
        switch NSStringFromSelector(selector) {
        case "level": record("flashlight.level", receiver, expected: controller); return level
        case "_loadFlashlightLevel": record("flashlight.load", receiver, expected: controller); return savedLevel
        default: wrongSelector = true; return 0
        }
    }
    static let turnOff: @convention(c) (AnyObject, Selector) -> Void = { receiver, selector in
        record("flashlight.off", receiver, expected: controller)
        wrongSelector = wrongSelector || NSStringFromSelector(selector) != "_turnPowerOff"
    }
    static let setLevel: @convention(c) (AnyObject, Selector, UInt64) -> Void = { receiver, selector, value in
        record("flashlight.set", receiver, expected: controller)
        wrongSelector = wrongSelector || NSStringFromSelector(selector) != "setLevel:"
        submittedLevels.append(value)
    }

    static func install(_ entries: [Entry], in type: AnyClass) {
        for entry in entries {
            let selector = NSSelectorFromString(entry.name)
            FlashlightRuntimeTests.require(class_addMethod(type, selector, entry.body, entry.encoding),
                                           "fixture method registration failed: " + entry.name)
            guard let method = class_getInstanceMethod(type, selector),
                  let encoding = method_getTypeEncoding(method) else {
                FlashlightRuntimeTests.fail("fixture metadata readback missing")
            }
            FlashlightRuntimeTests.require(String(cString: encoding) == entry.encoding,
                                           "fixture metadata readback differs: " + entry.name)
        }
    }
    static func allocate(_ name: String, superclass: AnyClass) -> AnyClass {
        FlashlightRuntimeTests.require(NSClassFromString(name) == nil, "fixture class identity already exists: " + name)
        guard let type = objc_allocateClassPair(superclass, name, 0) else {
            FlashlightRuntimeTests.fail("fixture class allocation failed")
        }
        return type
    }
    static func instance(_ type: AnyClass) -> NSObject {
        guard let value = class_createInstance(type, 0) as? NSObject else {
            FlashlightRuntimeTests.fail("fixture object allocation failed")
        }
        return value
    }
    static func root(_ name: String, getter: String, encoding: String?, body: IMP) -> AnyClass {
        let type = allocate(name, superclass: NSObject.self)
        guard let meta = object_getClass(type as AnyObject) else { FlashlightRuntimeTests.fail("missing fixture metaclass") }
        if let encoding = encoding { install([Entry(name: getter, encoding: encoding, body: body)], in: meta) }
        objc_registerClassPair(type)
        FlashlightRuntimeTests.require(NSClassFromString(name).map { ObjectIdentifier($0) } == ObjectIdentifier(type),
                                       "NSClassFromString resolved wrong fixture")
        return type
    }
    static func setup(role: String = "", encoding: String? = "@@:") {
        if role.isEmpty {
            FlashlightRuntimeTests.require(NSClassFromString(lockName) == nil && NSClassFromString(controllerName) == nil,
                                           "project fixture name collided with an existing runtime class")
            reset()
            FlashlightRuntimeTests.require(!FlashlightAction.toggle() && events.isEmpty && noLevelOrEffects(),
                                           "missing lock manager class was not rejected before singleton access")
        }
        lockType = root(lockName, getter: "sharedInstanceIfExists", encoding: role == "lock" ? encoding : "@@:",
                        body: unsafeBitCast(lockGetter, to: IMP.self))
        lock = makeLock()
        if role.isEmpty {
            reset()
            FlashlightRuntimeTests.require(!FlashlightAction.toggle() && events == lockTrace && noLevelOrEffects(),
                                           "missing controller class was not rejected before flashlight state/effect")
            integrity()
        }
        controllerType = root(controllerName, getter: "sharedInstance", encoding: role == "controller" ? encoding : "@@:",
                              body: unsafeBitCast(controllerGetter, to: IMP.self))
        controller = makeController()
        FlashlightRuntimeTests.require(lock!.isKind(of: lockType) && controller!.isKind(of: controllerType),
                                       "live fixture receiver has wrong class ancestry")
    }
    static func subclass(_ root: AnyClass, entries: [Entry]) -> NSObject {
        serial += 1
        let name = "TLFlashlightDisposableFixture_\(serial)"
        let type = allocate(name, superclass: root)
        install(entries, in: type)
        objc_registerClassPair(type)
        return instance(type)
    }
    static func makeController(overrides: [String: String] = [:], missing: Set<String> = []) -> NSObject {
        let entries = [
            Entry(name: "level", encoding: "Q@:", body: unsafeBitCast(readLevel, to: IMP.self)),
            Entry(name: "_loadFlashlightLevel", encoding: "Q@:", body: unsafeBitCast(readLevel, to: IMP.self)),
            Entry(name: "_turnPowerOff", encoding: "v@:", body: unsafeBitCast(turnOff, to: IMP.self)),
            Entry(name: "setLevel:", encoding: "v@:Q", body: unsafeBitCast(setLevel, to: IMP.self)),
        ]
        return subclass(controllerType, entries: entries.filter { !missing.contains($0.name) }.map {
            Entry(name: $0.name, encoding: overrides[$0.name] ?? $0.encoding, body: $0.body)
        })
    }
    static func makeLock(overrides: [String: String] = [:], missing: Set<String> = []) -> NSObject {
        return subclass(lockType, entries: ["isUILocked", "isLockScreenVisible", "isUIUnlocking"].filter {
            !missing.contains($0)
        }.map { Entry(name: $0, encoding: overrides[$0] ?? "B@:", body: unsafeBitCast(lockState, to: IMP.self)) })
    }
    static func reset() {
        events = []; submittedLevels = []; wrongReceiver = false; wrongSelector = false; allOnMain = true
    }
    static func noLevelOrEffects() -> Bool {
        return !events.contains { ["flashlight.level", "flashlight.load", "flashlight.off", "flashlight.set"].contains($0) }
            && submittedLevels.isEmpty && !lightIsOn
    }
    static func integrity() {
        FlashlightRuntimeTests.require(!wrongReceiver && !wrongSelector && allOnMain,
                                       "request receiver/selector/main-thread contract changed")
    }
}
#endif

@main
struct FlashlightRuntimeTests {
    static var assertions = 0
    static var cleanup: (() -> Bool)?
    static func fail(_ message: String) -> Never {
        let restore = cleanup; cleanup = nil
        if restore?() == false {
            print("FLASHLIGHT_RUNTIME_FAIL: preference restoration failed"); fflush(stdout); exit(2)
        }
        print("FLASHLIGHT_RUNTIME_FAIL: " + message); fflush(stdout); exit(1)
    }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
        assertions += 1
    }
    static func same(_ left: CFPropertyList?, _ right: CFPropertyList?) -> Bool {
        switch (left, right) {
        case (nil, nil): return true
        case let (left?, right?): return CFEqual(left, right)
        default: return false
        }
    }
    static func sync() -> Bool {
        CFPreferencesSynchronize(TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    static func stored(_ key: String) -> CFPropertyList? {
        CFPreferencesCopyValue(key as CFString, TapLockPreferences.domain as CFString,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    static func raw(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetValue(key as CFString, value, TapLockPreferences.domain as CFString,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        require(sync(), "fixture preference write failed")
    }

    #if !FLASHLIGHT_BASELINE
    static func preferences() {
        let actions: [(TapLockPreferences.Action, [String: String])] = [
            (.lock, ["kind": "lock"]),
            (.openApp("com.example.flashlightfixture"), ["kind": "openApp", "bundleIdentifier": "com.example.flashlightfixture"]),
            (.controlCenter, ["kind": "controlCenter"]), (.notificationCenter, ["kind": "notificationCenter"]),
            (.screenshot, ["kind": "screenshot"]), (.appSwitcher, ["kind": "appSwitcher"]),
            (.playPause, ["kind": "playPause"]), (.previousTrack, ["kind": "previousTrack"]),
            (.nextTrack, ["kind": "nextTrack"]), (.flashlight, ["kind": "flashlight"]),
        ]
        require(actions.count == 10, "incomplete mutually exclusive action matrix")
        for enabled in [nil, kCFBooleanFalse, kCFBooleanTrue] as [CFPropertyList?] {
            raw(TapLockPreferences.enabledKey, enabled)
            require(TapLockPreferences.readEnabled() == (enabled.map { CFEqual($0, kCFBooleanTrue) } ?? false),
                    "enable value/default changed")
            for (before, record) in actions {
                for (after, replacement) in actions {
                    raw(TapLockPreferences.actionKey, record as CFDictionary)
                    require(TapLockPreferences.readAction() == before, "existing action decode changed")
                    require(TapLockPreferences.writeAction(after), "single-value action replacement failed")
                    require(TapLockPreferences.readAction() == after, "single-value replacement did not round-trip")
                    require(same(stored(TapLockPreferences.actionKey), replacement as CFDictionary),
                            "replacement retained another action or stale App target")
                    require(same(stored(TapLockPreferences.enabledKey), enabled), "action selection changed enable state")
                }
            }
        }
        let malformed: [CFPropertyList] = [
            ["kind": "flashlight", "extra": "bad"] as CFDictionary,
            ["kind": "flashlight", "bundleIdentifier": "com.example.app"] as CFDictionary,
            ["kind": "flashlight", "target": "com.example.app"] as CFDictionary,
            ["kind": "flashlight", "enabled": true] as CFDictionary,
            ["kind": "flashlight", "actions": ["lock"]] as CFDictionary,
            ["kind": "Flashlight"] as CFDictionary, ["kind": "FLASHLIGHT"] as CFDictionary,
            ["kind": " flashlight"] as CFDictionary, ["kind": "flashlight "] as CFDictionary,
            ["kind": "flashlight\n"] as CFDictionary, ["kind": "Siri"] as CFDictionary,
            ["kind": "siri"] as CFDictionary, ["kind": true] as CFDictionary,
            ["kind": 1] as CFDictionary, ["kind": ["flashlight"]] as CFDictionary,
            ["kind": ["flashlight": true]] as CFDictionary, [:] as CFDictionary,
            "flashlight" as CFString, ["flashlight"] as CFArray, NSNumber(value: true), NSNumber(value: 4),
        ]
        let enabled = stored(TapLockPreferences.enabledKey)
        for value in malformed {
            raw(TapLockPreferences.actionKey, value)
            require(TapLockPreferences.readAction() == .unavailable, "malformed/unsupported action was admitted")
            require(same(stored(TapLockPreferences.actionKey), value), "invalid read rewrote the action")
            require(same(stored(TapLockPreferences.enabledKey), enabled), "invalid action changed enable state")
        }
        raw(TapLockPreferences.actionKey, nil)
        require(TapLockPreferences.readAction() == .lock && stored(TapLockPreferences.actionKey) == nil,
                "missing action fallback changed or persisted")
        require(TapLockPreferences.defaultEnabled == false, "enable default changed")
        require(TapLockPreferences.writeAction(.flashlight), "valid flashlight did not recover after malformed records")
        let selected = stored(TapLockPreferences.actionKey)
        require(!TapLockPreferences.writeAction(.unavailable) && !TapLockPreferences.writeAction(.openApp("")),
                "invalid action write was admitted")
        require(same(stored(TapLockPreferences.actionKey), selected) && same(stored(TapLockPreferences.enabledKey), enabled),
                "rejected write mutated stored action/enable")
    }

    static func accepted(level: UInt64, saved: UInt64, repetitions: Int = 1) {
        FlashlightFixture.level = level; FlashlightFixture.savedLevel = saved
        FlashlightFixture.reset()
        for _ in 0..<repetitions { require(FlashlightAction.toggle(), "valid void effect attempt was rejected") }
        let branch = level == 0 ? ["flashlight.load", "flashlight.set"] : ["flashlight.off"]
        let trace = FlashlightFixture.lockTrace + ["flashlight.getter", "flashlight.level"] + branch
        require(FlashlightFixture.events == Array(repeating: trace, count: repetitions).flatMap { $0 },
                "branch/state read/getter/effect must occur exactly once and in order")
        require(FlashlightFixture.submittedLevels == (level == 0 ? Array(repeating: saved, count: repetitions) : []),
                "saved UInt64 level was narrowed, changed or submitted on nonzero branch")
        require(FlashlightFixture.level == level && FlashlightFixture.savedLevel == saved && !FlashlightFixture.lightIsOn,
                "fixture effect changed observed state; local true is not hardware completion")
        FlashlightFixture.integrity()
    }
    static func recover() {
        FlashlightFixture.lock = FlashlightFixture.makeLock()
        FlashlightFixture.controller = FlashlightFixture.makeController()
        FlashlightFixture.locked = false; FlashlightFixture.visible = false; FlashlightFixture.unlocking = false
        accepted(level: 0, saved: 4)
    }
    static func rejectController(_ receiver: NSObject?, label: String) {
        FlashlightFixture.controller = receiver
        // Both branches must fail preflight even if the incompatible method would
        // not have been used by that branch. No level read can precede preflight.
        for value in [UInt64(0), UInt64(4)] {
            FlashlightFixture.level = value; FlashlightFixture.reset()
            require(!FlashlightAction.toggle(), "incompatible controller admitted: " + label)
            require(FlashlightFixture.events == FlashlightFixture.lockTrace + ["flashlight.getter"] &&
                    FlashlightFixture.noLevelOrEffects(), "ABI/identity rejection read state or attempted effect: " + label)
            FlashlightFixture.integrity()
        }
        recover()
    }
    static func controllerABI() {
        for receiver in [nil, NSObject(), FlashlightFixture.instance(FlashlightFixture.controllerType)] as [NSObject?] {
            rejectController(receiver, label: "nil/unrelated/missing all methods")
        }
        for selector in ["level", "_loadFlashlightLevel", "_turnPowerOff", "setLevel:"] {
            rejectController(FlashlightFixture.makeController(missing: [selector]), label: "missing " + selector)
            let result = ["level", "_loadFlashlightLevel"].contains(selector) ? "Q" : "v"
            let argument = selector == "setLevel:" ? "Q" : ""
            for wrongReturn in ["q", "Q", "B", "i", "@", "d", "v"] where wrongReturn != result {
                rejectController(FlashlightFixture.makeController(overrides: [selector: wrongReturn + "@:" + argument]),
                                 label: selector + " return=" + wrongReturn)
            }
            // All these are valid runtime encoding tokens but deliberately wrong
            // ABI shapes. Their IMPs must never run under mismatched metadata.
            for encoding in [result + "i:" + argument, result + "#:" + argument,
                             result + "@i" + argument, result + "@@" + argument,
                             result + "@:" + argument + "Q", result + "@:"] {
                if encoding == result + "@:" + argument { continue }
                rejectController(FlashlightFixture.makeController(overrides: [selector: encoding]),
                                 label: selector + " arity/implicit=" + encoding)
            }
        }
        for argument in ["q", "B"] {
            rejectController(FlashlightFixture.makeController(overrides: ["setLevel:": "v@:" + argument]),
                             label: "setLevel argument=" + argument)
        }
    }
    static func lockAdmission() {
        for mask in 1..<8 {
            FlashlightFixture.locked = mask & 1 != 0
            FlashlightFixture.visible = mask & 2 != 0
            FlashlightFixture.unlocking = mask & 4 != 0
            FlashlightFixture.reset()
            require(!FlashlightAction.toggle(), "locked/visible/unlocking state was admitted")
            let expected = FlashlightFixture.locked ? Array(FlashlightFixture.lockTrace.prefix(2)) :
                (FlashlightFixture.visible ? Array(FlashlightFixture.lockTrace.prefix(3)) : FlashlightFixture.lockTrace)
            require(FlashlightFixture.events == expected && FlashlightFixture.noLevelOrEffects(),
                    "lock refusal accessed controller or effect")
            FlashlightFixture.integrity()
        }
        FlashlightFixture.locked = false; FlashlightFixture.visible = false; FlashlightFixture.unlocking = false
        var receivers: [(NSObject?, [String])] = [
            (nil, ["lock.getter"]), (NSObject(), ["lock.getter"]),
            (FlashlightFixture.instance(FlashlightFixture.lockType), ["lock.getter"]),
        ]
        for (index, selector) in ["isUILocked", "isLockScreenVisible", "isUIUnlocking"].enumerated() {
            let expected = Array(FlashlightFixture.lockTrace.prefix(index + 1))
            receivers.append((FlashlightFixture.makeLock(missing: [selector]), expected))
            for encoding in ["q@:", "Q@:", "i@:", "@@:", "d@:", "v@:", "B@:Q", "Bi:", "B@i"] {
                receivers.append((FlashlightFixture.makeLock(overrides: [selector: encoding]), expected))
            }
        }
        for (receiver, expected) in receivers {
            FlashlightFixture.lock = receiver; FlashlightFixture.reset()
            require(!FlashlightAction.toggle(), "nil/unrelated/malformed lock state was admitted")
            require(FlashlightFixture.events == expected && FlashlightFixture.noLevelOrEffects(),
                    "lock identity/ABI rejection invoked malformed getter or accessed flashlight singleton")
            FlashlightFixture.integrity()
            recover()
        }
        recover()
    }
    private final class ThreadResult: @unchecked Sendable {
        var admitted = true
        var main = true
    }
    static func offMain() {
        FlashlightFixture.reset()
        let result = ThreadResult(), done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            result.main = Thread.isMainThread
            result.admitted = FlashlightAction.toggle()
            done.signal()
        }
        require(done.wait(timeout: .now() + 5) == .success, "off-main fixture timed out")
        require(!result.main && !result.admitted, "off-main request was admitted or test ran on main")
        require(FlashlightFixture.events.isEmpty && FlashlightFixture.noLevelOrEffects(), "off-main request accessed any private getter")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        require(FlashlightFixture.events.isEmpty && FlashlightFixture.noLevelOrEffects(), "off-main rejection queued delayed work")
        accepted(level: 1, saved: 4)
    }
    static let getterShapes = ["missing", "return-q", "return-Q", "return-B", "return-i", "return-d", "return-v",
                               "argument-q", "argument-Q", "argument-B", "self-i", "cmd-i"]
    static func getterEncoding(_ shape: String) -> String? {
        if shape == "missing" { return nil }
        if shape.hasPrefix("return-") { return String(shape.suffix(1)) + "@:" }
        if shape.hasPrefix("argument-") { return "@@:" + String(shape.suffix(1)) }
        return shape == "self-i" ? "@i:" : "@@i"
    }
    static func getterProbe(role: String, shape: String) {
        require(["lock", "controller"].contains(role) && getterShapes.contains(shape), "unknown isolated getter probe")
        FlashlightFixture.setup(role: role, encoding: getterEncoding(shape))
        FlashlightFixture.reset()
        require(!FlashlightAction.toggle(), "incompatible class getter ABI was admitted")
        require(FlashlightFixture.events == (role == "lock" ? [] : FlashlightFixture.lockTrace) &&
                FlashlightFixture.noLevelOrEffects(), "malformed/missing getter was invoked or accessed downstream state")
        FlashlightFixture.integrity()
        print("FLASHLIGHT_GETTER_PROBE_PASS: \(assertions) assertions; role=\(role); shape=\(shape)")
        fflush(stdout)
    }
    static func isolatedGetterMatrix() {
        // Each process owns fresh classes: no method swizzling, class mutation,
        // stale objc dispatch caches or live/system class collisions are possible.
        for role in ["lock", "controller"] {
            for shape in getterShapes {
                let process = Process(), output = Pipe()
                process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                process.arguments = ["--getter-probe", role, shape]
                process.standardOutput = output; process.standardError = output
                do { try process.run() } catch { fail("isolated getter process failed: \(error)") }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                let pattern = "\\AFLASHLIGHT_GETTER_PROBE_PASS: [1-9][0-9]* assertions; role=" + role + "; shape=" +
                    NSRegularExpression.escapedPattern(for: shape) + "\n\\z"
                require(process.terminationReason == .exit && process.terminationStatus == 0 &&
                        text.range(of: pattern, options: .regularExpression) != nil,
                        "isolated getter assertion/transport failed: " + role + "/" + shape + ": " + text)
            }
        }
    }
    static func runtime() {
        require(Thread.isMainThread, "runtime must begin on main")
        FlashlightFixture.setup()
        let snapshot = CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString,
                                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        offMain()
        lockAdmission()
        controllerABI()
        // Width probes are ABI stress values, not assertions about a real OS's
        // legal hardware brightness domain. Saved level differs across requests.
        for saved in [UInt64(0), UInt64(1), UInt64(4), UInt64(1) << 63, UInt64.max] {
            accepted(level: 0, saved: saved, repetitions: 3)
        }
        for level in [UInt64(1), UInt64(4), UInt64(1) << 63, UInt64.max] {
            accepted(level: level, saved: 2, repetitions: 3)
        }
        isolatedGetterMatrix()
        require(sync() && same(CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString,
                                                        kCFPreferencesCurrentUser, kCFPreferencesAnyHost), snapshot),
                "flashlight provider changed preferences")
        FlashlightFixture.lock = nil; FlashlightFixture.controller = nil
    }
    #endif

    static func main() {
        let args = CommandLine.arguments
        #if !FLASHLIGHT_BASELINE
        if args.count == 4 && args[1] == "--getter-probe" {
            getterProbe(role: args[2], shape: args[3]); return
        }
        #endif
        require(TapLockPreferences.domain == "com.tsangbaby.taplock" && TapLockPreferences.actionKey == "DoubleTapAction" &&
                TapLockPreferences.enabledKey == "Enabled", "preference namespace changed")
        require(sync(), "initial preference synchronization failed")
        let action = stored(TapLockPreferences.actionKey), enabled = stored(TapLockPreferences.enabledKey)
        cleanup = {
            for (key, value) in [(TapLockPreferences.actionKey, action), (TapLockPreferences.enabledKey, enabled)] {
                CFPreferencesSetValue(key as CFString, value, TapLockPreferences.domain as CFString,
                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            }
            return sync() && same(stored(TapLockPreferences.actionKey), action) && same(stored(TapLockPreferences.enabledKey), enabled)
        }
        #if FLASHLIGHT_BASELINE
        require(args.count == 2 && args[1] == "--baseline", "expected exact baseline mode")
        raw(TapLockPreferences.actionKey, ["kind": "flashlight"] as CFDictionary)
        // Intentionally the same behavior contract, without referencing the new
        // enum case, so unmodified 0.1.11 compiles and reaches the precise RED.
        require(TapLockPreferences.readAction() != .unavailable, "persisted flashlight action is unavailable")
        require(cleanup?() == true, "preference restoration failed"); cleanup = nil
        print("FLASHLIGHT_BASELINE_UNEXPECTED_SUCCESS")
        #else
        require(args.count == 2 && args[1] == "--current", "expected exact current mode")
        preferences()
        runtime()
        require(cleanup?() == true, "preference restoration failed"); cleanup = nil
        print("FLASHLIGHT_RUNTIME_PASS: \(assertions) assertions; mode=--current; actual production Swift/Objective-C fixtures, NOT hardware effect proof")
        #endif
        fflush(stdout)
    }
}
