import UIKit
import ObjectiveC

/// Recovered deck/container/recognizer source, normalized explicitly to the
/// attached screen's validated fixed coordinate space. This normalization is a
/// maintained safety policy, NOT a claim that raw container points were fixed.
struct BottomGestureSample {
    let point: CGPoint
    let referenceRect: CGRect
    var referenceSize: CGSize { referenceRect.size }
    let orientationRaw: Int
    let scene: UIWindowScene
    let screen: UIScreen
    let referenceSpace: UICoordinateSpace
    let container: UIView
    let recognizer: UIGestureRecognizer
    let deck: NSObject

    /// Only external runtime class/receiver bindings vary in the UIKit harness.
    /// All acquisition, method gates and point conversion remain production code.
    struct Capabilities {
        let manager: AnyClass
        let tongue: AnyClass
        let application: NSObject
    }

    static func capture(_ receiver: AnyObject, _ tongue: AnyObject?,
                        _ gesture: AnyObject?) -> BottomGestureSample? {
        guard let capabilities = liveCapabilities() else { return nil }
        return captureValidated(receiver, tongue, gesture, capabilities: capabilities)
    }

    private static func liveCapabilities() -> Capabilities? {
        guard Thread.isMainThread,
              let manager = NSClassFromString("SBFluidSwitcherGestureManager"),
              let tongueType = NSClassFromString("SBGrabberTongue"),
              let applicationType = NSClassFromString("SpringBoard"),
              let application = PrivateAPI.object(applicationType as AnyObject, "sharedApplication"),
              application.isKind(of: applicationType) else { return nil }
        return Capabilities(manager: manager, tongue: tongueType, application: application)
    }

    static func captureEdge(_ receiver: AnyObject) -> BottomGestureSample? {
        guard let capabilities = liveCapabilities(),
              let receiver = receiver as? NSObject, receiver.isKind(of: capabilities.manager),
              let deck = PrivateAPI.object(receiver, "deckGrabberTongue"),
              deck.isKind(of: capabilities.tongue),
              let gesture = edgeRecognizer(in: deck) else { return nil }
        return captureValidated(receiver, deck, gesture, capabilities: capabilities)
    }

    static func captureValidated(_ receiver: AnyObject, _ tongue: AnyObject?, _ gesture: AnyObject?,
                                 capabilities: Capabilities) -> BottomGestureSample? {
        guard Thread.isMainThread,
              UIApplication.shared.applicationState == .active,
              let receiver = receiver as? NSObject, receiver.isKind(of: capabilities.manager),
              let deck = PrivateAPI.object(receiver, "deckGrabberTongue"), deck === tongue,
              deck.isKind(of: capabilities.tongue),
              let recognizer = edgeRecognizer(in: deck), recognizer === gesture,
              let container = recognizer.view,
              let window = container.window, window.screen === UIScreen.main,
              let scene = window.windowScene, scene.activationState == .foregroundActive,
              scene.screen === window.screen,
              let referenceRect = referenceRectangle(of: window.screen),
              let orientationRaw = interfaceOrientation(of: capabilities.application),
              orientationRaw == scene.interfaceOrientation.rawValue else { return nil }
        let referenceSpace = window.screen.fixedCoordinateSpace
        guard referenceSpace.bounds == referenceRect else { return nil }
        let point = container.convert(recognizer.location(in: container), to: referenceSpace)
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return BottomGestureSample(point: point, referenceRect: referenceRect,
            orientationRaw: orientationRaw, scene: scene, screen: window.screen, referenceSpace: referenceSpace,
            container: container, recognizer: recognizer, deck: deck)
    }

    /// No guessed underscored getters, KVC, offsets or scalar-as-object reads.
    static func objectIvar(_ receiver: NSObject, _ name: String) -> NSObject? {
        guard Thread.isMainThread, let type = object_getClass(receiver) else { return nil }
        guard let ivar = class_getInstanceVariable(type, name),
              let raw = ivar_getTypeEncoding(ivar) else { return nil }
        let encoding = String(cString: raw)
        guard encoding == "@" || encoding.range(of: #"^@"[A-Za-z_][A-Za-z0-9_]*"$"#, options: .regularExpression) != nil else {
            return nil
        }
        return object_getIvar(receiver, ivar) as? NSObject
    }

