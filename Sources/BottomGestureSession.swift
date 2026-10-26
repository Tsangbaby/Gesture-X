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
        guard Thread.isMainThread else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleOffMain)
            #endif
            return nil
        }
        guard UIApplication.shared.applicationState == .active else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleApplicationInactive)
            #endif
            return nil
        }
        guard let receiver = receiver as? NSObject else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleReceiverUnavailable)
            #endif
            return nil
        }
        guard receiver.isKind(of: capabilities.manager) else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleReceiverWrongType)
            #endif
            return nil
        }
        guard let deck = PrivateAPI.object(receiver, "deckGrabberTongue") else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleDeckUnavailable)
            #endif
            return nil
        }
        guard deck === tongue else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleDeckMismatch)
            #endif
            return nil
        }
        guard deck.isKind(of: capabilities.tongue) else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleDeckWrongType)
            #endif
            return nil
        }
        guard let recognizer = edgeRecognizer(in: deck) else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleRecognizerUnavailable)
            #endif
            return nil
        }
        guard recognizer === gesture else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleRecognizerMismatch)
            #endif
            return nil
        }
        guard let container = recognizer.view else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleRecognizerDetached)
            #endif
            return nil
        }
        guard let window = container.window else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleContainerDetached)
            #endif
            return nil
        }
        guard window.screen === UIScreen.main else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleWrongScreen)
            #endif
            return nil
        }
        guard let scene = window.windowScene else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleSceneUnavailable)
            #endif
            return nil
        }
        guard scene.activationState == .foregroundActive else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleSceneInactive)
            #endif
            return nil
        }
        guard scene.screen === window.screen else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleSceneWrongScreen)
            #endif
            return nil
        }
        guard let referenceRect = referenceRectangle(of: window.screen) else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleReferenceUnavailable)
            #endif
            return nil
        }
        guard let orientationRaw = interfaceOrientation(of: capabilities.application) else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleOrientationUnavailable)
            #endif
            return nil
        }
        guard orientationRaw == scene.interfaceOrientation.rawValue else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleOrientationMismatch)
            #endif
            return nil
        }
        let referenceSpace = window.screen.fixedCoordinateSpace
        guard referenceSpace.bounds == referenceRect else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleReferenceMismatch)
            #endif
            return nil
        }
        let localPoint = recognizer.location(in: container)
        guard localPoint.x.isFinite, localPoint.y.isFinite else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleRawNonfinite)
            #endif
            return nil
        }
        let point = container.convert(localPoint, to: referenceSpace)
        guard point.x.isFinite, point.y.isFinite else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.sampleConvertedNonfinite)
            #endif
            return nil
        }
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
            guard self.tongue === tongue else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.contextTongueChanged)
                #endif
                return false
            }
            guard sample.scene === scene else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.contextSceneChanged)
                #endif
                return false
            }
            guard sample.container === container else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.contextContainerChanged)
                #endif
                return false
            }
            guard sample.recognizer === recognizer else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.contextRecognizerChanged)
                #endif
                return false
            }
            guard sample.deck === deck else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.contextDeckChanged)
                #endif
                return false
            }
            guard sample.screen === screen else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.contextScreenChanged)
                #endif
                return false
            }
            guard sample.referenceSpace === referenceSpace else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.contextReferenceChanged)
                #endif
                return false
            }
            guard sample.referenceRect == referenceRect else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.contextRectangleChanged)
                #endif
                return false
            }
            guard sample.orientationRaw == orientationRaw else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.contextOrientationChanged)
                #endif
                return false
            }
            guard sample.referenceSize == referenceSize else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.contextSizeChanged)
                #endif
                return false
            }
            return true
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
        #if BOTTOM_PANEL_DIAGNOSTIC
        BottomPanelDiagnostic.mark(.sessionInvalidated)
        #endif
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

    #if BOTTOM_PANEL_DIAGNOSTIC
    private func observeClassification(_ saved: Active, _ current: Sample) {
        guard let bounds = BottomGestureGeometry.bounds(snapshot: saved.snapshot,
            referenceSize: saved.referenceSize, orientationRaw: saved.orientationRaw) else {
            BottomPanelDiagnostic.mark(.classificationBoundsRejected); return
        }
        guard BottomGestureGeometry.side(origin: saved.origin, bounds: bounds) != nil else {
            BottomPanelDiagnostic.mark(.classificationOutsideSide); return
        }
        guard let displacement = BottomGestureGeometry.displacement(origin: saved.origin,
            current: current.point, orientationRaw: saved.orientationRaw) else {
            BottomPanelDiagnostic.mark(.classificationNonfinite); return
        }
        guard let tier = BottomGestureGeometry.tier(displacement: displacement, bounds: bounds) else {
            if displacement <= bounds.h0 { BottomPanelDiagnostic.mark(.classificationBelowMinimum) }
            else { BottomPanelDiagnostic.mark(.classificationAboveMaximum) }
            return
        }
        switch tier {
        case .ordinary: BottomPanelDiagnostic.mark(.classificationOrdinary)
        case .extra: BottomPanelDiagnostic.mark(.classificationExtra)
        case .extraPlus: BottomPanelDiagnostic.mark(.classificationExtraPlus)
        }
        let side = BottomGestureGeometry.side(origin: saved.origin, bounds: bounds)!
        let selection = saved.snapshot.selection(BottomGestureGeometry.gestureID(side: side, tier: tier))
        if !selection.enabled { BottomPanelDiagnostic.mark(.classificationDisabledTier) }
        else if selection.actions.isEmpty { BottomPanelDiagnostic.mark(.classificationEmptyActions) }
        else { BottomPanelDiagnostic.mark(.classificationInvalidActions) }
    }
    #endif

    func receive(_ phase: BottomGestureHooks.Phase, receiver: AnyObject,
                 tongue: AnyObject?, gesture: AnyObject?, forward: () -> Void) {
        guard Thread.isMainThread else { forward(); return }
        switch phase {
        case .began:
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.admission(true)
            defer { BottomPanelDiagnostic.admission(false) }
            #endif
            // Until separately proven lock-screen ingress is available, fluid
            // callbacks require known-unlocked eligibility EVEN if the setting
            // permits locked use. Unknown/locked preserves native input.
            guard active == nil else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.beganAlreadyOwned)
                #endif
                forward(); return
            }
            guard let gesture = gesture else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.beganGestureUnavailable)
                #endif
                forward(); return
            }
            guard let tongue = tongue else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.beganTongueUnavailable)
                #endif
                forward(); return
            }
            guard snapshot.available else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.beganPreferencesUnavailable)
                #endif
                forward(); return
            }
            guard unlocked() else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.beganLockedOrUnknown)
                #endif
                forward(); return
            }
            guard let current = sample(receiver, tongue, gesture) else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.beganSampleUnavailable)
                #endif
                forward(); return
            }
            guard let bounds = BottomGestureGeometry.bounds(snapshot: snapshot,
                referenceSize: current.referenceSize, orientationRaw: current.orientationRaw) else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.beganBoundsUnavailable)
                #endif
                forward(); return
            }
            guard let side = BottomGestureGeometry.side(origin: current.point, bounds: bounds) else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.beganOutsideSide)
                #endif
                forward(); return
            }
            guard enabledSide(side, snapshot: snapshot) else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.beganSideDisabled)
                #endif
                forward(); return
            }
            active = Active(receiver: receiver, gesture: gesture, tongue: tongue,
                            sample: current, snapshot: snapshot)
            cancelPendingFlow() // Never dismiss an already displayed panel here.
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.beganAdmitted)
            #endif
            // Only admitted Began suppresses its captured predecessor.
        case .updated:
            if let saved = active, saved.owns(receiver, gesture), !saved.ending {
                if !unlocked() {
                    #if BOTTOM_PANEL_DIAGNOSTIC
                    BottomPanelDiagnostic.mark(.updateLocked)
                    #endif
                    invalidate()
                } else if let current = sample(receiver, tongue, gesture) {
                    if !saved.accepts(current, tongue: tongue) {
                        #if BOTTOM_PANEL_DIAGNOSTIC
                        BottomPanelDiagnostic.mark(.updateContextRejected)
                        #endif
                        invalidate()
                    }
                } else {
                    #if BOTTOM_PANEL_DIAGNOSTIC
                    BottomPanelDiagnostic.mark(.updateSampleRejected)
                    #endif
                    invalidate()
                }
            }
            forward() // Always, even if Began was consumed or context is gone.
        case .ended:
            let saved = active
            if let saved = saved, saved.owns(receiver, gesture), !saved.ending {
                saved.ending = true // Reentrant Ended cannot submit twice.
                defer { reset(ifSame: saved) }
                func submitIfEligible() {
                    guard unlocked() else {
                        #if BOTTOM_PANEL_DIAGNOSTIC
                        BottomPanelDiagnostic.mark(.endedLocked)
                        #endif
                        invalidate(); return
                    }
                    guard let current = sample(receiver, tongue, gesture) else {
                        #if BOTTOM_PANEL_DIAGNOSTIC
                        BottomPanelDiagnostic.mark(.endedSampleRejected)
                        #endif
                        invalidate(); return
                    }
                    guard saved.accepts(current, tongue: tongue) else {
                        #if BOTTOM_PANEL_DIAGNOSTIC
                        BottomPanelDiagnostic.mark(.endedContextRejected)
                        #endif
                        invalidate(); return
                    }
                    if let match = BottomGestureGeometry.classify(origin: saved.origin, current: current.point,
                        snapshot: saved.snapshot, referenceSize: saved.referenceSize,
                        orientationRaw: saved.orientationRaw) {
                        #if BOTTOM_PANEL_DIAGNOSTIC
                        BottomPanelDiagnostic.mark(.actionSubmitted)
                        #endif
                        trigger(match.selection, saved.scene, false)
                    } else {
                        #if BOTTOM_PANEL_DIAGNOSTIC
                        observeClassification(saved, current)
                        BottomPanelDiagnostic.mark(.endedClassificationRejected)
                        #endif
                    }
                }
                submitIfEligible()
                forward() // Submission BEFORE native; own cleanup AFTER native.
            } else {
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.endedWithoutOwner)
                #endif
                forward()
            }
        case .canceled:
            let saved = active
            if let saved = saved, saved.owns(receiver, gesture) { saved.ending = true }
            forward()
            if let saved = saved, saved.owns(receiver, gesture) { reset(ifSame: saved) }
        }
    }
}
