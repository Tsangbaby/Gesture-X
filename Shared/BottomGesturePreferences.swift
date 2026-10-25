import Foundation
import CoreFoundation

/// Independent bottom keys in the maintained domain. Read once on activation or
/// preferences notification; consumers retain the immutable Snapshot for touches.
enum BottomGesturePreferences {
    enum GestureID: String, CaseIterable {
        case bottomLeftUp
        case bottomLeftUpExtra
        case bottomLeftUpExtraPlus
        case bottomRightUp
        case bottomRightUpExtra
        case bottomRightUpExtraPlus

        var enabledKey: String { rawValue + "Enabled" }
        var flowKey: String { rawValue + "FlowEnabled" }
    }

    enum BooleanKey: String, CaseIterable {
        case ignoreEdgeProtect
        case disableBottomWhenLocked
        case bottomUpOnLandscapeEnabled

        var defaultValue: Bool {
            switch self {
            case .ignoreEdgeProtect: return true
            case .disableBottomWhenLocked: return true
            case .bottomUpOnLandscapeEnabled: return false
            }
        }
    }

    enum NumericKey: String, CaseIterable {
        case bottomTriggerPosition
        case bottomTriggerRightPosition
        case bottomTriggerSensitivity
        case bottomTriggerArea
        case bottomTriggerExtraArea
        case bottomTriggerExtraPlusArea
        case bottomTriggerPositionLandscape
        case bottomTriggerRightPositionLandscape
        case bottomTriggerSensitivityLandscape
        case bottomTriggerAreaLandscape
        case bottomTriggerExtraAreaLandscape
        case bottomTriggerExtraPlusAreaLandscape

        private var metadata: (Double, Double, Double, String) {
            switch self {
            case .bottomTriggerPosition: return (0, 50, 30, "左边触发宽度")
            case .bottomTriggerRightPosition: return (0, 50, 30, "右边触发宽度")
            case .bottomTriggerSensitivity: return (0, 10, 7, "最小触发高度")
            case .bottomTriggerArea: return (0, 100, 18, "+手势最小触发高度")
            case .bottomTriggerExtraArea: return (0, 100, 40, "++手势最小触发高度")
            case .bottomTriggerExtraPlusArea: return (0, 100, 60, "最高触发高度")
            case .bottomTriggerPositionLandscape: return (0, 50, 20, "左边触发宽度(横屏)")
            case .bottomTriggerRightPositionLandscape: return (0, 50, 20, "右边触发宽度(横屏)")
            case .bottomTriggerSensitivityLandscape: return (0, 10, 7, "最小触发高度(横屏)")
            case .bottomTriggerAreaLandscape: return (0, 100, 40, "+手势最小触发高度(横屏)")
            case .bottomTriggerExtraAreaLandscape: return (0, 100, 70, "++手势最小触发高度(横屏)")
            case .bottomTriggerExtraPlusAreaLandscape: return (0, 100, 100, "最高触发高度(横屏)")
            }
        }
        var minValue: Double { metadata.0 }
        var maxValue: Double { metadata.1 }
        var defaultValue: Double { metadata.2 }
        var title: String { metadata.3 }
    }

    struct Selection: Equatable {
        let enabled: Bool
        let flowEnabled: Bool
        let actions: [TapLockPreferences.Action]

        static let disabled = Selection(enabled: false, flowEnabled: false, actions: [])
    }

    struct Snapshot {
        let available: Bool
        let numbers: [NumericKey: Double]
        let booleans: [BooleanKey: Bool]
        let selections: [GestureID: Selection]

        func number(_ key: NumericKey) -> Double { numbers[key] ?? key.defaultValue }
        func boolean(_ key: BooleanKey) -> Bool {
            available ? (booleans[key] ?? key.defaultValue) : key.defaultValue
        }
        func selection(_ id: GestureID) -> Selection {
            available ? (selections[id] ?? .disabled) : .disabled
        }

        static let unavailable = Snapshot(available: false, numbers: [:], booleans: [:], selections: [:])
    }

