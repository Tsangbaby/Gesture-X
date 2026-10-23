import Foundation
import ObjectiveC

/// Issues a system lock request; it does not claim that the device is locked.
/// Actual lock/display state is a separate device-acceptance requirement.
enum LockAction {
    private static let selector = NSSelectorFromString("lockUIFromSource:withOptions:")

    static func unlockedManager() -> NSObject? {
        guard Thread.isMainThread,
              let type = NSClassFromString("SBLockScreenManager"),
              let manager = PrivateAPI.object(type as AnyObject, "sharedInstanceIfExists"),
              manager.isKind(of: type),
              let runtimeType = object_getClass(manager),
              PrivateAPI.checkedMethod(in: runtimeType, selector: selector,
                                       returns: "v", arguments: ["i", "@"]) != nil,
              PrivateAPI.bool(manager, "isUILocked") == false,
              PrivateAPI.bool(manager, "isLockScreenVisible") == false,
              PrivateAPI.bool(manager, "isUIUnlocking") == false else {
            return nil
        }
        return manager
    }

    static func requestLock() {
        guard Thread.isMainThread,
              let manager = unlockedManager(),
              let type = object_getClass(manager),
              let method = PrivateAPI.checkedMethod(in: type, selector: selector,
                                                    returns: "v", arguments: ["i", "@"]) else {
            return
        }
        // Int32 is intentional: the accepted private ABI is v@:i@, not NSUInteger.
        // Source 1 is a lock request; no hardware-button simulation or fallback.
        typealias LockCall = @convention(c) (AnyObject, Selector, Int32, NSDictionary?) -> Void
        let invoke = unsafeBitCast(method_getImplementation(method), to: LockCall.self)
        invoke(manager, selector, 1, nil)
    }
}
