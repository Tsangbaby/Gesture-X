import Foundation
import CoreFoundation
import ObjectiveC
import Darwin

// Only unavailable OS receivers are fixtures; production ABI guards are intact.
typealias NotificationCompletion = @convention(block) () -> Void

@objc(TLNotificationCenterLockManagerFixture)
class NotificationLockManagerFixture: NSObject {
    static var current: NSObject?
    var locked = false
    var visible = false
    var unlocking = false
    @objc class func sharedInstanceIfExists() -> NSObject? { current }
    @objc func isUILocked() -> Bool { locked }
    @objc func isLockScreenVisible() -> Bool { visible }
    @objc func isUIUnlocking() -> Bool { unlocking }
}

@objc(TLNotificationCenterPresentationManagerFixture)
class NotificationManagerFixture: NSObject {
    static var current: NSObject?
    static var getterCalls = 0
    var calls = 0
    @objc class func sharedInstance() -> NSObject? {
        getterCalls += 1
        return current
    }
}

class NotificationStateFixture: NotificationManagerFixture {
    var presented = false
    var visible = false
    var transitioning = false
    @objc func isPresented() -> Bool { presented }
    @objc func isVisible() -> Bool { visible }
    @objc func isTransitioning() -> Bool { transitioning }
}

class NotificationAdmissionFixture: NotificationStateFixture {
    var allowed = true
    var admissionArguments: [Bool] = []
    @objc(coverSheetCanTransitionToPresented:)
    func canPresent(_ presented: Bool) -> Bool {
        admissionArguments.append(presented)
        return allowed
    }
}

class WorkingNotificationFixture: NotificationAdmissionFixture {
    var requests: [[Bool]] = []
    @objc(setCoverSheetPresented:animated:withCompletion:)
    func present(_ presented: Bool, animated: Bool, completion: NotificationCompletion?) {
        calls += 1
        requests.append([presented, animated, completion == nil])
    }
}

class WrongNotificationPresentedFixture: NotificationAdmissionFixture {
    @objc(setCoverSheetPresented:animated:withCompletion:)
    func present(_ presented: Int32, animated: Bool, completion: NotificationCompletion?) { calls += 1 }
}

class WrongNotificationAnimatedFixture: NotificationAdmissionFixture {
    @objc(setCoverSheetPresented:animated:withCompletion:)
    func present(_ presented: Bool, animated: Int32, completion: NotificationCompletion?) { calls += 1 }
}

class WrongNotificationBlockFixture: NotificationAdmissionFixture {
    @objc(setCoverSheetPresented:animated:withCompletion:)
    func present(_ presented: Bool, animated: Bool, completion: NSObject?) { calls += 1 }
}

class WrongNotificationReturnFixture: NotificationAdmissionFixture {
    @objc(setCoverSheetPresented:animated:withCompletion:)
    func present(_ presented: Bool, animated: Bool, completion: NotificationCompletion?) -> Bool {
        calls += 1
        return true
    }
}

class MissingNotificationAdmissionFixture: NotificationStateFixture {
    @objc(setCoverSheetPresented:animated:withCompletion:)
    func present(_ presented: Bool, animated: Bool, completion: NotificationCompletion?) { calls += 1 }
}

class WrongNotificationAdmissionArgumentFixture: NotificationStateFixture {
    @objc(coverSheetCanTransitionToPresented:)
    func canPresent(_ presented: Int32) -> Bool { calls += 1; return true }
    @objc(setCoverSheetPresented:animated:withCompletion:)
    func present(_ presented: Bool, animated: Bool, completion: NotificationCompletion?) { calls += 1 }
}

class WrongNotificationAdmissionReturnFixture: NotificationStateFixture {
    @objc(coverSheetCanTransitionToPresented:)
    func canPresent(_ presented: Bool) -> Int64 { calls += 1; return 1 }
    @objc(setCoverSheetPresented:animated:withCompletion:)
    func present(_ presented: Bool, animated: Bool, completion: NotificationCompletion?) { calls += 1 }
}

class WrongNotificationStateFixture: NotificationManagerFixture {
    @objc func isPresented() -> Int64 { calls += 1; return 0 }
    @objc func isVisible() -> Bool { false }
    @objc func isTransitioning() -> Bool { false }
    @objc(coverSheetCanTransitionToPresented:)
    func canPresent(_ presented: Bool) -> Bool { calls += 1; return true }
    @objc(setCoverSheetPresented:animated:withCompletion:)
    func present(_ presented: Bool, animated: Bool, completion: NotificationCompletion?) { calls += 1 }
}

@main
struct NotificationCenterRuntimeTests {
    static var assertions = 0
    static var cleanup: (() -> Void)?

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            cleanup?()
            print("NOTIFICATION_CENTER_RUNTIME_FAIL: \(message)")
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
        rawAction(["kind": "notificationCenter"] as CFDictionary)
        // Compiles against unmodified 0.1.5 and fails at real decoding behavior.
        require(TapLockPreferences.readAction() != .unavailable,
                "persisted Notification Center action is unavailable")

