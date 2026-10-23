import Foundation
import ObjectiveC

/// Request native presentation once. System state and transitions remain owned
/// by SpringBoard; this is not a toggle, retry or confirmation of visible UI.
enum ControlCenterAction {
    @discardableResult
    static func open() -> Bool {
        let selector = NSSelectorFromString("presentAnimated:")
        guard Thread.isMainThread, LockAction.unlockedManager() != nil,
              let controllerType = NSClassFromString("SBControlCenterController"),
              let controller = PrivateAPI.object(controllerType as AnyObject, "sharedInstance"),
              controller.isKind(of: controllerType),
              PrivateAPI.bool(controller, "isPresentedOrDismissing") == false,
              PrivateAPI.bool(controller, "canBePresented") == true,
              let runtimeType = object_getClass(controller),
              let method = PrivateAPI.checkedMethod(in: runtimeType, selector: selector,
                                                    returns: "v", arguments: ["B"]) else { return false }
        typealias Present = @convention(c) (AnyObject, Selector, Bool) -> Void
        let invoke = unsafeBitCast(method_getImplementation(method), to: Present.self)
        invoke(controller, selector, true)
        return true
    }
}
