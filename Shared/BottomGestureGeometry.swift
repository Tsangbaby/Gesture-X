import Foundation

/// Pure policy in the callback's unrotated reference space. The caller supplies
/// the matching point/size units and freezes orientation + Snapshot at Began.
/// No screen lookup, preference I/O, action dispatch or native forwarding here.
enum BottomGestureGeometry {
    typealias Preferences = BottomGesturePreferences

    enum Side: Equatable { case left, right }
    enum Tier: Equatable { case ordinary, extra, extraPlus }

    struct Bounds: Equatable {
        let orientationRaw: Int
        let referenceSize: CGSize
        let leftBoundary: Double
        let rightBoundary: Double
        let h0: Double
        let h1: Double
        let h2: Double
        let h3: Double

        // Consumers obtain validated values from bounds(), not an initializer.
        fileprivate init(orientationRaw: Int, referenceSize: CGSize,
                         leftBoundary: Double, rightBoundary: Double,
                         h0: Double, h1: Double, h2: Double, h3: Double) {
            self.orientationRaw = orientationRaw
            self.referenceSize = referenceSize
            self.leftBoundary = leftBoundary
            self.rightBoundary = rightBoundary
            self.h0 = h0
            self.h1 = h1
            self.h2 = h2
            self.h3 = h3
        }
    }

    struct Match: Equatable {
        let side: Side
        let tier: Tier
        let gestureID: Preferences.GestureID
        let displacement: Double
        let selection: Preferences.Selection
    }

    /// arm64e reference routine 0x7262c-0x7274c (landscape) and
    /// 0x727b4-0x7286c (portrait), slice SHA256 1925f96a…ef7f6d.
    /// Reference bounds.width/height are stored at 0xfe248/0xfe230 respectively
    /// (0x72d10-0x72d48). Do NOT swap the caller's size for landscape.
    /// Range/strict-order rejection is the port's fail-closed safety policy;
    /// persisted finite values remain untouched and thresholds are never sorted.
    static func bounds(snapshot: Preferences.Snapshot, referenceSize: CGSize,
                       orientationRaw: Int) -> Bounds? {
        guard snapshot.available, (1...4).contains(orientationRaw),
              referenceSize.width.isFinite, referenceSize.height.isFinite,
              referenceSize.width > 0, referenceSize.height > 0 else { return nil }
        let landscape = orientationRaw == 3 || orientationRaw == 4
        guard !landscape || snapshot.boolean(.bottomUpOnLandscapeEnabled) else { return nil }
        for key in Preferences.NumericKey.allCases {
            let value = snapshot.number(key)
            guard value.isFinite, value >= key.minValue, value <= key.maxValue else { return nil }
        }
        let left = snapshot.number(landscape ? .bottomTriggerPositionLandscape : .bottomTriggerPosition)
        let right = snapshot.number(landscape ? .bottomTriggerRightPositionLandscape : .bottomTriggerRightPosition)
        let minimum = snapshot.number(landscape ? .bottomTriggerSensitivityLandscape : .bottomTriggerSensitivity)
        let extra = snapshot.number(landscape ? .bottomTriggerAreaLandscape : .bottomTriggerArea)
        let extraPlus = snapshot.number(landscape ? .bottomTriggerExtraAreaLandscape : .bottomTriggerExtraArea)
        let maximum = snapshot.number(landscape ? .bottomTriggerExtraPlusAreaLandscape : .bottomTriggerExtraPlusArea)
        guard minimum < extra, extra < extraPlus, extraPlus < maximum else { return nil }
        let sideExtent = Double(landscape ? referenceSize.height : referenceSize.width)
        let heightExtent = Double(landscape ? referenceSize.width : referenceSize.height)
        let leftBoundary = (orientationRaw == 4 ? (100 - left) : left) / 100 * sideExtent
        let rightBoundary = (orientationRaw == 4 ? right : (100 - right)) / 100 * sideExtent
        let h0 = minimum / 100 * heightExtent
        let h1 = extra / 100 * heightExtent
        let h2 = extraPlus / 100 * heightExtent
        let h3 = maximum / 100 * heightExtent
        guard [leftBoundary, rightBoundary, h0, h1, h2, h3].allSatisfy({ $0.isFinite }),
              h0 < h1, h1 < h2, h2 < h3 else { return nil }
        return Bounds(orientationRaw: orientationRaw, referenceSize: referenceSize,
                      leftBoundary: leftBoundary, rightBoundary: rightBoundary,
                      h0: h0, h1: h1, h2: h2, h3: h3)
    }

