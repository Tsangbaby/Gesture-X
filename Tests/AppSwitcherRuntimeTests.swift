import Foundation
import CoreFoundation
import ObjectiveC
import Darwin

#if !APP_SWITCHER_BASELINE
// The production implementation and ABI checker run unchanged except for the
// runner's counted, invertible OS-class-lookup rebinding in disposable copies.
@objc(TLAppSwitcherLockManagerFixture)
class SwitcherLockFixture: NSObject {
    static var current: NSObject?
    static var getterCalls = 0
    var fallbackCalls = 0
    @objc class func sharedInstanceIfExists() -> NSObject? { getterCalls += 1; return current }
    @objc(lockUIFromSource:withOptions:)
    func lock(_ source: Int32, options: NSDictionary?) { fallbackCalls += 1 }
}
class SwitcherUnlockedFixture: SwitcherLockFixture {
    var locked = false, visible = false, unlocking = false
    @objc func isUILocked() -> Bool { locked }
    @objc func isLockScreenVisible() -> Bool { visible }
    @objc func isUIUnlocking() -> Bool { unlocking }
}
class SwitcherWrongLockStateFixture: SwitcherLockFixture {
    var stateCalls = 0
    @objc func isUILocked() -> Int64 { stateCalls += 1; return 0 }
    @objc func isLockScreenVisible() -> Bool { false }
    @objc func isUIUnlocking() -> Bool { false }
}

@objc(TLAppSwitcherControllerFixture)
class SwitcherControllerFixture: NSObject {
    static var current: NSObject?
    static var getterCalls = 0
    var nativeCalls = 0, fallbackCalls = 0
    var sources: [Int64] = [], animations: [Bool] = [], mainThread: [Bool] = []
    @objc class func sharedInstanceIfExists() -> NSObject? { getterCalls += 1; return current }
    @objc func toggleSwitcherNoninteractively() { fallbackCalls += 1 }
    @objc(dismissMainSwitcherNoninteractivelyAnimated:)
    func dismiss(_ animated: Bool) { fallbackCalls += 1 }
    @objc func _simulateHomeButtonPress() { fallbackCalls += 1 }
}
class SwitcherStateFixture: SwitcherControllerFixture {
    var mainVisible = false, anyVisible = false
    @objc func isMainSwitcherVisible() -> Bool { mainVisible }
    @objc func isAnySwitcherVisible() -> Bool { anyVisible }
}
class SwitcherWorkingFixture: SwitcherStateFixture {
    var acceptsRequest = true
    @objc(activateMainSwitcherNoninteractivelyWithSource:animated:)
    func open(_ source: Int64, animated: Bool) -> Bool {
        nativeCalls += 1; sources.append(source); animations.append(animated); mainThread.append(Thread.isMainThread)
        // Acceptance is intentionally not a visual transition or visibility change.
        return acceptsRequest
    }
}
class SwitcherWrongReturnFixture: SwitcherStateFixture {
    @objc(activateMainSwitcherNoninteractivelyWithSource:animated:)
    func open(_ source: Int64, animated: Bool) -> Int64 { nativeCalls += 1; return 1 }
}
class SwitcherWrongSourceFixture: SwitcherStateFixture {
    @objc(activateMainSwitcherNoninteractivelyWithSource:animated:)
    func open(_ source: Int32, animated: Bool) -> Bool { nativeCalls += 1; return true }
}
class SwitcherWrongAnimationFixture: SwitcherStateFixture {
    @objc(activateMainSwitcherNoninteractivelyWithSource:animated:)
    func open(_ source: Int64, animated: Int8) -> Bool { nativeCalls += 1; return true }
}
class SwitcherWrongStateFixture: SwitcherControllerFixture {
    var stateCalls = 0
    @objc func isAnySwitcherVisible() -> Int64 { stateCalls += 1; return 0 }
    @objc func isMainSwitcherVisible() -> Bool { false }
    @objc(activateMainSwitcherNoninteractivelyWithSource:animated:)
    func open(_ source: Int64, animated: Bool) -> Bool { nativeCalls += 1; return true }
}
class SwitcherUnrelatedFixture: NSObject {
    var nativeCalls = 0
    @objc func isAnySwitcherVisible() -> Bool { false }
    @objc func isMainSwitcherVisible() -> Bool { false }
    @objc(activateMainSwitcherNoninteractivelyWithSource:animated:)
    func open(_ source: Int64, animated: Bool) -> Bool { nativeCalls += 1; return true }
}
class SwitcherWrongArityFixture: SwitcherStateFixture {}
class SwitcherWrongSelfFixture: SwitcherStateFixture {}
class SwitcherWrongCommandFixture: SwitcherStateFixture {}
#endif

