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

    private static func synchronize() -> Bool {
        CFPreferencesSynchronize(domain as CFString,
                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