        #if NOTIFICATION_CENTER_BASELINE
        print("NOTIFICATION_CENTER_BASELINE_UNEXPECTED_SUCCESS")
        #else
        let enabled = TapLockPreferences.readEnabled()
        require(TapLockPreferences.readAction() == .notificationCenter, "wrong decoded Notification Center action")
        require(TapLockPreferences.writeAction(.notificationCenter), "Notification Center action could not persist")
        require(TapLockPreferences.readAction() == .notificationCenter, "Notification Center did not round-trip")
        require(TapLockPreferences.readEnabled() == enabled, "Notification Center selection changed enable state")
        for malformed in [
            ["kind": "notificationCenter", "bundleIdentifier": "com.example.app"],
            ["kind": "notificationCenter", "extra": "unexpected"],
            ["kind": "NotificationCenter"], ["kind": 1], ["kind": true]
        ] as [[String: Any]] {
            rawAction(malformed as CFDictionary)
            require(TapLockPreferences.readAction() == .unavailable, "malformed Notification Center record accepted")
        }
        rawAction(nil)
        require(TapLockPreferences.readAction() == .lock, "missing action no longer defaults to lock")
        for action in [TapLockPreferences.Action.lock, .openApp("com.example.app"), .controlCenter] {
            require(TapLockPreferences.writeAction(action) && TapLockPreferences.readAction() == action,
                    "existing action persistence regressed")
        }
        require(!TapLockPreferences.writeAction(.unavailable), "unavailable action was persisted")

        require(NSClassFromString("TLNotificationCenterPresentationManagerFixture").map { ObjectIdentifier($0) } ==
                ObjectIdentifier(NotificationManagerFixture.self), "presentation fixture identity collision")
        require(NSClassFromString("TLNotificationCenterLockManagerFixture").map { ObjectIdentifier($0) } ==
                ObjectIdentifier(NotificationLockManagerFixture.self), "lock fixture identity collision")
        let lock = NotificationLockManagerFixture()
        NotificationLockManagerFixture.current = lock
        let manager = WorkingNotificationFixture()
        NotificationManagerFixture.current = manager
        require(NotificationCenterAction.open(), "supported native request was rejected")
        require(manager.calls == 1 && manager.requests == [[true, true, true]],
                "native presenter must receive presented=true animated=true completion=nil exactly once")
        require(manager.admissionArguments == [true], "native admission must receive presented=true")
        manager.presented = true
        require(!NotificationCenterAction.open() && manager.calls == 1, "presented Cover Sheet was toggled/reinvoked")
        manager.presented = false
        manager.visible = true
        require(!NotificationCenterAction.open() && manager.calls == 1, "visible Cover Sheet was reinvoked")
        manager.visible = false
        manager.transitioning = true
        require(!NotificationCenterAction.open() && manager.calls == 1, "active Cover Sheet transition was reinvoked")
        manager.transitioning = false
        require(manager.admissionArguments == [true], "blocked states reached native admission")
        manager.allowed = false
        require(!NotificationCenterAction.open() && manager.calls == 1, "system admission refusal was ignored")
        require(manager.admissionArguments == [true, true], "admission arguments changed during refusal")
        manager.allowed = true
        require(NotificationCenterAction.open() && manager.calls == 2,
                "opening again after native dismissal was rejected")
        require(manager.requests == [[true, true, true], [true, true, true]], "reopen became a close request")

        for receiver in [nil, NSObject()] as [NSObject?] {
            NotificationManagerFixture.current = receiver
            require(!NotificationCenterAction.open(), "missing/wrong presentation manager identity accepted")
        }
        for rejected in [NotificationManagerFixture(), NotificationStateFixture(), NotificationAdmissionFixture(),
                         WrongNotificationPresentedFixture(), WrongNotificationAnimatedFixture(),
                         WrongNotificationBlockFixture(), WrongNotificationReturnFixture(),
                         MissingNotificationAdmissionFixture(), WrongNotificationAdmissionArgumentFixture(),
                         WrongNotificationAdmissionReturnFixture(), WrongNotificationStateFixture()] as [NotificationManagerFixture] {
            NotificationManagerFixture.current = rejected
            require(!NotificationCenterAction.open(), "missing method or incompatible BOOL/Block ABI accepted")
            require(rejected.calls == 0, "incompatible private method was invoked")
        }
        NotificationManagerFixture.current = manager
        let beforeLockChecks = NotificationManagerFixture.getterCalls
        lock.locked = true
        require(!NotificationCenterAction.open(), "locked device was admitted")
        lock.locked = false
        lock.visible = true
        require(!NotificationCenterAction.open(), "visible lock screen was admitted")
        lock.visible = false
        lock.unlocking = true
        require(!NotificationCenterAction.open(), "unlock transition was admitted")
        lock.unlocking = false
        for receiver in [nil, NSObject()] as [NSObject?] {
            NotificationLockManagerFixture.current = receiver
            require(!NotificationCenterAction.open(), "missing/wrong lock manager identity accepted")
        }
        require(NotificationManagerFixture.getterCalls == beforeLockChecks,
                "presentation manager was acquired before lock admission")
        NotificationLockManagerFixture.current = lock
        let beforeThreadCheck = NotificationManagerFixture.getterCalls
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            require(!NotificationCenterAction.open(), "off-main request accepted")
            done.signal()
        }
        require(done.wait(timeout: .now() + 5) == .success, "off-main test timed out")
        require(NotificationManagerFixture.getterCalls == beforeThreadCheck && manager.calls == 2,
                "rejected requests reached the native presenter")
        print("NOTIFICATION_CENTER_RUNTIME_PASS: \(assertions) assertions against production Swift; OS receivers are fixtures, NOT handset presentation proof")
        #endif
        fflush(stdout)
    }
}