    /// Strict comparisons preserve equal-boundary/middle native admission.
    /// raw 4 reverses the y-side predicates, not the reference width/height.
    static func side(origin: CGPoint, bounds: Bounds) -> Side? {
        guard finite(origin), origin.x >= 0, origin.y >= 0,
              origin.x <= bounds.referenceSize.width,
              origin.y <= bounds.referenceSize.height else { return nil }
        switch bounds.orientationRaw {
        case 4:
            if origin.y > bounds.leftBoundary { return .left }
            if origin.y < bounds.rightBoundary { return .right }
        case 3:
            if origin.y < bounds.leftBoundary { return .left }
            if origin.y > bounds.rightBoundary { return .right }
        case 1, 2:
            if origin.x < bounds.leftBoundary { return .left }
            if origin.x > bounds.rightBoundary { return .right }
        default: return nil
        }
        return nil
    }

    /// Signed net displacement, never accumulated travel or start-edge depth.
    /// Both components are checked even when one is perpendicular to the axis.
    static func displacement(origin: CGPoint, current: CGPoint, orientationRaw: Int) -> Double? {
        guard finite(origin), finite(current) else { return nil }
        let value: CGFloat
        switch orientationRaw {
        case 3: value = current.x - origin.x
        case 4: value = origin.x - current.x
        case 1, 2: value = origin.y - current.y
        default: return nil
        }
        guard value.isFinite else { return nil }
        return Double(value)
    }

    static func tier(displacement: Double, bounds: Bounds) -> Tier? {
        guard displacement.isFinite, displacement > bounds.h0, displacement < bounds.h3 else { return nil }
        if displacement < bounds.h1 { return .ordinary }
        if displacement < bounds.h2 { return .extra }
        return .extraPlus
    }

    static func gestureID(side: Side, tier: Tier) -> Preferences.GestureID {
        switch (side, tier) {
        case (.left, .ordinary): return .bottomLeftUp
        case (.left, .extra): return .bottomLeftUpExtra
        case (.left, .extraPlus): return .bottomLeftUpExtraPlus
        case (.right, .ordinary): return .bottomRightUp
        case (.right, .extra): return .bottomRightUpExtra
        case (.right, .extraPlus): return .bottomRightUpExtraPlus
        }
    }

    /// Evaluates only the geometrically selected tier. Disabled, empty or damaged
    /// selections return nil with no lower-tier or accepted double-tap fallback.
    /// This is action eligibility, NOT the Began native-suppression decision.
    static func classify(origin: CGPoint, current: CGPoint, snapshot: Preferences.Snapshot,
                         referenceSize: CGSize, orientationRaw: Int) -> Match? {
        guard let bounds = Self.bounds(snapshot: snapshot, referenceSize: referenceSize, orientationRaw: orientationRaw),
              let side = Self.side(origin: origin, bounds: bounds),
              let displacement = Self.displacement(origin: origin, current: current, orientationRaw: orientationRaw),
              let tier = Self.tier(displacement: displacement, bounds: bounds) else { return nil }
        let id = gestureID(side: side, tier: tier)
        let selection = snapshot.selection(id)
        guard selection.enabled, !selection.actions.isEmpty,
              selection.actions.allSatisfy({ action in
                  switch action {
                  case .unavailable: return false
                  case .openApp(let identifier): return TapLockPreferences.validBundleIdentifier(identifier)
                  default: return true
                  }
              }) else { return nil }
        return Match(side: side, tier: tier, gestureID: id, displacement: displacement, selection: selection)
    }

    private static func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }
}
