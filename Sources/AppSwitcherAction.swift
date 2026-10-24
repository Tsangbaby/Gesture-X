import Foundation
import ObjectiveC

/// Submits one native open-only request. A true result means the receiver
/// accepted the request, not that its transition or visual presentation finished.
enum AppSwitcherAction {
    private static let selector = NSSelectorFromString("activateMainSwitcherNoninteractivelyWithSource:animated:")

    @discardableResult
    static func open() -> Bool {
        guard Thread.isMainThread,
              LockAction.unlockedManager() != nil,
              let controllerType = NSClassFromString("SBMainSwitcherViewController"),
              let controller = PrivateAPI.object(controllerType as AnyObject, "sharedInstanceIfExists"),
              controller.isKind(of: controllerType),
              PrivateAPI.bool(controller, "isAnySwitcherVisible") == false,
              PrivateAPI.bool(controller, "isMainSwitcherVisible") == false,
              let type = object_getClass(controller),
              let method = PrivateAPI.checkedMethod(in: type, selector: selector,
                                                    returns: "B", arguments: ["q", "B"]) else {
            return false
        }
        typealias OpenCall = @convention(c) (AnyObject, Selector, Int64, Bool) -> Bool
        let invoke = unsafeBitCast(method_getImplementation(method), to: OpenCall.self)
        return invoke(controller, selector, 0, true)
    }
}