    static func edgeRecognizer(in deck: NSObject) -> UIGestureRecognizer? {
        guard Thread.isMainThread, let type = object_getClass(deck) else { return nil }
        let name = "edgePullGestureRecognizer"
        if class_getInstanceMethod(type, NSSelectorFromString(name)) != nil {
            return PrivateAPI.object(deck, name) as? UIGestureRecognizer
        }
        return objectIvar(deck, "_edgePullGestureRecognizer") as? UIGestureRecognizer
    }

    static func interfaceOrientation(of application: NSObject) -> Int? {
        let selector = NSSelectorFromString("activeInterfaceOrientation")
        guard Thread.isMainThread, let type = object_getClass(application),
              let method = PrivateAPI.checkedMethod(in: type, selector: selector, returns: "q") else { return nil }
        typealias GetOrientation = @convention(c) (AnyObject, Selector) -> Int64
        let invoke = unsafeBitCast(method_getImplementation(method), to: GetOrientation.self)
        let raw = invoke(application, selector)
        return (1...4).contains(raw) ? Int(raw) : nil
    }

    static func referenceRectangle(of screen: UIScreen) -> CGRect? {
        let selector = NSSelectorFromString("_referenceBounds")
        guard Thread.isMainThread, let type = object_getClass(screen),
              let method = PrivateAPI.checkedMethod(in: type, selector: selector,
                  returns: "{CGRect={CGPoint=dd}{CGSize=dd}}") else { return nil }
        typealias GetRect = @convention(c) (AnyObject, Selector) -> CGRect
        let invoke = unsafeBitCast(method_getImplementation(method), to: GetRect.self)
        let rectangle = invoke(screen, selector)
        guard rectangle.origin == .zero, rectangle.width.isFinite, rectangle.height.isFinite,
              rectangle.width > 0, rectangle.height > 0 else { return nil }
        return rectangle
    }
}

/// Main-thread-only ownership. Retaining the actual receiver/gesture prevents
/// pointer reuse; foreign callbacks neither dispatch nor clear the active owner.
/// Explicit reset on cancel/failure is maintained safety, not reference-global
/// quirk parity. Ending a session does NOT cancel its newly submitted flow.
final class BottomGestureSession {
    typealias Preferences = BottomGesturePreferences
    typealias Sample = BottomGestureSample
    private final class Active {
        let receiver: AnyObject
        let gesture: AnyObject
        let tongue: AnyObject
        let origin: CGPoint
        let snapshot: Preferences.Snapshot
        let referenceSize: CGSize
        let referenceRect: CGRect
        let orientationRaw: Int
        let scene: UIWindowScene
        let screen: UIScreen
        let referenceSpace: UICoordinateSpace
        let container: UIView
        let recognizer: UIGestureRecognizer
        let deck: NSObject
        var ending = false

        init(receiver: AnyObject, gesture: AnyObject, tongue: AnyObject,
             sample: Sample, snapshot: Preferences.Snapshot) {
            self.receiver = receiver; self.gesture = gesture; self.tongue = tongue
            origin = sample.point; self.snapshot = snapshot
            referenceSize = sample.referenceSize; orientationRaw = sample.orientationRaw
            referenceRect = sample.referenceRect; screen = sample.screen; referenceSpace = sample.referenceSpace
            scene = sample.scene; container = sample.container
            recognizer = sample.recognizer; deck = sample.deck
        }

        func owns(_ receiver: AnyObject, _ gesture: AnyObject?) -> Bool {
            self.receiver === receiver && self.gesture === gesture
        }
        func accepts(_ sample: Sample, tongue: AnyObject?) -> Bool {
            self.tongue === tongue && sample.scene === scene && sample.container === container &&
                sample.recognizer === recognizer && sample.deck === deck &&
                sample.screen === screen && sample.referenceSpace === referenceSpace &&
                sample.referenceRect == referenceRect &&
                sample.orientationRaw == orientationRaw && sample.referenceSize == referenceSize
        }
    }

    private let sample: (AnyObject, AnyObject?, AnyObject?) -> Sample?
    private let edgeSample: ((AnyObject) -> Sample?)?
    private let unlocked: () -> Bool
    private let trigger: (Preferences.Selection, UIWindowScene, Bool) -> Void
    private let cancelPendingFlow: () -> Void
    private let cancelAll: () -> Void
    private var snapshot: Preferences.Snapshot = .unavailable
    private var active: Active?

