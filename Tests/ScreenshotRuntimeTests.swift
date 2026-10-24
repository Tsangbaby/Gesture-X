import Foundation
import CoreFoundation
import ObjectiveC
import Darwin

#if !SCREENSHOT_BASELINE
// Only unavailable OS receivers are fixtures. The runner rebinds exact class
// lookup literals in disposable copies; no production method or ABI gate changes.
@objc(TLSystemScreenshotLockManagerFixture)
class SystemScreenshotLockManagerFixture: NSObject {
    static var current: NSObject?
    static var getterCalls = 0
    var directLockCalls = 0
    @objc class func sharedInstanceIfExists() -> NSObject? {
        getterCalls += 1
        return current
    }
    @objc(lockUIFromSource:withOptions:)
    func lockUI(_ source: Int32, options: NSDictionary?) { directLockCalls += 1 }
}

class SystemScreenshotUnlockedFixture: SystemScreenshotLockManagerFixture {
    var locked = false
    var visible = false
    var unlocking = false
    @objc func isUILocked() -> Bool { locked }
    @objc func isLockScreenVisible() -> Bool { visible }
    @objc func isUIUnlocking() -> Bool { unlocking }
}

class SystemScreenshotWrongLockStateFixture: SystemScreenshotLockManagerFixture {
    var stateCalls = 0
    @objc func isUILocked() -> Int64 { stateCalls += 1; return 0 }
    @objc func isLockScreenVisible() -> Bool { false }
    @objc func isUIUnlocking() -> Bool { false }
}

@objc(TLSystemScreenshotApplicationFixture)
class SystemScreenshotApplicationFixture: NSObject {
    static var current: NSObject?
    static var getterCalls = 0
    var nativeCalls = 0
    var fallbackCalls = 0
    var requestWasOnMain: [Bool] = []
    @objc class func sharedApplication() -> NSObject? {
        getterCalls += 1
        return current
    }
    // A rejected screenshot must not become a lock, private alternative, or
    // completion-based request. These traps perform no system action.
    @objc func _simulateLockButtonPress() { fallbackCalls += 1 }
    @objc func _takeScreenshot() { fallbackCalls += 1 }
    @objc func saveScreenshot() { fallbackCalls += 1 }
    @objc(takeScreenshotWithCompletion:)
    func alternativeScreenshot(_ completion: NSObject?) { fallbackCalls += 1 }
}

class SystemScreenshotWorkingFixture: SystemScreenshotApplicationFixture {
    @objc(takeScreenshot)
    func nativeScreenshotRequest() {
        nativeCalls += 1
        requestWasOnMain.append(Thread.isMainThread)
        // A void request deliberately does not render, save, or report completion.
    }
}

class SystemScreenshotWrongReturnFixture: SystemScreenshotApplicationFixture {
    @objc(takeScreenshot)
    func incompatibleScreenshotRequest() -> Bool { nativeCalls += 1; return true }
}

class SystemScreenshotUnrelatedReceiverFixture: NSObject {
    var nativeCalls = 0
    @objc(takeScreenshot)
    func nativeScreenshotRequest() { nativeCalls += 1 }
}

// Swift correctly forbids an extra parameter on @objc(takeScreenshot). Install
// that deliberately incompatible Objective-C shape with class_addMethod instead.
// Separate subclasses keep malformed encodings away from the working fixture.
class SystemScreenshotWrongArgumentFixture: SystemScreenshotApplicationFixture {}
class SystemScreenshotWrongSelfFixture: SystemScreenshotApplicationFixture {}
class SystemScreenshotWrongCommandFixture: SystemScreenshotApplicationFixture {}
#endif

