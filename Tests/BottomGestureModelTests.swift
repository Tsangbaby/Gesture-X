import Foundation
import CoreFoundation

// Compile with the unedited production preferences and geometry files.
// In-memory Store supplies I/O only; all decoding/writing/policy is production.
@main
struct BottomGestureModelTests {
    typealias P = BottomGesturePreferences
    static var assertions = 0

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError("BOTTOM_GESTURE_MODEL_FAIL: " + message) }
    }

    final class MemoryStore {
        var values: [String: Any] = [:]
        var syncResults: [Bool] = []
        var events: [String] = []
        var stored: [(String, Any?)] = []
        var store: P.Store {
            P.Store(synchronize: {
                self.events.append("sync")
                return self.syncResults.isEmpty ? true : self.syncResults.removeFirst()
            }, copyValues: { keys in
                self.events.append("copyValues")
                return self.values.filter { keys.contains($0.key) }
            }, copyValue: { key in
                self.events.append("copy:" + key)
                return self.values[key]
            }, setValue: { key, value in
                self.events.append("set:" + key)
                self.values[key] = value
                self.stored.append((key, value))
            }, notify: { self.events.append("notify") })
        }
    }

    static func defaults() {
        let memory = MemoryStore()
        let snapshot = P.readSnapshot(using: memory.store)
        require(snapshot.available, "missing keys should use defaults")
        require(memory.events == ["sync", "copyValues"], "one synchronized batch read")
        require(P.GestureID.allCases.count == 6, "six gestures")
        require(P.NumericKey.allCases.count == 12, "twelve numeric settings")
        require(P.BooleanKey.allCases.count == 3, "three boolean settings")
        for key in P.NumericKey.allCases {
            require(snapshot.number(key) == key.defaultValue, "default " + key.rawValue)
        }
        for id in P.GestureID.allCases {
            let selection = snapshot.selection(id)
            require(!selection.enabled && !selection.flowEnabled && selection.actions.isEmpty,
                    "missing bottom selection must not inherit lock")
            require(id.enabledKey == id.rawValue + "Enabled", "enabled key")
            require(id.flowKey == id.rawValue + "FlowEnabled", "flow key")
        }
        require(snapshot.boolean(.ignoreEdgeProtect), "edge protect default")
        require(snapshot.boolean(.disableBottomWhenLocked), "lock default")
        require(!snapshot.boolean(.bottomUpOnLandscapeEnabled), "landscape default")
    }

    static func strictSnapshot() {
        let memory = MemoryStore()
        let id = P.GestureID.bottomLeftUp
        memory.values = [id.enabledKey: kCFBooleanTrue!, id.flowKey: kCFBooleanTrue!,
                         id.rawValue: [["kind": "nextTrack"],
                                       ["kind": "openApp", "bundleIdentifier": "com.example.app"],
                                       ["kind": "lock"], ["kind": "nextTrack"]],
                         P.NumericKey.bottomTriggerArea.rawValue: NSNumber(value: 18.125)]
        let snapshot = P.readSnapshot(using: memory.store)
        require(snapshot.available, "valid typed snapshot")
        require(snapshot.selection(id) == P.Selection(enabled: true, flowEnabled: true,
                    actions: [.nextTrack, .openApp("com.example.app"), .lock, .nextTrack]),
                "preserve ordered actions including duplicates")
        require(snapshot.number(.bottomTriggerArea) == 18.125, "no invented slider quantization")
        memory.values[P.NumericKey.bottomTriggerArea.rawValue] = NSNumber(value: -123.25)
        require(P.readSnapshot(using: memory.store).number(.bottomTriggerArea) == -123.25,
                "retain finite legacy values without clamp/sort")
        let malformed: [(String, Any)] = [
            (id.enabledKey, NSNumber(value: 1)), (id.flowKey, "true"),
            (P.BooleanKey.ignoreEdgeProtect.rawValue, NSNumber(value: 0)),
            (P.NumericKey.bottomTriggerArea.rawValue, kCFBooleanTrue!),
            (P.NumericKey.bottomTriggerArea.rawValue, "18"),
            (P.NumericKey.bottomTriggerArea.rawValue, NSNumber(value: Double.nan)),
            (P.NumericKey.bottomTriggerArea.rawValue, NSNumber(value: Double.infinity)),
            (P.NumericKey.bottomTriggerArea.rawValue, NSNull()),
            (id.rawValue, ["kind": "lock"]), (id.rawValue, [NSNull()]),
            (id.rawValue, [["kind": "lock", "extra": "x"]]),
            (id.rawValue, [["kind": "openApp"]]),
            (id.rawValue, [["kind": "openApp", "bundleIdentifier": "bad..id"]]),
            (id.rawValue, [["kind": "openApp", "bundleIdentifier": "com.good", "extra": "x"]]),
            (id.rawValue, [["kind": "unavailable"]]), (id.rawValue, [["kind": "respring"]]),
            (id.rawValue, [["kind": "lock"], ["kind": "unknown"]]),
        ]
        for (key, value) in malformed {
            memory.values = [id.enabledKey: kCFBooleanTrue!]
            memory.values[key] = value
            let bad = P.readSnapshot(using: memory.store)
            require(!bad.available, "malformed key must invalidate snapshot " + key)
            require(bad.selection(id) == .disabled, "malformed data must not execute lock")
        }
        memory.values = [id.rawValue: [] as [[String: String]]]
        require(P.readSnapshot(using: memory.store).selection(id).actions.isEmpty, "explicit empty remains empty")
        memory.syncResults = [false]; memory.events = []
        require(!P.readSnapshot(using: memory.store).available, "failed synchronization unavailable")
        require(memory.events == ["sync"], "no reads after failed synchronization")
        let unavailable = P.Snapshot(available: false, numbers: [:], booleans: [:],
            selections: [id: P.Selection(enabled: true, flowEnabled: true, actions: [.lock])])
        require(unavailable.selection(id) == .disabled, "unavailable always fail closed")
    }

    static func persistence() {
        let actions: [TapLockPreferences.Action] = [.lock, .controlCenter, .notificationCenter,
            .screenshot, .appSwitcher, .playPause, .previousTrack, .nextTrack, .flashlight,
            .systemMute, .openApp("com.example.app"), .lock]
        let id = P.GestureID.bottomRightUpExtraPlus
        let writes: [(String, (P.Store) -> Bool)] = [
            (P.NumericKey.bottomTriggerArea.rawValue, { P.writeNumber(19.125, for: .bottomTriggerArea, using: $0) }),
            (P.BooleanKey.ignoreEdgeProtect.rawValue, { P.writeBoolean(false, for: .ignoreEdgeProtect, using: $0) }),
            (id.enabledKey, { P.writeEnabled(true, for: id, using: $0) }),
            (id.flowKey, { P.writeFlowEnabled(true, for: id, using: $0) }),
            (id.rawValue, { P.writeActions(actions, for: id, using: $0) }),
        ]
        for (key, write) in writes {
            let memory = MemoryStore()
            memory.values["Enabled"] = kCFBooleanTrue!
            memory.values["DoubleTapAction"] = ["kind": "lock"]
            require(write(memory.store), "valid write " + key)
            require(memory.events == ["sync", "copy:" + key, "set:" + key, "sync", "notify"],
                    "write persists before exactly one notification")
            require((memory.values["Enabled"] as? NSNumber)?.boolValue == true, "preserve double tap enabled")
            require(memory.values["DoubleTapAction"] as? [String: String] == ["kind": "lock"], "preserve double tap action")
            if key == id.rawValue {
                require(P.readSnapshot(using: memory.store).selection(id).actions == actions, "all accepted actions round trip")
            }
            for previous in [nil, "opaque previous value"] as [String?] {
                memory.values[key] = previous
                memory.syncResults = [true, false, true]; memory.events = []
                require(!write(memory.store), "failed save returns false")
                require(memory.values[key] as? String == previous, "restore exact previous value or absence")
                require(memory.events == ["sync", "copy:" + key, "set:" + key, "sync", "set:" + key, "sync"],
                        "rollback without notification")
            }
            memory.syncResults = [false]; memory.events = []
            require(!write(memory.store) && memory.events == ["sync"], "failed initial sync must not write")
        }
        let memory = MemoryStore()
        for value in [Double.nan, .infinity, -.infinity, -1, 101] {
            require(!P.writeNumber(value, for: .bottomTriggerArea, using: memory.store), "invalid writer number")
        }
        require(!P.writeActions([.lock, .unavailable], for: id, using: memory.store), "invalid actions atomic rejection")
        require(!P.writeActions([.openApp("bad..id")], for: id, using: memory.store), "invalid identifier rejection")
        require(memory.events.isEmpty, "validation occurs before I/O")
        require(P.writeActions([], for: id, using: memory.store), "can persist empty list")
        require(P.readSnapshot(using: memory.store).selection(id).actions.isEmpty, "empty list remains no action")
        for key in P.NumericKey.allCases {
            require(P.writeNumber(key.minValue, for: key, using: memory.store), "lower writer bound")
            require(P.writeNumber(key.maxValue, for: key, using: memory.store), "upper writer bound")
        }
        for key in P.BooleanKey.allCases {
            require(P.writeBoolean(true, for: key, using: memory.store), "boolean writer true")
            require(P.readSnapshot(using: memory.store).boolean(key), "CFBoolean round trip")
            require(P.writeBoolean(false, for: key, using: memory.store), "boolean writer false")
            require(!P.readSnapshot(using: memory.store).boolean(key), "CFBoolean false round trip")
        }
    }

    typealias G = BottomGestureGeometry
    static let referenceSize = CGSize(width: 400, height: 1000)

    static func modelSnapshot(numbers: [P.NumericKey: Double] = [:], landscape: Bool = false,
                              selections: [P.GestureID: P.Selection]? = nil) -> P.Snapshot {
        let enabled = Dictionary(uniqueKeysWithValues: P.GestureID.allCases.map {
            ($0, P.Selection(enabled: true, flowEnabled: false, actions: [.nextTrack]))
        })
        return P.Snapshot(available: true, numbers: numbers,
                          booleans: [.bottomUpOnLandscapeEnabled: landscape],
                          selections: selections ?? enabled)
    }

    static func near(_ actual: Double, _ expected: Double, _ label: String) {
        require(actual.isFinite && abs(actual - expected) < 0.000000001, label)
    }

    // Literal fixtures from the original arm64e orientation routine 0x7262c-0x7274c,
    // 0x727b4-0x7286c. Never a second implementation of the production algorithm.
    static func geometryReferenceBounds() {
        let portrait = modelSnapshot()
        let landscape = modelSnapshot(landscape: true)
        for raw in [1, 2] {
            guard let b = G.bounds(snapshot: portrait, referenceSize: referenceSize, orientationRaw: raw)
            else { fatalError("BOTTOM_GESTURE_MODEL_FAIL: portrait bounds unavailable") }
            require(b.orientationRaw == raw && b.referenceSize == referenceSize, "retains reference space")
            near(b.leftBoundary, 120, "portrait left width")
            near(b.rightBoundary, 280, "portrait right width")
            near(b.h0, 70, "portrait minimum")
            near(b.h1, 180, "portrait extra minimum")
            near(b.h2, 400, "portrait extra-plus minimum")
            near(b.h3, 600, "portrait maximum")
        }
        for raw in [3, 4] {
            require(G.bounds(snapshot: portrait, referenceSize: referenceSize, orientationRaw: raw) == nil,
                    "landscape independently disabled by default")
            guard let b = G.bounds(snapshot: landscape, referenceSize: referenceSize, orientationRaw: raw)
            else { fatalError("BOTTOM_GESTURE_MODEL_FAIL: landscape bounds unavailable") }
            near(b.leftBoundary, raw == 4 ? 800 : 200, "landscape left boundary uses reference height")
            near(b.rightBoundary, raw == 4 ? 200 : 800, "landscape right boundary uses reference height")
            near(b.h0, 28, "landscape displacement uses reference width")
            near(b.h1, 160, "landscape extra minimum")
            near(b.h2, 280, "landscape extra-plus minimum")
            near(b.h3, 400, "landscape maximum")
        }
        let asymmetric = modelSnapshot(numbers: [.bottomTriggerPositionLandscape: 10,
                                                 .bottomTriggerRightPositionLandscape: 35], landscape: true)
        let b3 = G.bounds(snapshot: asymmetric, referenceSize: referenceSize, orientationRaw: 3)!
        let b4 = G.bounds(snapshot: asymmetric, referenceSize: referenceSize, orientationRaw: 4)!
        near(b3.leftBoundary, 100, "raw3 asymmetric left")
        near(b3.rightBoundary, 650, "raw3 asymmetric right")
        near(b4.leftBoundary, 900, "raw4 asymmetric left complement")
        near(b4.rightBoundary, 350, "raw4 asymmetric right not complement")
    }

    static func geometrySideAndDirection() {
        for raw in [1, 2, 3, 4] {
            let b = G.bounds(snapshot: modelSnapshot(landscape: true), referenceSize: referenceSize,
                             orientationRaw: raw)!
            func point(_ axis: Double) -> CGPoint {
                raw >= 3 ? CGPoint(x: 200, y: axis) : CGPoint(x: axis, y: 1000)
            }
            let left = raw == 4 ? 1000.0 : 0.0
            let right = raw == 4 ? 0.0 : (raw == 3 ? 1000.0 : 400.0)
            require(G.side(origin: point(left), bounds: b) == .left, "left in each reference orientation")
            require(G.side(origin: point(right), bounds: b) == .right, "right in each reference orientation")
            require(G.side(origin: point(b.leftBoundary), bounds: b) == nil, "equal left boundary passes native")
            require(G.side(origin: point(b.rightBoundary), bounds: b) == nil, "equal right boundary passes native")
            require(G.side(origin: point((b.leftBoundary + b.rightBoundary) / 2), bounds: b) == nil,
                    "middle has no gesture")
        }
        let origin = CGPoint(x: 200, y: 500)
        let cases: [(Int, CGPoint, Double)] = [
            (1, CGPoint(x: 333, y: 400), 100), (2, CGPoint(x: 111, y: 400), 100),
            (3, CGPoint(x: 300, y: 777), 100), (4, CGPoint(x: 100, y: 777), 100),
            (1, CGPoint(x: 200, y: 600), -100), (2, CGPoint(x: 200, y: 600), -100),
            (3, CGPoint(x: 100, y: 500), -100), (4, CGPoint(x: 300, y: 500), -100),
        ]
        for (raw, current, expected) in cases {
            require(G.displacement(origin: origin, current: current, orientationRaw: raw) == expected,
                    "origin-relative signed displacement, not total path length")
        }
        require(G.displacement(origin: origin, current: origin, orientationRaw: 1) == 0, "stationary displacement")
        for raw in [0, -1, 5, Int.max] {
            require(G.bounds(snapshot: modelSnapshot(landscape: true), referenceSize: referenceSize,
                             orientationRaw: raw) == nil, "unknown orientation bounds rejected")
            require(G.displacement(origin: origin, current: origin, orientationRaw: raw) == nil,
                    "unknown orientation displacement rejected")
        }
    }

    static func geometryTierBoundaries() {
        let b = G.bounds(snapshot: modelSnapshot(), referenceSize: referenceSize, orientationRaw: 1)!
        let cases: [(Double, G.Tier?)] = [
            (-1, nil), (0, nil), (69.999, nil), (70, nil), (70.001, .ordinary),
            (179.999, .ordinary), (180, .extra), (180.001, .extra),
            (399.999, .extra), (400, .extraPlus), (400.001, .extraPlus),
            (599.999, .extraPlus), (600, nil), (600.001, nil),
            (.nan, nil), (.infinity, nil), (-.infinity, nil),
        ]
        for (distance, expected) in cases {
            require(G.tier(displacement: distance, bounds: b) == expected, "exact tier inclusivity")
        }
        let ids: [(G.Side, G.Tier, P.GestureID)] = [
            (.left, .ordinary, .bottomLeftUp), (.left, .extra, .bottomLeftUpExtra),
            (.left, .extraPlus, .bottomLeftUpExtraPlus), (.right, .ordinary, .bottomRightUp),
            (.right, .extra, .bottomRightUpExtra), (.right, .extraPlus, .bottomRightUpExtraPlus),
        ]
        for (side, tier, expected) in ids {
            require(G.gestureID(side: side, tier: tier) == expected, "six exact tier IDs")
        }
        for raw in [1, 2, 3, 4] {
            let snapshot = modelSnapshot(landscape: true)
            let bounds = G.bounds(snapshot: snapshot, referenceSize: referenceSize, orientationRaw: raw)!
            for side in [G.Side.left, .right] {
                for (d, expected) in [(bounds.h0, nil), ((bounds.h0 + bounds.h1) / 2, G.Tier.ordinary),
                                      (bounds.h1, .extra), (bounds.h2, .extraPlus), (bounds.h3, nil)] {
                    let origin: CGPoint
                    if raw == 3 { origin = CGPoint(x: 0, y: side == .left ? 0 : 1000) }
                    else if raw == 4 { origin = CGPoint(x: 400, y: side == .left ? 1000 : 0) }
                    else { origin = CGPoint(x: side == .left ? 0 : 400, y: 1000) }
                    let current: CGPoint
                    if raw == 3 { current = CGPoint(x: origin.x + d, y: origin.y) }
                    else if raw == 4 { current = CGPoint(x: origin.x - d, y: origin.y) }
                    else { current = CGPoint(x: origin.x, y: origin.y - d) }
                    let match = G.classify(origin: origin, current: current, snapshot: snapshot,
                                           referenceSize: referenceSize, orientationRaw: raw)
                    require(match?.tier == expected, "full geometry orientation/tier matrix")
                    if let expected = expected {
                        require(match?.gestureID == G.gestureID(side: side, tier: expected), "full geometry ID")
                        require(match?.side == side, "full geometry side")
                        require(match?.displacement == d, "full geometry origin-relative displacement")
                    }
                }
            }
        }
    }

    static func geometrySelectionFailClosed() {
        let origin = CGPoint(x: 0, y: 1000)
        func classify(_ snapshot: P.Snapshot, _ y: Double = 800) -> G.Match? {
            G.classify(origin: origin, current: CGPoint(x: 0, y: y), snapshot: snapshot,
                       referenceSize: referenceSize, orientationRaw: 1)
        }
        let disabled = modelSnapshot(selections: [.bottomLeftUp:
            P.Selection(enabled: true, flowEnabled: false, actions: [.lock])])
        require(classify(disabled) == nil, "disabled extra tier must not fall back to ordinary lock")
        let empty = modelSnapshot(selections: [.bottomLeftUpExtra:
            P.Selection(enabled: true, flowEnabled: true, actions: [])])
        require(classify(empty) == nil, "empty action list does not become lock")
        let invalidActions: [[TapLockPreferences.Action]] = [
            [.unavailable], [.lock, .unavailable], [.openApp("bad..id")]
        ]
        for actions in invalidActions {
            require(classify(modelSnapshot(selections: [.bottomLeftUpExtra:
                P.Selection(enabled: true, flowEnabled: true, actions: actions)])) == nil,
                    "malformed constructed selection must not execute")
        }
        let selection = P.Selection(enabled: true, flowEnabled: true,
                                    actions: [.nextTrack, .lock, .nextTrack, .openApp("com.example.app")])
        let configured = modelSnapshot(selections: [.bottomLeftUpExtra: selection])
        require(classify(configured)?.selection == selection, "match retains exact ordered flow selection")
        require(classify(configured, 1100) == nil, "reverse movement no classification")
        require(classify(.unavailable) == nil, "unavailable snapshot no classification")
        let memory = MemoryStore()
        memory.values = [P.GestureID.bottomLeftUpExtra.enabledKey: kCFBooleanTrue!,
                         P.GestureID.bottomLeftUpExtra.rawValue: [["kind": "unknown"]]]
        require(classify(P.readSnapshot(using: memory.store)) == nil, "damaged stored list no classification")
        let badNumbers: [[P.NumericKey: Double]] = [
            [.bottomTriggerArea: .nan], [.bottomTriggerArea: .infinity],
            [.bottomTriggerSensitivity: -1], [.bottomTriggerArea: 101],
            [.bottomTriggerPosition: 51], [.bottomTriggerRightPosition: -1],
            [.bottomTriggerArea: 7], [.bottomTriggerArea: 50],
            [.bottomTriggerExtraArea: 60], [.bottomTriggerExtraPlusArea: 30],
        ]
        for numbers in badNumbers {
            let snapshot = modelSnapshot(numbers: numbers)
            require(G.bounds(snapshot: snapshot, referenceSize: referenceSize, orientationRaw: 1) == nil,
                    "nonfinite/out-of-range/crossed/equal geometry fails closed without sorting")
            require(classify(snapshot) == nil, "invalid geometry cannot produce an action")
        }
        for size in [CGSize.zero, CGSize(width: -1, height: 1000), CGSize(width: 400, height: 0),
                     CGSize(width: Double.nan, height: 1000), CGSize(width: 400, height: Double.infinity)] {
            require(G.bounds(snapshot: configured, referenceSize: size, orientationRaw: 1) == nil,
                    "invalid reference size rejected")
        }
        let bounds = G.bounds(snapshot: configured, referenceSize: referenceSize, orientationRaw: 1)!
        let invalidPoints = [CGPoint(x: Double.nan, y: 1000), CGPoint(x: 0, y: Double.infinity),
                             CGPoint(x: -1, y: 1000), CGPoint(x: 401, y: 1000),
                             CGPoint(x: 0, y: -1), CGPoint(x: 0, y: 1001)]
        for point in invalidPoints {
            require(G.side(origin: point, bounds: bounds) == nil, "nonfinite/out-of-space origin rejected")
        }
        for point in [CGPoint(x: Double.nan, y: 800), CGPoint(x: 0, y: Double.infinity)] {
            require(G.displacement(origin: origin, current: point, orientationRaw: 1) == nil,
                    "all point components must be finite, even perpendicular component")
            require(G.displacement(origin: point, current: origin, orientationRaw: 3) == nil,
                    "nonfinite origin rejected")
            require(G.classify(origin: origin, current: point, snapshot: configured,
                               referenceSize: referenceSize, orientationRaw: 1) == nil, "nonfinite match rejected")
        }
        require(G.displacement(origin: CGPoint(x: -Double.greatestFiniteMagnitude, y: 0),
                               current: CGPoint(x: Double.greatestFiniteMagnitude, y: 0), orientationRaw: 3) == nil,
                "finite operands with overflowing displacement rejected")
        let zeroWidth = modelSnapshot(numbers: [.bottomTriggerPosition: 0])
        require(G.classify(origin: origin, current: CGPoint(x: 0, y: 900), snapshot: zeroWidth,
                           referenceSize: referenceSize, orientationRaw: 1) == nil, "zero width disables that side")
    }

    static func independentSnapshots() {
        let memory = MemoryStore()
        let left = P.GestureID.bottomLeftUp
        let right = P.GestureID.bottomRightUp
        memory.values = [left.enabledKey: kCFBooleanTrue!, left.rawValue: [["kind": "nextTrack"]],
                         right.enabledKey: kCFBooleanTrue!, right.rawValue: [["kind": "previousTrack"]]]
        let old = P.readSnapshot(using: memory.store)
        require(P.writeActions([.systemMute], for: left, using: memory.store), "new configuration saved")
        require(P.writeNumber(25, for: .bottomTriggerArea, using: memory.store), "new threshold saved")
        let fresh = P.readSnapshot(using: memory.store)
        memory.events = []
        let origin = CGPoint(x: 0, y: 1000), current = CGPoint(x: 0, y: 900)
        let oldMatch = G.classify(origin: origin, current: current, snapshot: old,
                                 referenceSize: referenceSize, orientationRaw: 1)
        let freshMatch = G.classify(origin: origin, current: current, snapshot: fresh,
                                   referenceSize: referenceSize, orientationRaw: 1)
        require(oldMatch?.selection.actions == [.nextTrack], "activation retains old immutable selection")
        require(freshMatch?.selection.actions == [.systemMute], "fresh snapshot receives new selection")
        require(old.number(.bottomTriggerArea) == 18 && fresh.number(.bottomTriggerArea) == 25,
                "independent immutable threshold snapshots")
        require(fresh.selection(right).actions == [.previousTrack], "left edits do not change right")
        require(memory.events.isEmpty, "geometry does not synchronize/read/write/notify")
    }

    static func main() {
        defaults()
        strictSnapshot()
        persistence()
        geometryReferenceBounds()
        geometrySideAndDirection()
        geometryTierBoundaries()
        geometrySelectionFailClosed()
        independentSnapshots()
        print("BOTTOM_GESTURE_MODEL_PASS assertions=\(assertions)")
    }
}
