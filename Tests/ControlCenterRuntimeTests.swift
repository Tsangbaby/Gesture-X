import Foundation
import CoreFoundation
import ObjectiveC
import Darwin

// Unique receiver identities; only runtime class lookup constants are rebound.
@objc(TLControlCenterLockManagerFixture)
class ControlCenterLockManagerFixture: NSObject {
    static var current: NSObject?
    var locked = false
    var visible = false
    var unlocking = false
    @objc class func sharedInstanceIfExists() -> NSObject? { current }
    @objc func isUILocked() -> Bool { locked }
    @objc func isLockScreenVisible() -> Bool { visible }
    @objc func isUIUnlocking() -> Bool { unlocking }
}

@objc(TLControlCenterControllerFixture)
class ControlCenterControllerFixture: NSObject {
    static var current: NSObject?
    static var getterCalls = 0
    var calls = 0
    var animations: [Bool] = []
    @objc class func sharedInstance() -> NSObject? {
        getterCalls += 1
        return current
    }
}

class ControlCenterStateFixture: ControlCenterControllerFixture {
    var presentedOrDismissing = false
    var allowed = true
    @objc func isPresentedOrDismissing() -> Bool { presentedOrDismissing }
    @objc func canBePresented() -> Bool { allowed }
}

class WorkingControlCenterFixture: ControlCenterStateFixture {
    @objc func presentAnimated(_ animated: Bool) { calls += 1; animations.append(animated) }
}

class WrongControlCenterArgumentFixture: ControlCenterStateFixture {
    @objc func presentAnimated(_ animated: Int32) { calls += 1 }
}

class WrongControlCenterReturnFixture: ControlCenterStateFixture {
    @objc func presentAnimated(_ animated: Bool) -> Bool { calls += 1; return true }
}

class WrongControlCenterAdmissionFixture: ControlCenterControllerFixture {
    @objc func isPresentedOrDismissing() -> Bool { false }
    @objc func canBePresented() -> Int64 { calls += 1; return 1 }
    @objc func presentAnimated(_ animated: Bool) { calls += 1 }
}

class WrongControlCenterStateFixture: ControlCenterControllerFixture {
    @objc func isPresentedOrDismissing() -> Int64 { calls += 1; return 0 }
    @objc func canBePresented() -> Bool { true }
    @objc func presentAnimated(_ animated: Bool) { calls += 1 }
}

