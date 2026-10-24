import Foundation
import ObjectiveC

/// Submits one native system screenshot request. Album persistence and the
/// system thumbnail/animation remain separate handset-acceptance requirements.
enum ScreenshotAction {
    private static let selector = NSSelectorFromString("takeScreenshot")

    @discardableResult
    static func capture() -> Bool {
        guard Thread.isMainThread,
              LockAction.unlockedManager() != nil,
              let applicationType = NSClassFromString("SpringBoard"),
              let application = PrivateAPI.object(applicationType as AnyObject, "sharedApplication"),
              application.isKind(of: applicationType),
              let type = object_getClass(application),
              let method = PrivateAPI.checkedMethod(in: type, selector: selector,
                                                    returns: "v") else {
            return false
        }
        typealias ScreenshotCall = @convention(c) (AnyObject, Selector) -> Void
        let invoke = unsafeBitCast(method_getImplementation(method), to: ScreenshotCall.self)
        invoke(application, selector)
        return true
    }
}
