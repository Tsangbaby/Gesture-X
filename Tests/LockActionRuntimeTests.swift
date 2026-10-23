import Foundation
import ObjectiveC
import Darwin

// Only absent SpringBoard classes are fixtures. Both baseline and candidate
// execute their actual production LockAction.swift and PrivateAPI.swift.
@objc(SBLockScreenManager)
final class LockManagerFixture: NSObject {
    static var current: NSObject?
    var locked = false
    var visible = false
    var unlocking = false
    var directLockCalls = 0

    @objc dynamic class func sharedInstanceIfExists() -> NSObject? { current }
    @objc dynamic func isUILocked() -> Bool { locked }
    @objc dynamic func isLockScreenVisible() -> Bool { visible }
    @objc dynamic func isUIUnlocking() -> Bool { unlocking }
    @objc dynamic func lockUIFromSource(_ source: Int32, withOptions options: NSDictionary?) {
        directLockCalls += 1
    }
}

@objc(SpringBoard)
class SpringBoardFixture: NSObject {
    static var current: NSObject?
    @objc dynamic class func sharedApplication() -> NSObject? { current }
}

final class LockButtonFixture: SpringBoardFixture {
    var presses = 0
    @objc dynamic func _simulateLockButtonPress() { presses += 1 }
}

final class WrongReturnFixture: SpringBoardFixture {
    var calls = 0
    @objc dynamic func _simulateLockButtonPress() -> Bool {
        calls += 1
        return true
    }
}

@main
struct LockActionRuntimeTests {
    static func main() {
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else {
                print("LOCK_BUTTON_FAIL: \(name)")
                fflush(stdout)
                exit(1)
            }
            passed += 1
        }
        let manager = LockManagerFixture()
        let button = LockButtonFixture()
        LockManagerFixture.current = manager
        SpringBoardFixture.current = button
        LockAction.requestLock()
        check(button.presses == 1 && manager.directLockCalls == 0,
              "one system button action instead of direct UI lock")
        LockAction.requestLock()
        check(button.presses == 2 && manager.directLockCalls == 0,
              "exactly one invocation per request without fallback")

        manager.locked = true
        LockAction.requestLock()
        check(button.presses == 2, "already locked must not toggle screen awake")
        manager.locked = false
        manager.visible = true
        LockAction.requestLock()
        check(button.presses == 2, "visible lock screen rejects request")
        manager.visible = false
        manager.unlocking = true
        LockAction.requestLock()
        check(button.presses == 2, "unlocking rejects request")
        manager.unlocking = false

        LockManagerFixture.current = nil
        LockAction.requestLock()
        check(button.presses == 2, "missing lock manager rejects request")
        LockManagerFixture.current = NSObject()
        LockAction.requestLock()
        check(button.presses == 2, "wrong lock-manager class rejects request")
        LockManagerFixture.current = manager

        SpringBoardFixture.current = nil
        LockAction.requestLock()
        check(button.presses == 2, "missing application rejects request")
        SpringBoardFixture.current = NSObject()
        LockAction.requestLock()
        check(button.presses == 2, "wrong application class rejects request")
        SpringBoardFixture.current = SpringBoardFixture()
        LockAction.requestLock()
        check(manager.directLockCalls == 0, "absent button selector has no UI-lock fallback")
        let wrongReturn = WrongReturnFixture()
        SpringBoardFixture.current = wrongReturn
        LockAction.requestLock()
        check(wrongReturn.calls == 0 && manager.directLockCalls == 0,
              "wrong return ABI is rejected without invocation")

        SpringBoardFixture.current = button
        let completed = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            LockAction.requestLock()
            completed.signal()
        }
        check(completed.wait(timeout: .now() + 5) == .success && button.presses == 2,
              "off-main request is rejected without deferred action")
        LockAction.requestLock()
        check(button.presses == 3 && manager.directLockCalls == 0,
              "valid request recovers after all rejection cases")
        print("LOCK_BUTTON_PASS: \(passed) executed production-action checks")
        print("Boundary: macOS Objective-C class fixtures; NOT handset screen-off or animation proof")
        fflush(stdout)
    }
}