@main
struct ControlCenterRuntimeTests {
    static var assertions = 0
    static var cleanup: (() -> Void)?

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            cleanup?()
            print("CONTROL_CENTER_RUNTIME_FAIL: \(message)")
            fflush(stdout)
            exit(1)
        }
        assertions += 1
    }

    static func rawAction(_ value: CFPropertyList?) {
        CFPreferencesSetValue(TapLockPreferences.actionKey as CFString, value,
            TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        require(CFPreferencesSynchronize(TapLockPreferences.domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost), "fixture preference write failed")
    }

    static func main() {
        let original = CFPreferencesCopyValue(TapLockPreferences.actionKey as CFString,
            TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        cleanup = {
            CFPreferencesSetValue(TapLockPreferences.actionKey as CFString, original,
                TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            _ = CFPreferencesSynchronize(TapLockPreferences.domain as CFString,
                kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        defer { cleanup?() }
        rawAction(["kind": "controlCenter"] as CFDictionary)
        // This assertion also compiles against the unmodified accepted version.
        require(TapLockPreferences.readAction() != .unavailable,
                "persisted Control Center action is unavailable")

        #if CONTROL_CENTER_BASELINE
        print("CONTROL_CENTER_BASELINE_UNEXPECTED_SUCCESS")
        #else
        let enabled = TapLockPreferences.readEnabled()
        require(TapLockPreferences.readAction() == .controlCenter, "wrong decoded Control Center action")
        require(TapLockPreferences.writeAction(.controlCenter), "Control Center action could not persist")
        require(TapLockPreferences.readAction() == .controlCenter, "Control Center did not round-trip")
        require(TapLockPreferences.readEnabled() == enabled, "Control Center selection changed enable state")
        for malformed in [
            ["kind": "controlCenter", "bundleIdentifier": "com.example.app"],
            ["kind": "controlCenter", "extra": "unexpected"],
            ["kind": "ControlCenter"]
        ] {
            rawAction(malformed as CFDictionary)
            require(TapLockPreferences.readAction() == .unavailable, "malformed Control Center record accepted")
        }
        rawAction(nil)
        require(TapLockPreferences.readAction() == .lock, "missing action no longer defaults to lock")
        require(TapLockPreferences.writeAction(.openApp("com.example.app")) &&
                TapLockPreferences.readAction() == .openApp("com.example.app"), "existing App choice regressed")
        require(TapLockPreferences.writeAction(.lock) && TapLockPreferences.readAction() == .lock,
                "existing lock choice regressed")

        require(NSClassFromString("TLControlCenterControllerFixture").map { ObjectIdentifier($0) } ==
                ObjectIdentifier(ControlCenterControllerFixture.self), "controller fixture identity collision")
        require(NSClassFromString("TLControlCenterLockManagerFixture").map { ObjectIdentifier($0) } ==
                ObjectIdentifier(ControlCenterLockManagerFixture.self), "lock fixture identity collision")
        let manager = ControlCenterLockManagerFixture()
        ControlCenterLockManagerFixture.current = manager
        let controller = WorkingControlCenterFixture()
        ControlCenterControllerFixture.current = controller
        require(ControlCenterAction.open(), "supported native request was rejected")
        require(controller.calls == 1 && controller.animations == [true],
                "native presentation must be invoked exactly once with animated=true")
        controller.presentedOrDismissing = true
        require(!ControlCenterAction.open(), "presented/dismissing Control Center was invoked again")
        require(controller.calls == 1, "opening Control Center acted as a toggle")
        controller.presentedOrDismissing = false
        controller.allowed = false
        require(!ControlCenterAction.open() && controller.calls == 1, "system admission refusal was ignored")
        controller.allowed = true

        for receiver in [nil, NSObject()] as [NSObject?] {
            ControlCenterControllerFixture.current = receiver
            require(!ControlCenterAction.open(), "missing/wrong Control Center identity accepted")
        }
        for rejected in [ControlCenterStateFixture(), WrongControlCenterArgumentFixture(),
                         WrongControlCenterReturnFixture(), WrongControlCenterAdmissionFixture(),
                         WrongControlCenterStateFixture()] as [ControlCenterControllerFixture] {
            ControlCenterControllerFixture.current = rejected
            require(!ControlCenterAction.open(), "missing selector or wrong ABI accepted")
            require(rejected.calls == 0, "incompatible ABI was invoked")
        }
        ControlCenterControllerFixture.current = controller
        let beforeLockChecks = ControlCenterControllerFixture.getterCalls
        manager.locked = true
        require(!ControlCenterAction.open(), "locked device was admitted")
        manager.locked = false
        manager.visible = true
        require(!ControlCenterAction.open(), "visible lock screen was admitted")
        manager.visible = false
        manager.unlocking = true
        require(!ControlCenterAction.open(), "unlock transition was admitted")
        manager.unlocking = false
        for lockReceiver in [nil, NSObject()] as [NSObject?] {
            ControlCenterLockManagerFixture.current = lockReceiver
            require(!ControlCenterAction.open(), "missing/wrong lock manager identity accepted")
        }
        require(ControlCenterControllerFixture.getterCalls == beforeLockChecks,
                "Control Center singleton was acquired before lock admission")
        ControlCenterLockManagerFixture.current = manager
        let beforeThreadCheck = ControlCenterControllerFixture.getterCalls
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            require(!ControlCenterAction.open(), "off-main request accepted")
            done.signal()
        }
        require(done.wait(timeout: .now() + 5) == .success, "off-main test timed out")
        require(ControlCenterControllerFixture.getterCalls == beforeThreadCheck && controller.calls == 1,
                "rejected requests reached the native presenter")
        print("CONTROL_CENTER_RUNTIME_PASS: \(assertions) assertions against production Swift; OS receivers are fixtures, NOT handset presentation proof")
        #endif
        fflush(stdout)
    }
}
