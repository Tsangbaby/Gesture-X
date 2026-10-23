import Foundation
import ObjectiveC

/// Fixed LaunchServices calls shared by the Settings picker and SpringBoard.
/// Capability/ABI checks reject unsupported systems; no URL or launch fallback.
enum InstalledApplications {
    struct Choice: Equatable {
        let identifier: String
        let name: String
    }

    static func choices() -> [Choice] {
        guard Thread.isMainThread,
              let proxyType = NSClassFromString("LSApplicationProxy"),
              let workspace = workspace(),
              let proxies = PrivateAPI.object(workspace, "allApplications") as? [NSObject] else { return [] }
        var seen = Set<String>()
        return proxies.compactMap { proxy -> Choice? in
            guard let result = choice(proxy, type: proxyType),
                  seen.insert(result.identifier).inserted else { return nil }
            return result
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.identifier < $1.identifier : order == .orderedAscending
        }
    }

    static func choice(identifier: String) -> Choice? {
        let selector = NSSelectorFromString("applicationProxyForIdentifier:")
        guard Thread.isMainThread, TapLockPreferences.validBundleIdentifier(identifier),
              let proxyType = NSClassFromString("LSApplicationProxy"),
              let metaclass = object_getClass(proxyType),
              let method = PrivateAPI.checkedMethod(in: metaclass, selector: selector,
                                                    returns: "@", arguments: ["@"]) else { return nil }
        typealias Lookup = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
        let invoke = unsafeBitCast(method_getImplementation(method), to: Lookup.self)
        guard let proxy = invoke(proxyType as AnyObject, selector, identifier as NSString)?.takeUnretainedValue() as? NSObject,
              let result = choice(proxy, type: proxyType), result.identifier == identifier else { return nil }
        return result
    }

    @discardableResult
    static func open(identifier: String) -> Bool {
        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard Thread.isMainThread, choice(identifier: identifier) != nil,
              let workspace = workspace(), let type = object_getClass(workspace),
              let method = PrivateAPI.checkedMethod(in: type, selector: selector,
                                                    returns: "B", arguments: ["@"]) else { return false }
        typealias Open = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let invoke = unsafeBitCast(method_getImplementation(method), to: Open.self)
        return invoke(workspace, selector, identifier as NSString)
    }

    private static func workspace() -> NSObject? {
        guard let type = NSClassFromString("LSApplicationWorkspace"),
              let object = PrivateAPI.object(type as AnyObject, "defaultWorkspace"),
              object.isKind(of: type) else { return nil }
        return object
    }

    private static func choice(_ proxy: NSObject, type: AnyClass) -> Choice? {
        guard proxy.isKind(of: type),
              PrivateAPI.bool(proxy, "isInstalled") == true,
              let recordType = NSClassFromString("LSApplicationRecord"),
              let record = PrivateAPI.object(proxy, "correspondingApplicationRecord"),
              record.isKind(of: recordType),
              PrivateAPI.bool(record, "isLaunchProhibited") == false,
              let category = PrivateAPI.object(proxy, "applicationType") as? String,
              category == "User" || category == "System",
              let identifier = PrivateAPI.object(proxy, "bundleIdentifier") as? String,
              TapLockPreferences.validBundleIdentifier(identifier),
              PrivateAPI.object(record, "bundleIdentifier") as? String == identifier else { return nil }
        let tags = PrivateAPI.object(record, "appTags") as? [String] ?? []
        guard !tags.contains(where: { $0.contains("hidden") }) else { return nil }
        let name = (PrivateAPI.object(proxy, "localizedName") as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Choice(identifier: identifier, name: name ?? identifier)
    }
}
