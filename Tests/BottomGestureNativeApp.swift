import UIKit
import ObjectiveC
import Darwin

// Unique runtime names: never impersonate a possibly-loaded SpringBoard class.
// Only sample/eligibility/provider effects and the substrate backend are fixtures;
// callbacks execute the actual production replacement IMP/session/core/coordinator.
@objc(TLBottomNativeRecognizerFixture)
final class NativeRecognizerFixture: UIGestureRecognizer {
    var point = CGPoint(x: 10, y: 790)
    override func location(in view: UIView?) -> CGPoint { point }
}

final class NativeDeckFixture {
    static let runtimeType: AnyClass = {
        let type = objc_allocateClassPair(NSObject.self, "TLBottomNativeDeckObjectFixture", 0)!
        let alignment = UInt8(MemoryLayout<AnyObject>.alignment.trailingZeroBitCount)
        precondition(class_addIvar(type, "_tongueContainer", MemoryLayout<AnyObject>.size, alignment, "@"))
        precondition(class_addIvar(type, "_edgePullGestureRecognizer", MemoryLayout<AnyObject>.size, alignment, "@"))
        typealias Getter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let getter: Getter = { receiver, _ in
            guard let ivar = class_getInstanceVariable(object_getClass(receiver)!, "_edgePullGestureRecognizer"),
                  let object = object_getIvar(receiver, ivar) else { return nil }
            return Unmanaged.passUnretained(object as AnyObject)
        }
        precondition(class_addMethod(type, NSSelectorFromString("edgePullGestureRecognizer"),
            unsafeBitCast(getter, to: IMP.self), "@@:"))
        objc_registerClassPair(type)
        return type
    }()
    let object = class_createInstance(NativeDeckFixture.runtimeType, 0) as! NSObject
    var container: UIView! {
        didSet { object_setIvar(object, class_getInstanceVariable(Self.runtimeType, "_tongueContainer")!, container) }
    }
    var recognizer: NativeRecognizerFixture! {
        didSet { object_setIvar(object, class_getInstanceVariable(Self.runtimeType, "_edgePullGestureRecognizer")!, recognizer) }
    }
}

@objc(TLBottomOrientationFixture)
final class NativeOrientationFixture: NSObject {
    var raw: Int64 = 1
    @objc dynamic func activeInterfaceOrientation() -> Int64 { raw }
}

private struct OriginalCall {
    let receiver: AnyObject
    let selector: Selector
    let tongue: AnyObject?
    let distance: Double
    let velocity: Double
    let gesture: AnyObject?
}

@objc(TLBottomNativeReceiverFixture)
final class NativeReceiverFixture: NSObject {
    let deck = NativeDeckFixture()
    fileprivate var original: ((OriginalCall) -> Void)?
    var protected = true
    var edgeCalls: [(AnyObject, Selector, Double)] = []
    @objc dynamic func deckGrabberTongue() -> AnyObject { deck.object }

    @objc(grabberTongueBeganPulling:withDistance:andVelocity:andGesture:)
    dynamic func began(_ tongue: AnyObject?, distance: Double, velocity: Double, gesture: AnyObject?) {
        record(0, tongue, distance, velocity, gesture)
    }
    @objc(grabberTongueUpdatedPulling:withDistance:andVelocity:andGesture:)
    dynamic func updated(_ tongue: AnyObject?, distance: Double, velocity: Double, gesture: AnyObject?) {
        record(1, tongue, distance, velocity, gesture)
    }
    @objc(grabberTongueEndedPulling:withDistance:andVelocity:andGesture:)
    dynamic func ended(_ tongue: AnyObject?, distance: Double, velocity: Double, gesture: AnyObject?) {
        record(2, tongue, distance, velocity, gesture)
    }
    @objc(grabberTongueCanceledPulling:withDistance:andVelocity:andGesture:)
    dynamic func canceled(_ tongue: AnyObject?, distance: Double, velocity: Double, gesture: AnyObject?) {
        record(3, tongue, distance, velocity, gesture)
    }
    @objc(_shouldProtectEdgeLocation:)
    dynamic func edge(_ location: Double) -> Bool {
        edgeCalls.append((self, NSSelectorFromString("_shouldProtectEdgeLocation:"), location))
        return protected
    }
    private func record(_ index: Int, _ tongue: AnyObject?, _ distance: Double,
                        _ velocity: Double, _ gesture: AnyObject?) {
        original?(OriginalCall(receiver: self, selector: BottomGestureHooks.selectors[index],
            tongue: tongue, distance: distance, velocity: velocity, gesture: gesture))
    }
}

