import Foundation
import ObjectiveC

/// Matches the original action33 state/brightness route. Adjacent iOS 15.5
/// declarations support UInt64, but only exact runtime signatures permit use.
/// True means one void effect call was attempted, not native acceptance or light.
enum FlashlightAction {
    private static let levelSelector = NSSelectorFromString("level")
    private static let loadLevelSelector = NSSelectorFromString("_loadFlashlightLevel")
    private static let turnOffSelector = NSSelectorFromString("_turnPowerOff")
    private static let setLevelSelector = NSSelectorFromString("setLevel:")

    @discardableResult
    static func toggle() -> Bool {
        guard Thread.isMainThread,
              LockAction.unlockedManager() != nil,
              let controllerType = NSClassFromString("SBUIFlashlightController"),
              let controller = PrivateAPI.object(controllerType as AnyObject, "sharedInstance"),
              controller.isKind(of: controllerType),
              let type = object_getClass(controller),
              let levelMethod = PrivateAPI.checkedMethod(in: type, selector: levelSelector,
                                                         returns: "Q"),
              let loadLevelMethod = PrivateAPI.checkedMethod(in: type, selector: loadLevelSelector,
                                                             returns: "Q"),
              let turnOffMethod = PrivateAPI.checkedMethod(in: type, selector: turnOffSelector,
                                                           returns: "v"),
              let setLevelMethod = PrivateAPI.checkedMethod(in: type, selector: setLevelSelector,
                                                            returns: "v", arguments: ["Q"]) else {
            return false
        }
        typealias LevelCall = @convention(c) (AnyObject, Selector) -> UInt64
        typealias OffCall = @convention(c) (AnyObject, Selector) -> Void
        typealias SetCall = @convention(c) (AnyObject, Selector, UInt64) -> Void
        let readLevel = unsafeBitCast(method_getImplementation(levelMethod), to: LevelCall.self)
        if readLevel(controller, levelSelector) != 0 {
            let turnOff = unsafeBitCast(method_getImplementation(turnOffMethod), to: OffCall.self)
            turnOff(controller, turnOffSelector)
        } else {
            let loadLevel = unsafeBitCast(method_getImplementation(loadLevelMethod), to: LevelCall.self)
            let setLevel = unsafeBitCast(method_getImplementation(setLevelMethod), to: SetCall.self)
            setLevel(controller, setLevelSelector, loadLevel(controller, loadLevelSelector))
        }
        return true
    }
}