@main
struct AppSwitcherRuntimeTests {
    static var assertions = 0
    static var cleanup: (() -> Bool)?
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            if cleanup?() == false { print("APP_SWITCHER_RUNTIME_FAIL: preference restoration failed"); fflush(stdout); exit(2) }
            cleanup = nil
            print("APP_SWITCHER_RUNTIME_FAIL: \(message)"); fflush(stdout); exit(1)
        }
        assertions += 1
    }
    static func same(_ lhs: CFPropertyList?, _ rhs: CFPropertyList?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (left?, right?): return CFEqual(left, right)
        default: return false
        }
    }
    static func stored(_ key: String) -> CFPropertyList? {
        CFPreferencesCopyValue(key as CFString, TapLockPreferences.domain as CFString,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    static func synchronize() -> Bool {
        CFPreferencesSynchronize(TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    static func raw(_ value: CFPropertyList?) {
        CFPreferencesSetValue(TapLockPreferences.actionKey as CFString, value,
                              TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        require(synchronize(), "fixture preference write failed")
    }
    #if !APP_SWITCHER_BASELINE
    static func preferences(_ originalEnabled: CFPropertyList?) {
        require(TapLockPreferences.readAction() == .appSwitcher, "wrong decoded App Switcher action")
        require(TapLockPreferences.writeAction(.appSwitcher), "App Switcher did not persist")
        require(same(stored(TapLockPreferences.actionKey), ["kind": "appSwitcher"] as CFDictionary), "action record must contain only kind")
        require(TapLockPreferences.readAction() == .appSwitcher, "App Switcher did not round-trip")
        let malformed: [[String: Any]] = [
            ["kind": "appSwitcher", "bundleIdentifier": "com.example.app"],
            ["kind": "appSwitcher", "extra": "unexpected"], ["kind": "appSwitcher", "enabled": true],
            ["kind": "appSwitcher", "action": "lock"], ["kind": "AppSwitcher"], ["kind": "APPSWITCHER"],
            ["kind": "appSwitcher "], ["kind": ""], ["kind": "unknown"], ["kind": 1], ["kind": true],
            ["kind": ["appSwitcher"]], ["kind": ["kind": "appSwitcher"]], ["bundleIdentifier": "com.example.app"], [:]
        ]
        for record in malformed {
            raw(record as CFDictionary)
            require(TapLockPreferences.readAction() == .unavailable, "malformed App Switcher record accepted")
            require(same(stored(TapLockPreferences.actionKey), record as CFDictionary), "invalid read rewrote state")
        }
        for value in ["appSwitcher" as CFString, ["appSwitcher"] as CFArray, NSNumber(value: true)] as [CFPropertyList] {
            raw(value); require(TapLockPreferences.readAction() == .unavailable, "non-dictionary action accepted")
        }
        raw(nil)
        require(TapLockPreferences.readAction() == .lock && stored(TapLockPreferences.actionKey) == nil, "default lock changed or read persisted")
        let older: [(TapLockPreferences.Action, [String: String])] = [
            (.lock, ["kind": "lock"]), (.openApp("com.example.app"), ["kind": "openApp", "bundleIdentifier": "com.example.app"]),
            (.controlCenter, ["kind": "controlCenter"]), (.notificationCenter, ["kind": "notificationCenter"]),
            (.screenshot, ["kind": "screenshot"])
        ]
        for (action, record) in older {
            raw(record as CFDictionary)
            require(TapLockPreferences.readAction() == action, "older action decoding changed")
            require(TapLockPreferences.writeAction(.appSwitcher), "switch from older action failed")
            require(same(stored(TapLockPreferences.actionKey), ["kind": "appSwitcher"] as CFDictionary), "App Switcher retained old target")
            require(TapLockPreferences.writeAction(action) && TapLockPreferences.readAction() == action, "older action did not replace App Switcher")
            require(same(stored(TapLockPreferences.actionKey), record as CFDictionary), "older record changed")
        }
        require(TapLockPreferences.writeAction(.appSwitcher), "final action write failed")
        let before = stored(TapLockPreferences.actionKey)
        require(!TapLockPreferences.writeAction(.unavailable) && !TapLockPreferences.writeAction(.openApp("")), "invalid selection persisted")
        require(same(stored(TapLockPreferences.actionKey), before), "rejected selection changed state")
        require(same(stored(TapLockPreferences.enabledKey), originalEnabled), "selection changed enable state")
    }
    static func malformedMethods() {
        let selector = NSSelectorFromString("activateMainSwitcherNoninteractivelyWithSource:animated:")
        let body: @convention(c) (AnyObject, Selector, Int64, Bool) -> Bool = { receiver, _, _, _ in
            (receiver as? SwitcherControllerFixture)?.nativeCalls += 1; return true
        }
        for (type, encoding) in [(SwitcherWrongArityFixture.self, "B@:q"),
                                 (SwitcherWrongSelfFixture.self, "B#:qB"),
                                 (SwitcherWrongCommandFixture.self, "B@@qB")] as [(AnyClass, String)] {
            require(class_addMethod(type, selector, unsafeBitCast(body, to: IMP.self), encoding), "malformed method install failed")
            guard let method = class_getInstanceMethod(type, selector), let actual = method_getTypeEncoding(method) else {
                require(false, "malformed method missing"); return
            }
            require(String(cString: actual) == encoding, "fixture encoding normalized")
            require(PrivateAPI.checkedMethod(in: type, selector: selector, returns: "B", arguments: ["q", "B"]) == nil, "production checker accepted malformed ABI")
        }
    }
    static func runtime() {
        require(Thread.isMainThread, "harness must start on main")
        require(NSClassFromString("TLAppSwitcherLockManagerFixture").map { ObjectIdentifier($0) } == ObjectIdentifier(SwitcherLockFixture.self), "lock fixture identity collision")
        require(NSClassFromString("TLAppSwitcherControllerFixture").map { ObjectIdentifier($0) } == ObjectIdentifier(SwitcherControllerFixture.self), "controller fixture identity collision")
        malformedMethods()
        let lock = SwitcherUnlockedFixture(), controller = SwitcherWorkingFixture()
        SwitcherLockFixture.current = lock; SwitcherControllerFixture.current = controller
        require(LockAction.unlockedManager() === lock, "production lock admission failed")
        require(PrivateAPI.object(SwitcherControllerFixture.self as AnyObject, "sharedInstanceIfExists") === controller, "production singleton resolution failed")
        require(PrivateAPI.checkedMethod(in: SwitcherWorkingFixture.self,
            selector: NSSelectorFromString("activateMainSwitcherNoninteractivelyWithSource:animated:"),
            returns: "B", arguments: ["q", "B"]) != nil, "working ABI is not BOOL/int64/BOOL")
        let before = CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let getters = SwitcherControllerFixture.getterCalls
        require(AppSwitcherAction.open(), "native accepted request rejected")
        require(controller.nativeCalls == 1 && controller.sources == [0] && controller.animations == [true] && controller.mainThread == [true], "must submit exactly one animated native open on main with source zero")
        require(SwitcherControllerFixture.getterCalls == getters + 1, "open acquired singleton more than once")
        controller.acceptsRequest = false
        require(!AppSwitcherAction.open() && controller.nativeCalls == 2 && controller.fallbackCalls == 0, "native refusal was retried or reported as success")
        controller.acceptsRequest = true
        require(AppSwitcherAction.open() && controller.nativeCalls == 3, "valid request did not recover after refusal")
        require(!controller.mainVisible && !controller.anyVisible, "request return incorrectly implies visible UI")
        for states in [(true, false), (false, true), (true, true)] {
            controller.anyVisible = states.0; controller.mainVisible = states.1
            require(!AppSwitcherAction.open() && controller.nativeCalls == 3 && controller.fallbackCalls == 0, "visible switcher was toggled or activated again")
        }
        controller.mainVisible = false; controller.anyVisible = false
        let beforeBlocked = SwitcherControllerFixture.getterCalls
        lock.locked = true; require(!AppSwitcherAction.open(), "locked device admitted"); lock.locked = false
        lock.visible = true; require(!AppSwitcherAction.open(), "lock screen admitted"); lock.visible = false
        lock.unlocking = true; require(!AppSwitcherAction.open(), "unlock transition admitted"); lock.unlocking = false
        let badLock = SwitcherWrongLockStateFixture()
        for receiver in [nil, NSObject(), SwitcherLockFixture(), badLock] as [NSObject?] {
            SwitcherLockFixture.current = receiver
            require(!AppSwitcherAction.open(), "missing/wrong lock identity/state ABI admitted")
        }
        require(badLock.stateCalls == 0 && SwitcherControllerFixture.getterCalls == beforeBlocked, "blocked lock admission accessed controller or invalid getter")
        SwitcherLockFixture.current = lock
        let unrelated = SwitcherUnrelatedFixture()
        for receiver in [nil, NSObject(), unrelated] as [NSObject?] {
            SwitcherControllerFixture.current = receiver; require(!AppSwitcherAction.open(), "wrong/missing actual receiver admitted")
        }
        require(unrelated.nativeCalls == 0, "selector availability bypassed receiver identity")
        let badState = SwitcherWrongStateFixture()
        let rejected: [SwitcherControllerFixture] = [SwitcherControllerFixture(), SwitcherStateFixture(), badState,
            SwitcherWrongReturnFixture(), SwitcherWrongSourceFixture(), SwitcherWrongAnimationFixture(),
            SwitcherWrongArityFixture(), SwitcherWrongSelfFixture(), SwitcherWrongCommandFixture()]
        for receiver in rejected {
            SwitcherControllerFixture.current = receiver
            require(!AppSwitcherAction.open(), "missing selector or incompatible explicit/implicit ABI admitted")
            require(receiver.nativeCalls == 0 && receiver.fallbackCalls == 0, "invalid receiver invoked or fallback used")
        }
        require(badState.stateCalls == 0, "invalid visibility getter invoked")
        SwitcherControllerFixture.current = controller
        let lockGetters = SwitcherLockFixture.getterCalls, controllerGetters = SwitcherControllerFixture.getterCalls
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            require(!Thread.isMainThread && !AppSwitcherAction.open(), "off-main request admitted"); done.signal()
        }
        require(done.wait(timeout: .now() + 5) == .success, "off-main check timed out")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        require(SwitcherLockFixture.getterCalls == lockGetters && SwitcherControllerFixture.getterCalls == controllerGetters, "off-main/rejected request deferred singleton acquisition")
        require(controller.nativeCalls == 3 && controller.fallbackCalls == 0 && lock.fallbackCalls == 0, "rejected request scheduled later action")
        require(rejected.allSatisfy { $0.nativeCalls == 0 && $0.fallbackCalls == 0 }, "invalid receiver scheduled later work")
        require(AppSwitcherAction.open() && controller.nativeCalls == 4 && controller.sources == [0, 0, 0, 0] && controller.animations == [true, true, true, true] && controller.mainThread == [true, true, true, true], "valid open did not recover exactly once")
        require(same(CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost), before), "provider mutated preferences")
        SwitcherControllerFixture.current = nil; SwitcherLockFixture.current = nil
    }
    #endif
    static func main() {
        require(TapLockPreferences.domain == "com.tsangbaby.taplock" && TapLockPreferences.actionKey == "DoubleTapAction" && TapLockPreferences.enabledKey == "Enabled", "production preference namespace changed")
        require(synchronize(), "initial synchronization failed")
        let action = stored(TapLockPreferences.actionKey), enabled = stored(TapLockPreferences.enabledKey)
        cleanup = {
            CFPreferencesSetValue(TapLockPreferences.actionKey as CFString, action, TapLockPreferences.domain as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return synchronize() && same(stored(TapLockPreferences.actionKey), action) && same(stored(TapLockPreferences.enabledKey), enabled)
        }
        defer { _ = cleanup?() }
        raw(["kind": "appSwitcher"] as CFDictionary)
        require(TapLockPreferences.readAction() != .unavailable, "persisted App Switcher action is unavailable")
        #if APP_SWITCHER_BASELINE
        require(cleanup?() == true, "preference restoration failed"); cleanup = nil
        print("APP_SWITCHER_BASELINE_UNEXPECTED_SUCCESS")
        #else
        preferences(enabled); runtime()
        require(cleanup?() == true, "preference restoration failed"); cleanup = nil
        print("APP_SWITCHER_RUNTIME_PASS: \(assertions) assertions against production Swift; OS receivers are fixtures, NOT handset App Switcher proof")
        #endif
        fflush(stdout)
    }
}
