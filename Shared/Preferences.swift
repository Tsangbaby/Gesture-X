import Foundation
import CoreFoundation

/// One preferences domain/key shared by Settings and SpringBoard.
/// No absolute jailbreak paths and no reads on the touch-event hot path.
enum TapLockPreferences {
    static let domain = "com.tsangbaby.taplock"
    static let enabledKey = "Enabled"
    static let defaultEnabled = false
    static let changedNotification = "com.tsangbaby.taplock.preferences-changed"

    static func readEnabled() -> Bool {
        guard synchronize(),
              let value = CFPreferencesCopyValue(
                enabledKey as CFString, domain as CFString,
                kCFPreferencesCurrentUser, kCFPreferencesAnyHost
              ), CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return defaultEnabled
        }
        return (value as? NSNumber)?.boolValue ?? defaultEnabled
    }

    /// Publish only after persistence succeeds. Restore the previous cached
    /// value on failure, and let the settings controller report the failure.
    @discardableResult
    static func writeEnabled(_ enabled: Bool) -> Bool {
        _ = synchronize()
        let previous = CFPreferencesCopyValue(
            enabledKey as CFString, domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
        CFPreferencesSetValue(
            enabledKey as CFString, enabled ? kCFBooleanTrue : kCFBooleanFalse,
            domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
        guard synchronize() else {
            CFPreferencesSetValue(enabledKey as CFString, previous,
                                  domain as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            _ = synchronize()
            return false
        }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: changedNotification as CFString),
            nil, nil, true
        )
        return true
    }

    // One property-list value keeps the action and its target atomic. Missing
    // configuration preserves the accepted lock action; malformed data does not.
    enum Action: Equatable {
        case lock
        case openApp(String)
        case controlCenter
        case notificationCenter
        case screenshot
        case unavailable
    }
    static let actionKey = "DoubleTapAction"

    static func validBundleIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.utf8.count <= 255 &&
            !identifier.hasPrefix(".") && !identifier.hasSuffix(".") &&
            !identifier.contains("..") && identifier.rangeOfCharacter(from:
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.").inverted) == nil
    }

    static func readAction() -> Action {
        guard synchronize() else { return .unavailable }
        guard let value = CFPreferencesCopyValue(
            actionKey as CFString, domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        ) else { return .lock }
        guard CFGetTypeID(value) == CFDictionaryGetTypeID(),
              let record = value as? [String: Any],
              let kind = record["kind"] as? String else { return .unavailable }
        if kind == "lock", record.count == 1 { return .lock }
        if kind == "controlCenter", record.count == 1 { return .controlCenter }
        if kind == "notificationCenter", record.count == 1 { return .notificationCenter }
        if kind == "screenshot", record.count == 1 { return .screenshot }
        if kind == "openApp", record.count == 2,
           let identifier = record["bundleIdentifier"] as? String,
           validBundleIdentifier(identifier) { return .openApp(identifier) }
        return .unavailable
    }

    @discardableResult
    static func writeAction(_ action: Action) -> Bool {
        let record: [String: String]
        switch action {
        case .lock:
            record = ["kind": "lock"]
        case .controlCenter:
            record = ["kind": "controlCenter"]
        case .notificationCenter:
            record = ["kind": "notificationCenter"]
        case .screenshot:
            record = ["kind": "screenshot"]
        case .openApp(let identifier):
            guard validBundleIdentifier(identifier) else { return false }
            record = ["kind": "openApp", "bundleIdentifier": identifier]
        case .unavailable:
            return false
        }
        _ = synchronize()
        let previous = CFPreferencesCopyValue(
            actionKey as CFString, domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
        CFPreferencesSetValue(actionKey as CFString, record as CFDictionary,
                              domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard synchronize() else {
            CFPreferencesSetValue(actionKey as CFString, previous,
                                  domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            _ = synchronize()
            return false
        }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: changedNotification as CFString), nil, nil, true
        )
        return true
    }

    private static func synchronize() -> Bool {
        CFPreferencesSynchronize(domain as CFString,
                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