@main
final class BottomGestureNativeApp: UIResponder, UIApplicationDelegate, UIWindowSceneDelegate {
    var window: UIWindow?
    private var checks = 0
    private var sampleReads = 0
    private var events: [String] = []
    private var calls: [OriginalCall] = []
    private var selections: [BottomGesturePreferences.Selection] = []
    private let receiver = NativeReceiverFixture()
    private let other = NativeReceiverFixture()
    private var owner: BottomGestureSession!
    private var hooks: BottomGestureHooks!
    private var scene: UIWindowScene!
    private var raw = 1
    private var size = CGSize(width: 400, height: 800)
    private var allowed = true
    private var sampleAvailable = true
    private var alternateContainer: UIView?
    private var coordinator: BottomActionCoordinator?
    private var providerActions: [TapLockPreferences.Action] = []
    private var jobs: [() -> Void] = []
    private var serial = 0

    // Independent C-callable predecessor: capture the ACTUAL incoming _cmd,
    // not a selector reconstructed from the Swift fixture method name.
    private static let exactPredecessor: BottomGestureHooks.PullCall = { receiver, selector, tongue, distance, velocity, gesture in
        guard let target = receiver as? NativeReceiverFixture else { return }
        target.original?(OriginalCall(receiver: receiver, selector: selector, tongue: tongue, distance: distance,
            velocity: velocity, gesture: gesture))
    }
    private typealias EdgePredecessor = @convention(c) (AnyObject, Selector, Double) -> Bool
    private static let exactEdgePredecessor: EdgePredecessor = { receiver, selector, location in
        guard let target = receiver as? NativeReceiverFixture else { return true }
        target.edgeCalls.append((receiver, selector, location))
        return target.protected
    }

    private func require(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else {
            print("BOTTOM_GESTURE_NATIVE_FAIL: " + name); fflush(stdout); exit(1)
        }
        checks += 1
    }
    private func checkpoint(_ text: String) {
        print("BOTTOM_GESTURE_NATIVE_CHECKPOINT: " + text); fflush(stdout)
    }
    private func configured(disabled: BottomGesturePreferences.GestureID? = nil,
                            ignore: Bool = true, allOff: Bool = false,
                            flow: Bool = false) -> BottomGesturePreferences.Snapshot {
        var selections: [BottomGesturePreferences.GestureID: BottomGesturePreferences.Selection] = [:]
        for (index, id) in BottomGesturePreferences.GestureID.allCases.enumerated() {
            let actions: [TapLockPreferences.Action] = [.lock, .flashlight, .systemMute, .playPause, .previousTrack, .nextTrack]
            selections[id] = .init(enabled: !allOff && id != disabled, flowEnabled: flow,
                                  actions: flow ? [.playPause, .nextTrack] : [actions[index]])
        }
        return .init(available: true, numbers: [:],
            booleans: [.ignoreEdgeProtect: ignore, .bottomUpOnLandscapeEnabled: true], selections: selections)
    }
    private func prepare(_ snapshot: BottomGesturePreferences.Snapshot? = nil) {
        coordinator?.cancelAll(); coordinator = nil; jobs = []; providerActions = []
        owner.reload(snapshot ?? configured())
        events = []; calls = []; selections = []
        raw = 1; size = CGSize(width: 400, height: 800); allowed = true
        sampleAvailable = true; alternateContainer = nil
        receiver.deck.recognizer.point = CGPoint(x: 10, y: 790)
        other.deck.recognizer.point = CGPoint(x: 390, y: 790)
    }
    private func bind(_ receiver: NativeReceiverFixture) {
        receiver.deck.container = UIView(frame: CGRect(origin: .zero, size: size))
        receiver.deck.recognizer = NativeRecognizerFixture()
        receiver.deck.container.addGestureRecognizer(receiver.deck.recognizer)
        window!.rootViewController!.view.addSubview(receiver.deck.container)
        receiver.original = { [unowned self] call in
            self.calls.append(call)
            guard let index = BottomGestureHooks.selectors.firstIndex(of: call.selector) else {
                self.require(false, "predecessor received foreign selector"); return
            }
            self.events.append("native.\(index)")
        }
    }
    private func invoke(_ phase: BottomGestureHooks.Phase, on target: NativeReceiverFixture? = nil,
                        tongue: AnyObject? = nil, gesture: AnyObject? = nil) {
        let target = target ?? receiver
        let selector = BottomGestureHooks.selectors[phase.rawValue]
        let method = class_getInstanceMethod(object_getClass(target)!, selector)!
        let call = unsafeBitCast(method_getImplementation(method), to: BottomGestureHooks.PullCall.self)
        call(target, selector, tongue ?? target.deck.object, 123.125, -456.875, gesture ?? target.deck.recognizer)
    }
    private func assertLast(_ phase: BottomGestureHooks.Phase, on target: NativeReceiverFixture? = nil) {
        let target = target ?? receiver
        guard let call = calls.last else { require(false, "missing full predecessor tuple"); return }
        require(call.receiver === target && call.selector == BottomGestureHooks.selectors[phase.rawValue] &&
            call.tongue === target.deck.object && call.gesture === target.deck.recognizer &&
            call.distance == 123.125 && call.velocity == -456.875, "full ABI carriers/receiver/selector changed")
    }
    private func drag(_ current: CGPoint) {
        invoke(.began)
        receiver.deck.recognizer.point = current
        invoke(.updated)
        invoke(.ended)
    }