    init(sample: @escaping (AnyObject, AnyObject?, AnyObject?) -> Sample?,
         edgeSample: ((AnyObject) -> Sample?)? = nil,
         unlocked: @escaping () -> Bool,
         trigger: @escaping (Preferences.Selection, UIWindowScene, Bool) -> Void,
         cancelPendingFlow: @escaping () -> Void, cancelAll: @escaping () -> Void) {
        self.sample = sample; self.edgeSample = edgeSample; self.unlocked = unlocked; self.trigger = trigger
        self.cancelPendingFlow = cancelPendingFlow; self.cancelAll = cancelAll
    }

    func reload(_ snapshot: Preferences.Snapshot) {
        guard Thread.isMainThread else { return }
        invalidate()
        self.snapshot = snapshot
    }

    func invalidate() {
        guard Thread.isMainThread else { return }
        active = nil
        cancelAll()
    }

    func invalidate(in scene: UIWindowScene) {
        guard Thread.isMainThread, active?.scene === scene else { return }
        invalidate()
    }

    private func reset(ifSame saved: Active) {
        if active === saved { active = nil }
    }

    private func enabledSide(_ side: BottomGestureGeometry.Side,
                             snapshot: Preferences.Snapshot) -> Bool {
        [BottomGestureGeometry.Tier.ordinary, .extra, .extraPlus].contains {
            snapshot.selection(BottomGestureGeometry.gestureID(side: side, tier: $0)).enabled
        }
    }

    /// Parent-authorized narrow policy, not the unresolved raw-global formula.
    func shouldRelaxEdge(_ location: Double, receiver: AnyObject) -> Bool {
        guard Thread.isMainThread, location.isFinite, snapshot.available,
              snapshot.boolean(.ignoreEdgeProtect), unlocked(),
              let current = edgeSample?(receiver),
              let bounds = BottomGestureGeometry.bounds(snapshot: snapshot,
                  referenceSize: current.referenceSize, orientationRaw: current.orientationRaw) else { return false }
        let origin = current.orientationRaw == 3 || current.orientationRaw == 4 ?
            CGPoint(x: 0, y: location) : CGPoint(x: location, y: 0)
        guard let side = BottomGestureGeometry.side(origin: origin, bounds: bounds) else { return false }
        return enabledSide(side, snapshot: snapshot)
    }

    func receive(_ phase: BottomGestureHooks.Phase, receiver: AnyObject,
                 tongue: AnyObject?, gesture: AnyObject?, forward: () -> Void) {
        guard Thread.isMainThread else { forward(); return }
        switch phase {
        case .began:
            // Until separately proven lock-screen ingress is available, fluid
            // callbacks require known-unlocked eligibility EVEN if the setting
            // permits locked use. Unknown/locked preserves native input.
            guard active == nil, let gesture = gesture, let tongue = tongue,
                  snapshot.available, unlocked(),
                  let current = sample(receiver, tongue, gesture),
                  let bounds = BottomGestureGeometry.bounds(snapshot: snapshot,
                      referenceSize: current.referenceSize, orientationRaw: current.orientationRaw),
                  let side = BottomGestureGeometry.side(origin: current.point, bounds: bounds),
                  enabledSide(side, snapshot: snapshot) else { forward(); return }
            active = Active(receiver: receiver, gesture: gesture, tongue: tongue,
                            sample: current, snapshot: snapshot)
            cancelPendingFlow() // Never dismiss an already displayed panel here.
            // Only admitted Began suppresses its captured predecessor.
        case .updated:
            if let saved = active, saved.owns(receiver, gesture), !saved.ending {
                if !unlocked() || sample(receiver, tongue, gesture).map({ saved.accepts($0, tongue: tongue) }) != true {
                    invalidate()
                }
            }
            forward() // Always, even if Began was consumed or context is gone.
        case .ended:
            let saved = active
            if let saved = saved, saved.owns(receiver, gesture), !saved.ending {
                saved.ending = true // Reentrant Ended cannot submit twice.
                defer { reset(ifSame: saved) }
                if unlocked(), let current = sample(receiver, tongue, gesture),
                   saved.accepts(current, tongue: tongue) {
                    if let match = BottomGestureGeometry.classify(origin: saved.origin, current: current.point,
                        snapshot: saved.snapshot, referenceSize: saved.referenceSize,
                        orientationRaw: saved.orientationRaw) {
                        trigger(match.selection, saved.scene, false)
                    }
                } else { invalidate() }
                forward() // Submission BEFORE native; own cleanup AFTER native.
            } else { forward() }
        case .canceled:
            let saved = active
            if let saved = saved, saved.owns(receiver, gesture) { saved.ending = true }
            forward()
            if let saved = saved, saved.owns(receiver, gesture) { reset(ifSame: saved) }
        }
    }
}
