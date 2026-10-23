import Foundation
import ObjectiveC
import Darwin

/// SpringBoard-only native launch. Settings owns the LaunchServices catalog;
/// the gesture never queries that service or waits for a launch completion.
enum AppAction {
    @discardableResult
    static func open(identifier: String) -> Bool {
        let selector = NSSelectorFromString("launchApplicationWithIdentifier:suspended:")
        guard Thread.isMainThread, TapLockPreferences.validBundleIdentifier(identifier),
              let springBoardType = NSClassFromString("SpringBoard"),
              let application = PrivateAPI.object(springBoardType as AnyObject, "sharedApplication"),
              application.isKind(of: springBoardType),
              let runtimeType = object_getClass(application),
              ownsLaunchMethod(runtimeType, through: springBoardType, selector: selector),
              let method = PrivateAPI.checkedMethod(in: runtimeType, selector: selector,
                                                    returns: "B", arguments: ["@", "B"]) else { return false }
        typealias Launch = @convention(c) (AnyObject, Selector, NSString, Bool) -> Bool
        let invoke = unsafeBitCast(method_getImplementation(method), to: Launch.self)
        // Native SpringBoard owns target admission and presentation. A rejected
        // request never retries, invokes the other action, or uses a client RPC.
        return invoke(application, selector, identifier as NSString, false)
    }

    private static func ownsLaunchMethod(_ runtimeType: AnyClass, through springBoardType: AnyClass,
                                         selector: Selector) -> Bool {
        var current: AnyClass? = runtimeType
        while let type = current {
            var count: UInt32 = 0
            if let methods = class_copyMethodList(type, &count) {
                defer { free(methods) }
                for index in 0..<Int(count) where method_getName(methods[index]) == selector {
                    return true
                }
            }
            // Do not inherit UIApplication's client-side launcher. The method
            // must be implemented by SpringBoard or one of its actual subclasses.
            if ObjectIdentifier(type) == ObjectIdentifier(springBoardType) { return false }
            current = class_getSuperclass(type)
        }
        return false
    }
}