    private func scriptedSample(_ target: AnyObject, _ tongue: AnyObject?, _ gesture: AnyObject?) -> BottomGestureSample? {
        sampleReads += 1
        guard sampleAvailable, let target = target as? NativeReceiverFixture,
              tongue === target.deck.object, gesture === target.deck.recognizer else { return nil }
        return BottomGestureSample(point: target.deck.recognizer.point,
            referenceRect: CGRect(origin: .zero, size: size), orientationRaw: raw, scene: scene,
            screen: UIScreen.main, referenceSpace: UIScreen.main.fixedCoordinateSpace,
            container: alternateContainer ?? target.deck.container,
            recognizer: target.deck.recognizer, deck: target.deck.object)
    }
    private func testForwarding() {
        checkpoint("full forwarding/order")
        prepare(configured(allOff: true))
        for phase in BottomGestureHooks.Phase.allCases { invoke(phase); assertLast(phase) }
        require(calls.count == 4 && selections.isEmpty && events == ["native.0", "native.1", "native.2", "native.3"],
                "disabled callbacks must all forward once")
        prepare()
        invoke(.began)
        require(calls.isEmpty && events == ["pending"], "admitted side only suppresses Began, cancels pending only")
        receiver.deck.recognizer.point.y = 700
        invoke(.updated); assertLast(.updated)
        invoke(.ended); assertLast(.ended)
        require(events == ["pending", "native.1", "trigger", "native.2"], "Ended trigger/native order")
        require(selections.map { $0.actions } == [[.lock]], "real core ordinary selection")
        invoke(.ended)
        require(selections.count == 1, "matching Ended submitted twice")
        invoke(.began)
        require(events.last == "pending", "Ended must release own session after forwarding")
        invoke(.canceled); assertLast(.canceled)
        invoke(.ended)
        require(selections.count == 1, "cancel must reset without dispatch")
        prepare()
        let selector = BottomGestureHooks.selectors[0]
        let imp = method_getImplementation(class_getInstanceMethod(object_getClass(receiver)!, selector)!)
        unsafeBitCast(imp, to: BottomGestureHooks.PullCall.self)(receiver, selector, nil, 2.5, -9.75, nil)
        require(calls.count == 1 && calls[0].tongue == nil && calls[0].gesture == nil &&
                calls[0].distance == 2.5 && calls[0].velocity == -9.75, "nil object carriers must fail open unchanged")
        prepare()
        let before = sampleReads
        let work = DispatchGroup()
        work.enter()
        DispatchQueue.global().async {
            for phase in BottomGestureHooks.Phase.allCases { self.invoke(phase) }
            work.leave()
        }
        require(work.wait(timeout: .now() + 5) == .success, "off-main forwarding blocked")
        require(sampleReads == before && selections.isEmpty && calls.count == 4, "off-main must only forward, no sample/UIKit")
        for (index, call) in calls.enumerated() {
            require(call.selector == BottomGestureHooks.selectors[index] && call.receiver === receiver &&
                    call.tongue === receiver.deck.object && call.gesture === receiver.deck.recognizer &&
                    call.distance == 123.125 && call.velocity == -456.875, "off-main full tuple")
        }
    }
    private func testOverlap() {
        checkpoint("identity/overlap/reentrant cleanup")
        prepare(); invoke(.began)
        invoke(.began, on: other); invoke(.updated, on: other)
        invoke(.canceled, on: other); invoke(.ended, on: other)
        receiver.deck.recognizer.point.y = 700; invoke(.ended)
        require(selections.count == 1 && selections[0].actions == [.lock], "foreign receiver cleared/dispatched active session")
        prepare(); invoke(.began)
        let foreign = NativeRecognizerFixture()
        invoke(.canceled, gesture: foreign); invoke(.ended, gesture: foreign)
        receiver.deck.recognizer.point.y = 700; invoke(.ended)
        require(selections.count == 1, "foreign gesture cleared active session")
        prepare(); invoke(.began)
        receiver.deck.recognizer.point.y = 700
        var reentered = false
        let original = receiver.original
        receiver.original = { [unowned self] call in
            original?(call)
            if call.selector == BottomGestureHooks.selectors[2], !reentered {
                reentered = true; self.invoke(.ended)
            }
        }
        invoke(.ended); receiver.original = original
        require(selections.count == 1 && calls.count == 2, "reentrant Ended must forward but never dispatch twice")
        prepare(); invoke(.began); receiver.deck.recognizer.point.y = 700
        receiver.original = { [unowned self] call in
            original?(call)
            if call.selector == BottomGestureHooks.selectors[2] { self.invoke(.began, on: self.other) }
        }
        invoke(.ended); receiver.original = original
        require(events == ["pending", "trigger", "native.2", "native.0"],
                "Ended must retain old ownership until native predecessor returns")
        invoke(.began, on: other)
        require(events.last == "pending", "Ended failed to reset after predecessor")
        prepare(); invoke(.began); receiver.deck.recognizer.point.y = 700
        receiver.original = { [unowned self] call in
            original?(call)
            if call.selector == BottomGestureHooks.selectors[3] { self.invoke(.ended) }
        }
        invoke(.canceled); receiver.original = original
        require(selections.isEmpty && calls.count == 2, "Canceled predecessor reentrancy must never authorize Ended")
        prepare(); invoke(.began)
        // Native Canceled may synchronously admit a replacement AFTER explicit
        // lifecycle reset. The old terminal must not erase that new identity.
        receiver.original = { [unowned self] call in
            original?(call)
            if call.selector == BottomGestureHooks.selectors[3] {
                self.owner.invalidate(); self.invoke(.began, on: self.other)
            }
        }
        invoke(.canceled); receiver.original = original
        other.deck.recognizer.point.y = 700; invoke(.ended, on: other)
        require(selections.count == 1 && selections[0].actions == [.playPause], "stale canceled cleanup erased new session")
    }
    private func testInvalidation() {
        checkpoint("lifecycle/frozen geometry/cache")
        for change in 0..<6 {
            prepare(); invoke(.began); receiver.deck.recognizer.point.y = 700
            switch change {
            case 0: owner.reload(configured())
            case 1: raw = 3
            case 2: size.width = 401
            case 3: allowed = false
            case 4: sampleAvailable = false
            default: alternateContainer = UIView()
            }
            invoke(.ended)
            require(selections.isEmpty && calls.count == 1 && events.contains("all"), "invalid context/reload/lock must cancel all and forward Ended")
        }
        prepare(); invoke(.began); owner.invalidate()
        receiver.deck.recognizer.point.y = 700; invoke(.ended)
        require(selections.isEmpty, "suspend/scene lifecycle invalidation did not clear session")
        prepare(); allowed = false; invoke(.began)
        require(calls.count == 1 && !events.contains("pending"), "locked/unknown cannot swallow native Began")
        prepare(.unavailable)
        let readsBeforeUnavailable = sampleReads
        invoke(.began)
        require(calls.count == 1 && sampleReads == readsBeforeUnavailable, "unavailable snapshot must fail open without sampling")
        prepare(); receiver.deck.recognizer.point.x = 120; invoke(.began)
        require(calls.count == 1, "strict left boundary equality swallowed")
        prepare(); receiver.deck.recognizer.point.x = 280; invoke(.began)
        require(calls.count == 1, "strict right boundary equality swallowed")
        prepare(); receiver.deck.recognizer.point.x = 200; invoke(.began)
        require(calls.count == 1, "middle swallowed")
        for (y, expected) in [(700.0, TapLockPreferences.Action.lock), (600, .flashlight), (400, .systemMute)] {
            prepare(); drag(CGPoint(x: 10, y: y))
            require(selections.map { $0.actions } == [[expected]], "three real geometry tiers")
        }
        prepare(configured(disabled: .bottomLeftUpExtra))
        drag(CGPoint(x: 10, y: 600))
        require(selections.isEmpty && calls.count == 2, "disabled selected tier fell back/swallowed updates")
        prepare(); drag(CGPoint(x: 10, y: 790))
        require(selections.isEmpty, "zero displacement dispatched")
    }
    private func testLandscape() {
        checkpoint("landscape unchanged referenceSize")
        for orientation in [3, 4] {
            prepare(); raw = orientation
            receiver.deck.recognizer.point = orientation == 3 ? CGPoint(x: 5, y: 10) : CGPoint(x: 395, y: 790)
            invoke(.began)
            receiver.deck.recognizer.point.x = orientation == 3 ? 55 : 345
            invoke(.ended)
            require(selections.map { $0.actions } == [[.lock]] && calls.count == 1,
                    "landscape must use unrotated 400x800 and orientation-specific displacement")
        }
    }
    private func testEdge() {
        checkpoint("optional edge preserved predecessor/narrow policy")
        let selector = NSSelectorFromString("_shouldProtectEdgeLocation:")
        typealias Edge = @convention(c) (AnyObject, Selector, Double) -> Bool
        let edge = unsafeBitCast(method_getImplementation(class_getInstanceMethod(object_getClass(receiver)!, selector)!), to: Edge.self)
        for (ignore, allOff, lock, location, expected) in [
            (true, false, false, 10.0, false), (false, false, false, 10, true),
            (true, true, false, 10, true), (true, false, true, 10, true),
            (true, false, false, 120, true), (true, false, false, 200, true),
            (true, false, false, 280, true), (true, false, false, 390, false)] {
            prepare(configured(ignore: ignore, allOff: allOff)); allowed = !lock
            receiver.protected = true; receiver.edgeCalls = []
            require(edge(receiver, selector, location) == expected, "edge narrow policy")
            require(receiver.edgeCalls.count == 1 && receiver.edgeCalls[0].0 === receiver &&
                receiver.edgeCalls[0].1 == selector && receiver.edgeCalls[0].2 == location,
                "edge must preserve full predecessor tuple exactly once")
        }
        prepare(); receiver.protected = false
        require(!edge(receiver, selector, 200), "false predecessor must remain false")
        receiver.protected = true
        for orientation in [3, 4] {
            prepare(); raw = orientation
            let atSide = orientation == 3 ? 10.0 : 790.0
            require(!edge(receiver, selector, atSide), "landscape edge axis/side")
        }
    }
    private func testCapabilityRejection() {
        checkpoint("exact ABI/whole-set fail-open")
        let valid = "v@:@dd@"
        let bad = ["B@:@dd@", "v@:@fd@", "v@:@dq@", "v@:@ddq", "v@:@dd@@", "v#:@dd@"]
        let noop: BottomGestureHooks.PullCall = { _, _, _, _, _, _ in }
        for encoding in bad + ["missing"] {
            serial += 1
            let name = "TLBottomRejectedABI\(serial)"
            let type = objc_allocateClassPair(NSObject.self, name, 0)!
            for index in 0..<4 where encoding != "missing" || index != 3 {
                let shape = index == 3 ? encoding : valid
                class_addMethod(type, BottomGestureHooks.selectors[index], unsafeBitCast(noop, to: IMP.self), shape)
            }
            objc_registerClassPair(type)
            require(NSClassFromString(name).map(ObjectIdentifier.init) == ObjectIdentifier(type), "unique ObjC fixture identity")
            let count = TLHookInstallCount()
            require(!BottomGestureHooks(session: owner).install(on: type), "mismatched callback ABI admitted")
            require(TLHookInstallCount() == count, "partially installed before final callback capability check")
        }
        let count = TLHookInstallCount()
        require(hooks.install(on: NativeReceiverFixture.self), "repeat hook install rejected")
        require(TLHookInstallCount() == count, "process owner installed duplicate hooks")
    }
    private func testSafeObjectSlots() {
        checkpoint("safe getters/object ivars/no KVC")
        require(BottomGestureSample.objectIvar(receiver.deck.object, "missing") == nil, "absent slot")
        require(BottomGestureSample.objectIvar(receiver.deck.object, "_tongueContainer") === receiver.deck.container, "exact container ivar")
        let type = objc_allocateClassPair(NSObject.self, "TLBottomObjectIvarFixture", 0)!
        require(class_addIvar(type, "_object", MemoryLayout<AnyObject>.size,
            UInt8(MemoryLayout<AnyObject>.alignment.trailingZeroBitCount), "@"), "object ivar fixture")
        require(class_addIvar(type, "_scalar", MemoryLayout<Int>.size,
            UInt8(MemoryLayout<Int>.alignment.trailingZeroBitCount), "q"), "scalar ivar fixture")
        objc_registerClassPair(type)
        let instance = class_createInstance(type, 0) as! NSObject
        let value = NSObject()
        object_setIvar(instance, class_getInstanceVariable(type, "_object")!, value)
        require(BottomGestureSample.objectIvar(instance, "_object") === value, "object ivar reader")
        require(BottomGestureSample.objectIvar(instance, "_scalar") == nil, "scalar ivar read as object")
        require(BottomGestureSample.capture(receiver, NSObject(), receiver.deck.recognizer) == nil, "foreign tongue")
        require(BottomGestureSample.capture(receiver, receiver.deck.object, NSObject()) == nil, "foreign coordinate recognizer")
        // Simulator versions can lack the private reference getter. In that case
        // install only that external capability fixture, not a rewritten reader.
        if class_getInstanceMethod(object_getClass(UIScreen.main)!, NSSelectorFromString("_referenceBounds")) == nil {
            let bounds: @convention(c) (AnyObject, Selector) -> CGRect = { _, _ in
                UIScreen.main.fixedCoordinateSpace.bounds
            }
            require(class_addMethod(object_getClass(UIScreen.main)!, NSSelectorFromString("_referenceBounds"),
                unsafeBitCast(bounds, to: IMP.self), "{CGRect={CGPoint=dd}{CGSize=dd}}@:"), "reference rectangle getter fixture")
        }
        let orientation = NativeOrientationFixture()
        orientation.raw = Int64(scene.interfaceOrientation.rawValue)
        let capabilities = BottomGestureSample.Capabilities(manager: NativeReceiverFixture.self,
            tongue: NativeDeckFixture.runtimeType, application: orientation)
        require(BottomGestureSample.captureValidated(receiver, NSObject(), receiver.deck.recognizer,
            capabilities: capabilities) == nil, "bound capture rejects foreign tongue identity")
        require(BottomGestureSample.captureValidated(receiver, receiver.deck.object, NSObject(),
            capabilities: capabilities) == nil, "bound capture rejects foreign recognizer identity")
        require(BottomGestureSample.captureValidated(receiver, receiver.deck.object, receiver.deck.recognizer,
            capabilities: .init(manager: NSString.self, tongue: NativeDeckFixture.runtimeType,
                application: orientation)) == nil, "bound capture rejects unrelated manager class")
        require(BottomGestureSample.captureValidated(receiver, receiver.deck.object, receiver.deck.recognizer,
            capabilities: .init(manager: NativeReceiverFixture.self, tongue: NSString.self,
                application: orientation)) == nil, "bound capture rejects unrelated tongue class")
        let sample = BottomGestureSample.captureValidated(receiver, receiver.deck.object, receiver.deck.recognizer,
            capabilities: capabilities)
        let expected = receiver.deck.container.convert(receiver.deck.recognizer.point, to: UIScreen.main.fixedCoordinateSpace)
        require(sample?.point == expected && sample?.scene === scene &&
            sample?.container === receiver.deck.container, "actual production coordinate chain/locationInView")
        require(sample?.referenceRect == BottomGestureSample.referenceRectangle(of: UIScreen.main), "actual unrotated reference rectangle")
        receiver.deck.container.transform = CGAffineTransform(translationX: 23, y: 17)
        let transformed = BottomGestureSample.captureValidated(receiver, receiver.deck.object, receiver.deck.recognizer,
            capabilities: capabilities)
        require(transformed?.point == receiver.deck.container.convert(receiver.deck.recognizer.point,
            to: UIScreen.main.fixedCoordinateSpace) && transformed?.point != sample?.point,
            "raw local coordinates must be converted through real UIKit transforms")
        receiver.deck.container.transform = .identity
        let referenceMethod = class_getInstanceMethod(object_getClass(UIScreen.main)!, NSSelectorFromString("_referenceBounds"))!
        let incompatible: @convention(c) (AnyObject, Selector) -> CGRect = { _, _ in
            CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let previousReference = method_setImplementation(referenceMethod, unsafeBitCast(incompatible, to: IMP.self))
        let incompatibleSample = BottomGestureSample.captureValidated(receiver, receiver.deck.object, receiver.deck.recognizer,
            capabilities: capabilities)
        method_setImplementation(referenceMethod, previousReference)
        require(incompatibleSample == nil, "incompatible fixed/reference rectangle must fail open")
        orientation.raw = orientation.raw == 1 ? 3 : 1
        require(BottomGestureSample.captureValidated(receiver, receiver.deck.object, receiver.deck.recognizer,
            capabilities: capabilities) == nil, "conflicting SpringBoard/scene orientation must reject")
    }
    private func testCoordinatorBridge() {
        checkpoint("hook/core/coordinator real integration")
        prepare(configured(flow: true))
        coordinator = BottomActionCoordinator(io: .init(now: { 0 },
            schedule: { [unowned self] _, job in self.jobs.append(job) },
            invoke: { [unowned self] action in self.providerActions.append(action) },
            permission: { _, _ in true }))
        drag(CGPoint(x: 10, y: 700))
        require(providerActions == [.playPause] && jobs.count == 1, "Hook to core to actual coordinator immediate flow")
        let pending = jobs; jobs = []
        pending.forEach { $0() }
        require(providerActions == [.playPause, .nextTrack], "Ended cleanup canceled newly submitted flow")
        receiver.deck.recognizer.point = CGPoint(x: 10, y: 790)
        drag(CGPoint(x: 10, y: 700))
        let stale = jobs; jobs = []
        receiver.deck.recognizer.point = CGPoint(x: 10, y: 790); invoke(.began)
        stale.forEach { $0() }
        require(providerActions == [.playPause, .nextTrack, .playPause], "new admitted Began did not cancel old delayed generation")
        owner.invalidate(); coordinator?.cancelAll(); coordinator = nil
    }
    private func run(_ scene: UIWindowScene, attempts: Int = 0) {
        guard scene.activationState == .foregroundActive && UIApplication.shared.applicationState == .active else {
            require(attempts < 100, "scene never activated")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.run(scene, attempts: attempts + 1) }
            return
        }
        self.scene = scene
        bind(receiver); bind(other)
        var expectedPredecessors: [Selector: IMP] = [:]
        for selector in BottomGestureHooks.selectors {
            let predecessor = unsafeBitCast(Self.exactPredecessor, to: IMP.self)
            method_setImplementation(class_getInstanceMethod(NativeReceiverFixture.self, selector)!, predecessor)
            expectedPredecessors[selector] = predecessor
        }
        let edgeSelector = NSSelectorFromString("_shouldProtectEdgeLocation:")
        let edgePredecessor = unsafeBitCast(Self.exactEdgePredecessor, to: IMP.self)
        method_setImplementation(class_getInstanceMethod(NativeReceiverFixture.self, edgeSelector)!, edgePredecessor)
        expectedPredecessors[edgeSelector] = edgePredecessor
        require(NSClassFromString("TLBottomNativeReceiverFixture").map(ObjectIdentifier.init) ==
            ObjectIdentifier(NativeReceiverFixture.self), "resolved fixture class identity")
        owner = BottomGestureSession(sample: { [unowned self] target, tongue, gesture in
            self.scriptedSample(target, tongue, gesture)
        }, edgeSample: { [unowned self] target in
            guard let target = target as? NativeReceiverFixture else { return nil }
            return self.scriptedSample(target, target.deck.object, target.deck.recognizer)
        }, unlocked: { [unowned self] in self.allowed },
        trigger: { [unowned self] selection, scene, permission in
            self.require(scene === self.scene && !permission, "scene/lock permission not preserved")
            self.events.append("trigger"); self.selections.append(selection)
            self.coordinator?.trigger(selection, in: scene, allowWhileLocked: permission)
        }, cancelPendingFlow: { [unowned self] in self.events.append("pending"); self.coordinator?.cancelPendingFlow() },
        cancelAll: { [unowned self] in self.events.append("all"); self.coordinator?.cancelAll() })
        hooks = BottomGestureHooks(session: owner)
        let before = TLHookInstallCount()
        // Invoke replacements before backend has written its out predecessor:
        // production must already have seeded all four slots.
        require(hooks.install(on: NativeReceiverFixture.self, installer: { [unowned self] type, selector, replacement, previous in
            self.require(previous.pointee != nil, "predecessor not seeded")
            self.require(unsafeBitCast(previous.pointee!, to: UnsafeRawPointer.self) ==
                unsafeBitCast(expectedPredecessors[selector]!, to: UnsafeRawPointer.self), "wrong predecessor identity seeded")
            if BottomGestureHooks.selectors.contains(selector) {
                unsafeBitCast(replacement, to: BottomGestureHooks.PullCall.self)(self.receiver, selector,
                    self.receiver.deck.object, 123.125, -456.875, self.receiver.deck.recognizer)
            }
            MSHookMessageEx(type, selector, replacement, previous)
        }), "actual production Hook installation")
        require(TLHookInstallCount() == before + 5 && calls.count == 4, "four complete callbacks + optional edge installed/seeded")
        for call in calls { require(call.receiver === receiver && call.distance == 123.125 && call.velocity == -456.875 &&
            call.tongue === receiver.deck.object && call.gesture === receiver.deck.recognizer, "installation-time seed forwarding tuple") }
        testCapabilityRejection(); testForwarding(); testOverlap(); testInvalidation()
        testLandscape(); testEdge(); testSafeObjectSlots(); testCoordinatorBridge()
        owner.invalidate()
        print("BOTTOM_GESTURE_NATIVE_PASS: assertions=\(checks)")
        print("Boundary: UIKit/ObjC backend fixtures; NOT handset injection, native competition, or lockscreen parity")
        fflush(stdout); exit(0)
    }
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "BottomNative", sessionRole: connectingSceneSession.role)
        config.delegateClass = BottomGestureNativeApp.self
        return config
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { require(false, "missing UIWindowScene"); return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController(); self.window = window
        window.makeKeyAndVisible()
        DispatchQueue.main.async { self.run(scene) }
    }
}
