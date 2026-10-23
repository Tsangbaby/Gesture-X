import Foundation
import ObjectiveC

/// Issues a system lock request; it does not claim that the device is locked.
/// Actual lock/display state is a separate device-acceptance requirement.
enum LockAction {
    private static let selector = NSSelectorFromString("_simulateLockButtonPress")

    static func unlockedManager() -> NSObject? {
        guard Thread.isMainThread,
              let type = NSClassFromString("SBLockScreenManager"),
              let manager = PrivateAPI.object(type as AnyObject, "sharedInstanceIfExists"),
              manager.isKind(of: type),
              PrivateAPI.bool(manager, "isUILocked") == false,
              PrivateAPI.bool(manager, "isLockScreenVisible") == false,
              PrivateAPI.bool(manager, "isUIUnlocking") == false else {
            return nil
        }
        return manager
    }

    static func requestLock() {
        guard Thread.isMainThread,
              unlockedManager() != nil,
              let applicationType = NSClassFromString("SpringBoard"),
              let application = PrivateAPI.object(applicationType as AnyObject, "sharedApplication"),
              application.isKind(of: applicationType),
              let type = object_getClass(application),
              let method = PrivateAPI.checkedMethod(in: type, selector: selector,
                                                    returns: "v") else {
            return
        }
        // Let the system own the short-press transition; do not also lock the UI.
        typealias LockCall = @convention(c) (AnyObject, Selector) -> Void
        let invoke = unsafeBitCast(method_getImplementation(method), to: LockCall.self)
        invoke(application, selector)
    }
}