@main
struct ScreenshotRuntimeTests {
    static var assertions = 0
    static var cleanup: (() -> Bool)?

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            if cleanup?() == false {
                print("SCREENSHOT_RUNTIME_FAIL: preference restoration failed")
                fflush(stdout)
                exit(2)
            }
            cleanup = nil
            print("SCREENSHOT_RUNTIME_FAIL: \(message)")
            fflush(stdout)
            exit(1)
        }
        assertions += 1
    }

    static func sameValue(_ lhs: CFPropertyList?, _ rhs: CFPropertyList?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (left?, right?): return CFEqual(left, right)
        default: return false
        }
    }

    static func storedAction() -> CFPropertyList? {
        CFPreferencesCopyValue(TapLockPreferences.actionKey as CFString,
            TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    static func storedEnabled() -> CFPropertyList? {
        CFPreferencesCopyValue(TapLockPreferences.enabledKey as CFString,
            TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    static func domainSnapshot() -> CFPropertyList? {
        CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    static func rawAction(_ value: CFPropertyList?) {
        CFPreferencesSetValue(TapLockPreferences.actionKey as CFString, value,
            TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        require(CFPreferencesSynchronize(TapLockPreferences.domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost), "fixture preference write failed")
    }

    #if !SCREENSHOT_BASELINE
    static func requireRecord(_ expected: [String: String], _ message: String) {
        require(sameValue(storedAction(), expected as CFDictionary), message)
    }

    static func preferences(_ originalEnabled: CFPropertyList?) {
        let enabled = TapLockPreferences.readEnabled()
        require(TapLockPreferences.readAction() == .screenshot, "wrong decoded screenshot action")
        require(TapLockPreferences.writeAction(.screenshot), "screenshot action could not persist")
        requireRecord(["kind": "screenshot"], "screenshot record must be exactly one kind field")
        require(TapLockPreferences.readAction() == .screenshot, "screenshot did not round-trip")

        let malformed: [[String: Any]] = [
            ["kind": "screenshot", "bundleIdentifier": "com.example.app"],
            ["kind": "screenshot", "bundleIdentifier": ""],
            ["kind": "screenshot", "extra": "unexpected"],
            ["kind": "screenshot", "enabled": true],
            ["kind": "screenshot", "action": "lock"],
            ["kind": "Screenshot"], ["kind": "SCREENSHOT"],
            ["kind": "screenshot "], ["kind": ""], ["kind": "unknown"],
            ["kind": 1], ["kind": true], ["kind": ["screenshot"]],
            ["kind": ["kind": "screenshot"]], ["bundleIdentifier": "com.example.app"], [:]
        ]
        for (index, record) in malformed.enumerated() {
            rawAction(record as CFDictionary)
            require(TapLockPreferences.readAction() == .unavailable,
                    "malformed screenshot record \(index) was accepted")
            require(sameValue(storedAction(), record as CFDictionary), "malformed read rewrote the action")
        }
        for value in ["screenshot" as CFString, ["screenshot"] as CFArray, NSNumber(value: true)] as [CFPropertyList] {
            rawAction(value)
            require(TapLockPreferences.readAction() == .unavailable, "non-dictionary action was accepted")
        }
        rawAction(nil)
        require(TapLockPreferences.readAction() == .lock, "missing action no longer defaults to lock")
        require(storedAction() == nil, "default read unexpectedly persisted an action")

        let older: [(TapLockPreferences.Action, [String: String])] = [
            (.lock, ["kind": "lock"]),
            (.openApp("com.example.app"), ["kind": "openApp", "bundleIdentifier": "com.example.app"]),
            (.controlCenter, ["kind": "controlCenter"]),
            (.notificationCenter, ["kind": "notificationCenter"])
        ]
        for (action, record) in older {
            rawAction(record as CFDictionary)
            require(TapLockPreferences.readAction() == action, "older action decoding regressed")
            require(TapLockPreferences.writeAction(.screenshot), "switch from older action failed")
            requireRecord(["kind": "screenshot"], "screenshot retained an older action or app target")
            require(TapLockPreferences.readAction() == .screenshot, "screenshot did not replace older action")
            require(TapLockPreferences.writeAction(action), "older action persistence regressed")
            require(TapLockPreferences.readAction() == action, "older action did not replace screenshot")
            requireRecord(record, "older persisted record changed or retained screenshot")
        }
        require(TapLockPreferences.writeAction(.screenshot), "final screenshot selection failed")
        let beforeInvalidWrite = storedAction()
        require(!TapLockPreferences.writeAction(.unavailable), "unavailable action was persisted")
        require(!TapLockPreferences.writeAction(.openApp("")), "invalid app target was persisted")
        require(sameValue(storedAction(), beforeInvalidWrite), "rejected selection changed screenshot state")
        require(TapLockPreferences.readEnabled() == enabled && sameValue(storedEnabled(), originalEnabled),
                "action selection changed enabled state")
    }

    static func installMalformedMethods() {
        let selector = NSSelectorFromString("takeScreenshot")
        let extraArgument: @convention(c) (AnyObject, Selector, Int32) -> Void = { receiver, _, _ in
            (receiver as? SystemScreenshotApplicationFixture)?.nativeCalls += 1
        }
        let wrongImplicitArgument: @convention(c) (AnyObject, Selector) -> Void = { receiver, _ in
            (receiver as? SystemScreenshotApplicationFixture)?.nativeCalls += 1
        }
        require(class_addMethod(SystemScreenshotWrongArgumentFixture.self, selector,
                unsafeBitCast(extraArgument, to: IMP.self), "v@:i"), "wrong-arity fixture method was not installed")
        require(class_addMethod(SystemScreenshotWrongSelfFixture.self, selector,
                unsafeBitCast(wrongImplicitArgument, to: IMP.self), "v#:"), "wrong-self fixture method was not installed")
        require(class_addMethod(SystemScreenshotWrongCommandFixture.self, selector,
                unsafeBitCast(wrongImplicitArgument, to: IMP.self), "v@@"), "wrong-command fixture method was not installed")
        for (type, encoding) in [(SystemScreenshotWrongArgumentFixture.self, "v@:i"),
                                 (SystemScreenshotWrongSelfFixture.self, "v#:"),
                                 (SystemScreenshotWrongCommandFixture.self, "v@@")] as [(AnyClass, String)] {
            guard let method = class_getInstanceMethod(type, selector),
                  let actual = method_getTypeEncoding(method) else {
                require(false, "malformed fixture selector is missing")
                return
            }
            require(String(cString: actual) == encoding, "malformed fixture encoding was normalized")
            require(PrivateAPI.checkedMethod(in: type, selector: selector, returns: "v", arguments: []) == nil,
                    "actual production ABI checker accepted a malformed C-call shape")
        }
    }

    static func runtime() {
        require(Thread.isMainThread, "runtime harness must start on main")
        require(NSClassFromString("TLSystemScreenshotLockManagerFixture").map { ObjectIdentifier($0) } ==
                ObjectIdentifier(SystemScreenshotLockManagerFixture.self), "lock fixture identity collision")
        require(NSClassFromString("TLSystemScreenshotApplicationFixture").map { ObjectIdentifier($0) } ==
                ObjectIdentifier(SystemScreenshotApplicationFixture.self), "application fixture identity collision")
        installMalformedMethods()
        let lock = SystemScreenshotUnlockedFixture()
        let application = SystemScreenshotWorkingFixture()
        SystemScreenshotLockManagerFixture.current = lock
        SystemScreenshotApplicationFixture.current = application
        require(application.isKind(of: SystemScreenshotApplicationFixture.self), "working application is not fixture SpringBoard")
        require(PrivateAPI.object(SystemScreenshotApplicationFixture.self as AnyObject, "sharedApplication") === application,
                "production object getter did not resolve fixture singleton")
        require(LockAction.unlockedManager() === lock, "production lock admission did not resolve fixture singleton")
        let selector = NSSelectorFromString("takeScreenshot")
        guard let actualType = object_getClass(application),
              let method = class_getInstanceMethod(actualType, selector) else {
            require(false, "working fixture selector is missing")
            return
        }
        require(PrivateAPI.checkedMethod(in: actualType, selector: selector, returns: "v", arguments: []) != nil &&
                method_getNumberOfArguments(method) == 2, "working fixture must expose exact void/no-argument ABI")

        let preferencesBefore = domainSnapshot()
        let gettersBefore = SystemScreenshotApplicationFixture.getterCalls
        require(ScreenshotAction.capture(), "supported native screenshot request was rejected")
        require(application.nativeCalls == 1 && application.requestWasOnMain == [true],
                "capture must synchronously submit exactly one native main-thread request")
        require(SystemScreenshotApplicationFixture.getterCalls == gettersBefore + 1,
                "capture did not acquire the real singleton exactly once")
        require(!lock.locked && !lock.visible && !lock.unlocking,
                "a submitted screenshot request changed lock state")
        require(ScreenshotAction.capture() && application.nativeCalls == 2 && application.requestWasOnMain == [true, true],
                "each explicit capture must submit once without completion or a permanent busy latch")

        let beforeBlockedGetters = SystemScreenshotApplicationFixture.getterCalls
        lock.locked = true
        require(!ScreenshotAction.capture(), "locked device was admitted")
        lock.locked = false
        lock.visible = true
        require(!ScreenshotAction.capture(), "visible lock screen was admitted")
        lock.visible = false
        lock.unlocking = true
        require(!ScreenshotAction.capture(), "unlock transition was admitted")
        lock.unlocking = false
        let wrongState = SystemScreenshotWrongLockStateFixture()
        for receiver in [nil, NSObject(), SystemScreenshotLockManagerFixture(), wrongState] as [NSObject?] {
            SystemScreenshotLockManagerFixture.current = receiver
            require(!ScreenshotAction.capture(), "missing/wrong lock receiver or invalid lock-state ABI was admitted")
        }
        require(wrongState.stateCalls == 0, "wrong lock-state return ABI was invoked")
        require(SystemScreenshotApplicationFixture.getterCalls == beforeBlockedGetters && application.nativeCalls == 2,
                "application was acquired before lock admission or a blocked screenshot was invoked")
        SystemScreenshotLockManagerFixture.current = lock

        let unrelated = SystemScreenshotUnrelatedReceiverFixture()
        for receiver in [nil, NSObject(), unrelated] as [NSObject?] {
            SystemScreenshotApplicationFixture.current = receiver
            require(!ScreenshotAction.capture(), "missing/wrong application receiver was admitted")
        }
        require(unrelated.nativeCalls == 0, "responding to the selector bypassed actual SpringBoard identity")
        let rejected: [SystemScreenshotApplicationFixture] = [
            SystemScreenshotApplicationFixture(), SystemScreenshotWrongReturnFixture(),
            SystemScreenshotWrongArgumentFixture(), SystemScreenshotWrongSelfFixture(),
            SystemScreenshotWrongCommandFixture()
        ]
        for receiver in rejected {
            SystemScreenshotApplicationFixture.current = receiver
            require(!ScreenshotAction.capture(), "missing selector or incompatible return/argument C ABI was admitted")
            require(receiver.nativeCalls == 0 && receiver.fallbackCalls == 0,
                    "rejected method was invoked or screenshot fell back to another action")
        }
        SystemScreenshotApplicationFixture.current = application

        let beforeThreadLockGetters = SystemScreenshotLockManagerFixture.getterCalls
        let beforeThreadAppGetters = SystemScreenshotApplicationFixture.getterCalls
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            require(!Thread.isMainThread, "off-main fixture executed on main")
            require(!ScreenshotAction.capture(), "off-main screenshot request was accepted")
            done.signal()
        }
        require(done.wait(timeout: .now() + 5) == .success, "off-main test timed out")
        require(SystemScreenshotLockManagerFixture.getterCalls == beforeThreadLockGetters &&
                SystemScreenshotApplicationFixture.getterCalls == beforeThreadAppGetters,
                "off-main capture accessed a private singleton")
        // Give an incorrectly queued main-thread request a chance to run. This
        // is a bounded scheduling regression check, not screenshot timing proof.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        require(application.nativeCalls == 2 && application.fallbackCalls == 0 && lock.directLockCalls == 0,
                "rejected capture scheduled a later screenshot or fallback")
        require(SystemScreenshotLockManagerFixture.getterCalls == beforeThreadLockGetters &&
                SystemScreenshotApplicationFixture.getterCalls == beforeThreadAppGetters,
                "rejected capture deferred private singleton acquisition")
        require(rejected.allSatisfy { $0.nativeCalls == 0 && $0.fallbackCalls == 0 },
                "incompatible receiver scheduled a delayed invocation or fallback")
        require(ScreenshotAction.capture() && application.nativeCalls == 3 &&
                application.requestWasOnMain == [true, true, true], "valid screenshot did not recover after rejection cases")
        require(application.fallbackCalls == 0 && lock.directLockCalls == 0,
                "native screenshot request also triggered a lock or alternative action")
        require(!lock.locked && !lock.visible && !lock.unlocking, "capture mutated the fixture lock state")
        require(sameValue(domainSnapshot(), preferencesBefore), "capture changed persisted preference state")
        SystemScreenshotApplicationFixture.current = nil
        SystemScreenshotLockManagerFixture.current = nil
    }
    #endif

    static func main() {
        // Freeze the real existing domain, not an isolated replacement or a fake
        // preferences implementation. Only the action key is written and restored.
        require(TapLockPreferences.domain == "com.tsangbaby.taplock" &&
                TapLockPreferences.actionKey == "DoubleTapAction" && TapLockPreferences.enabledKey == "Enabled",
                "production preference domain or keys changed")
        require(CFPreferencesSynchronize(TapLockPreferences.domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost), "initial preference synchronization failed")
        let original = storedAction()
        let originalEnabled = storedEnabled()
        cleanup = {
            CFPreferencesSetValue(TapLockPreferences.actionKey as CFString, original,
                TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return CFPreferencesSynchronize(TapLockPreferences.domain as CFString,
                kCFPreferencesCurrentUser, kCFPreferencesAnyHost) &&
                sameValue(storedAction(), original) && sameValue(storedEnabled(), originalEnabled)
        }
        defer { _ = cleanup?() }
        rawAction(["kind": "screenshot"] as CFDictionary)
        // The exact same assertion compiles with actual unmodified 0.1.6 enum.
        require(TapLockPreferences.readAction() != .unavailable,
                "persisted screenshot action is unavailable")

        #if SCREENSHOT_BASELINE
        require(cleanup?() == true, "preference restoration failed")
        cleanup = nil
        print("SCREENSHOT_BASELINE_UNEXPECTED_SUCCESS")
        #else
        preferences(originalEnabled)
        runtime()
        require(cleanup?() == true, "preference restoration failed")
        cleanup = nil
        print("SCREENSHOT_RUNTIME_PASS: \(assertions) assertions against production Swift; OS receivers are fixtures, NOT handset screenshot proof")
        #endif
        fflush(stdout)
    }
}