    /// I/O seam for deterministic tests; no codec/policy is replaced by a fixture.
    struct Store {
        let synchronize: () -> Bool
        let copyValues: ([String]) -> [String: Any]?
        let copyValue: (String) -> Any?
        let setValue: (String, Any?) -> Void
        let notify: () -> Void

        static let live = Store(synchronize: {
            CFPreferencesSynchronize(TapLockPreferences.domain as CFString,
                                     kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }, copyValues: { keys in
            CFPreferencesCopyMultiple(keys as CFArray, TapLockPreferences.domain as CFString,
                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any]
        }, copyValue: { key in
            CFPreferencesCopyValue(key as CFString, TapLockPreferences.domain as CFString,
                                   kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }, setValue: { key, value in
            CFPreferencesSetValue(key as CFString, value as CFPropertyList?,
                                  TapLockPreferences.domain as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }, notify: {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(rawValue: TapLockPreferences.changedNotification as CFString),
                nil, nil, true)
        })
    }

    private static var allKeys: [String] {
        NumericKey.allCases.map { $0.rawValue } + BooleanKey.allCases.map { $0.rawValue } +
            GestureID.allCases.flatMap { [$0.rawValue, $0.enabledKey, $0.flowKey] }
    }

    static func readSnapshot() -> Snapshot { readSnapshot(using: .live) }

    static func readSnapshot(using store: Store) -> Snapshot {
        accessLock.lock()
        defer { accessLock.unlock() }
        guard store.synchronize(), let values = store.copyValues(allKeys) else { return .unavailable }
        var numbers: [NumericKey: Double] = [:]
        var booleans: [BooleanKey: Bool] = [:]
        var selections: [GestureID: Selection] = [:]
        for key in NumericKey.allCases {
            if let value = values[key.rawValue] {
                guard let number = decodeNumber(value) else { return .unavailable }
                // Retain finite persisted values verbatim, including crossed
                // thresholds; UI bounds are not a reader clamp/migration.
                numbers[key] = number
            } else { numbers[key] = key.defaultValue }
        }
        for key in BooleanKey.allCases {
            if let value = values[key.rawValue] {
                guard let boolean = decodeBoolean(value) else { return .unavailable }
                booleans[key] = boolean
            } else { booleans[key] = key.defaultValue }
        }
        for id in GestureID.allCases {
            var enabled = false, flowEnabled = false
            var actions: [TapLockPreferences.Action] = []
            if let value = values[id.enabledKey] {
                guard let boolean = decodeBoolean(value) else { return .unavailable }
                enabled = boolean
            }
            if let value = values[id.flowKey] {
                guard let boolean = decodeBoolean(value) else { return .unavailable }
                flowEnabled = boolean
            }
            if let value = values[id.rawValue] {
                guard let decoded = decodeActions(value) else { return .unavailable }
                actions = decoded
            }
            selections[id] = Selection(enabled: enabled, flowEnabled: flowEnabled, actions: actions)
        }
        return Snapshot(available: true, numbers: numbers, booleans: booleans, selections: selections)
    }

    private static func decodeBoolean(_ value: Any) -> Bool? {
        guard CFGetTypeID(value as AnyObject) == CFBooleanGetTypeID(),
              let number = value as? NSNumber else { return nil }
        return number.boolValue
    }

    private static func decodeNumber(_ value: Any) -> Double? {
        guard CFGetTypeID(value as AnyObject) == CFNumberGetTypeID(),
              let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func decodeActions(_ value: Any) -> [TapLockPreferences.Action]? {
        guard CFGetTypeID(value as AnyObject) == CFArrayGetTypeID(),
              let records = value as? [Any] else { return nil }
        var result: [TapLockPreferences.Action] = []
        for value in records {
            guard CFGetTypeID(value as AnyObject) == CFDictionaryGetTypeID(),
                  let record = value as? [String: Any], let kind = record["kind"] as? String else { return nil }
            let action: TapLockPreferences.Action
            if kind == "openApp" {
                guard record.count == 2, let identifier = record["bundleIdentifier"] as? String,
                      TapLockPreferences.validBundleIdentifier(identifier) else { return nil }
                action = .openApp(identifier)
            } else {
                guard record.count == 1 else { return nil }
                switch kind {
                case "lock": action = .lock
                case "controlCenter": action = .controlCenter
                case "notificationCenter": action = .notificationCenter
                case "screenshot": action = .screenshot
                case "appSwitcher": action = .appSwitcher
                case "playPause": action = .playPause
                case "previousTrack": action = .previousTrack
                case "nextTrack": action = .nextTrack
                case "flashlight": action = .flashlight
                case "systemMute": action = .systemMute
                default: return nil
                }
            }
            result.append(action)
        }
        return result
    }

    private static func encodeActions(_ actions: [TapLockPreferences.Action]) -> [[String: String]]? {
        var records: [[String: String]] = []
        for action in actions {
            let record: [String: String]
            switch action {
            case .lock: record = ["kind": "lock"]
            case .controlCenter: record = ["kind": "controlCenter"]
            case .notificationCenter: record = ["kind": "notificationCenter"]
            case .screenshot: record = ["kind": "screenshot"]
            case .appSwitcher: record = ["kind": "appSwitcher"]
            case .playPause: record = ["kind": "playPause"]
            case .previousTrack: record = ["kind": "previousTrack"]
            case .nextTrack: record = ["kind": "nextTrack"]
            case .flashlight: record = ["kind": "flashlight"]
            case .systemMute: record = ["kind": "systemMute"]
            case .openApp(let identifier):
                guard TapLockPreferences.validBundleIdentifier(identifier) else { return nil }
                record = ["kind": "openApp", "bundleIdentifier": identifier]
            case .unavailable: return nil
            }
            records.append(record)
        }
        return records
    }

    @discardableResult
    static func writeNumber(_ value: Double, for key: NumericKey) -> Bool {
        writeNumber(value, for: key, using: .live)
    }

    @discardableResult
    static func writeBoolean(_ value: Bool, for key: BooleanKey) -> Bool {
        writeBoolean(value, for: key, using: .live)
    }

    @discardableResult
    static func writeEnabled(_ value: Bool, for id: GestureID) -> Bool {
        writeEnabled(value, for: id, using: .live)
    }

    @discardableResult
    static func writeFlowEnabled(_ value: Bool, for id: GestureID) -> Bool {
        writeFlowEnabled(value, for: id, using: .live)
    }

    @discardableResult
    static func writeActions(_ actions: [TapLockPreferences.Action], for id: GestureID) -> Bool {
        writeActions(actions, for: id, using: .live)
    }

    static func writeNumber(_ value: Double, for key: NumericKey, using store: Store) -> Bool {
        guard value.isFinite, value >= key.minValue, value <= key.maxValue else { return false }
        return persist(NSNumber(value: value), for: key.rawValue, using: store)
    }

    static func writeBoolean(_ value: Bool, for key: BooleanKey, using store: Store) -> Bool {
        persist(value ? kCFBooleanTrue! : kCFBooleanFalse!, for: key.rawValue, using: store)
    }

    static func writeEnabled(_ value: Bool, for id: GestureID, using store: Store) -> Bool {
        persist(value ? kCFBooleanTrue! : kCFBooleanFalse!, for: id.enabledKey, using: store)
    }

    static func writeFlowEnabled(_ value: Bool, for id: GestureID, using store: Store) -> Bool {
        persist(value ? kCFBooleanTrue! : kCFBooleanFalse!, for: id.flowKey, using: store)
    }

    static func writeActions(_ actions: [TapLockPreferences.Action], for id: GestureID, using store: Store) -> Bool {
        guard let records = encodeActions(actions) else { return false }
        return persist(records, for: id.rawValue, using: store)
    }

    /// Only bottom readers/writers are serialized here; no old key is modified.
    private static let accessLock = NSLock()

    private static func persist(_ value: Any, for key: String, using store: Store) -> Bool {
        accessLock.lock()
        let saved: Bool = {
            guard store.synchronize() else { return false }
            let previous = store.copyValue(key)
            store.setValue(key, value)
            guard store.synchronize() else {
                store.setValue(key, previous)
                _ = store.synchronize()
                return false
            }
            return true
        }()
        accessLock.unlock()
        guard saved else { return false }
        store.notify()
        return true
    }
}
