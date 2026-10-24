import Foundation
import ObjectiveC

/// Open the native unlocked Cover Sheet once; presentation and dismissal remain
/// system-owned. Returning true means a request, not visible Notification Center.
enum NotificationCenterAction {
    @discardableResult
    static func open() -> Bool {
        let selector = NSSelectorFromString("setCoverSheetPresented:animated:withCompletion:")
        let admissionSelector = NSSelectorFromString("coverSheetCanTransitionToPresented:")
        guard Thread.isMainThread, LockAction.unlockedManager() != nil,
              let managerType = NSClassFromString("SBCoverSheetPresentationManager"),
              let manager = PrivateAPI.object(managerType as AnyObject, "sharedInstance"),
              manager.isKind(of: managerType),
              PrivateAPI.bool(manager, "isPresented") == false,
              PrivateAPI.bool(manager, "isVisible") == false,
              PrivateAPI.bool(manager, "isTransitioning") == false,
              let runtimeType = object_getClass(manager),
              let admission = PrivateAPI.checkedMethod(in: runtimeType, selector: admissionSelector,
                                                       returns: "B", arguments: ["B"]),
              let method = PrivateAPI.checkedMethod(in: runtimeType, selector: selector,
                                                    returns: "v", arguments: ["B", "B", "@?"]) else { return false }
        typealias CanPresent = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let canPresent = unsafeBitCast(method_getImplementation(admission), to: CanPresent.self)
        guard canPresent(manager, admissionSelector, true) else { return false }
        typealias Completion = @convention(block) () -> Void
        typealias Present = @convention(c) (AnyObject, Selector, Bool, Bool, Completion?) -> Void
        let invoke = unsafeBitCast(method_getImplementation(method), to: Present.self)
        invoke(manager, selector, true, true, nil)
        return true
    }
}
