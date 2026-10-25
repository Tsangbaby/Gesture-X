import Foundation
import ObjectiveC

/// Ports the original action50 Boolean toggle and Int32 HUD argument. Owner
/// getters are capability-selected from iOS 15/16 declarations, not the original
/// init-hook cache. True means void calls attempted, not native acceptance,
/// changed ringer state, or visible HUD. Exact patch-version support is unproven.
enum SystemMuteAction {
    private static let ringerSelector = NSSelectorFromString("ringerControl")
    private static let mutedSelector = NSSelectorFromString("isRingerMuted")
    private static let setMutedSelector = NSSelectorFromString("setRingerMuted:")
    private static let hudSelector = NSSelectorFromString("activateRingerHUDFromMuteSwitch:")

    @discardableResult
    static func toggle() -> Bool {
        guard Thread.isMainThread,
              LockAction.unlockedManager() != nil,
              let applicationType = NSClassFromString("SpringBoard"),
              let application = PrivateAPI.object(applicationType as AnyObject, "sharedApplication"),
              application.isKind(of: applicationType),
              let applicationClass = object_getClass(application) else { return false }

        let controller: NSObject
        if class_getInstanceMethod(applicationClass, ringerSelector) != nil {
            // Presence chooses this route even when its signature or result is bad.
            guard let direct = PrivateAPI.object(application, "ringerControl") else { return false }
            controller = direct
        } else {
            guard let workspaceType = NSClassFromString("SBMainWorkspace"),
                  let workspace = PrivateAPI.object(workspaceType as AnyObject, "sharedInstanceIfExists"),
                  workspace.isKind(of: workspaceType),
                  let indirect = PrivateAPI.object(workspace, "ringerControl") else { return false }
            controller = indirect
        }
        guard let controllerType = NSClassFromString("SBRingerControl"),
              controller.isKind(of: controllerType),
              let type = object_getClass(controller),
              let mutedMethod = PrivateAPI.checkedMethod(in: type, selector: mutedSelector,
                                                         returns: "B"),
              let setMutedMethod = PrivateAPI.checkedMethod(in: type, selector: setMutedSelector,
                                                            returns: "v", arguments: ["B"]),
              let hudMethod = PrivateAPI.checkedMethod(in: type, selector: hudSelector,
                                                       returns: "v", arguments: ["i"]) else { return false }
        typealias ReadCall = @convention(c) (AnyObject, Selector) -> Bool
        typealias SetCall = @convention(c) (AnyObject, Selector, Bool) -> Void
        typealias HUDCall = @convention(c) (AnyObject, Selector, Int32) -> Void
        let readMuted = unsafeBitCast(method_getImplementation(mutedMethod), to: ReadCall.self)
        let setMuted = unsafeBitCast(method_getImplementation(setMutedMethod), to: SetCall.self)
        let showHUD = unsafeBitCast(method_getImplementation(hudMethod), to: HUDCall.self)
        let old = readMuted(controller, mutedSelector)
        setMuted(controller, setMutedSelector, !old)
        showHUD(controller, hudSelector, Int32(old ? 1 : 0))
        return true
    }
}
