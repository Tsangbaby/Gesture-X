import Foundation
import ObjectiveC
import Darwin

/// Only the fixed ABI shapes used by TapLock. An unknown encoding fails closed.
/// These checks do not catch Objective-C exceptions thrown inside system code.
enum PrivateAPI {
    static func checkedMethod(in type: AnyClass, selector: Selector,
                              returns: String, arguments: [String] = []) -> Method? {
        guard let method = class_getInstanceMethod(type, selector),
              method_getNumberOfArguments(method) == UInt32(arguments.count + 2),
              matches(method_copyReturnType(method), returns) else {
            return nil
        }
        for (index, expected) in (["@", ":"] + arguments).enumerated() {
            guard matches(method_copyArgumentType(method, UInt32(index)), expected) else {
                return nil
            }
        }
        return method
    }

    static func object(_ receiver: AnyObject, _ name: String) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard let type = object_getClass(receiver),
              let method = checkedMethod(in: type, selector: selector, returns: "@") else {
            return nil
        }
        // Only +0 getters (no alloc/new/copy/init family) are used by callers.
        typealias Getter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let invoke = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return invoke(receiver, selector)?.takeUnretainedValue() as? NSObject
    }

    static func bool(_ receiver: AnyObject, _ name: String) -> Bool? {
        let selector = NSSelectorFromString(name)
        guard let type = object_getClass(receiver),
              let method = checkedMethod(in: type, selector: selector, returns: "B") else {
            return nil
        }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let invoke = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return invoke(receiver, selector)
    }

    private static func matches(_ raw: UnsafeMutablePointer<CChar>?, _ expected: String) -> Bool {
        guard let raw = raw else { return false }
        defer { free(raw) }
        return String(cString: raw) == expected
    }
}
