import UIKit
import ObjectiveC
import CoreFoundation
import TapLockNativeRuntime

/// Exact arm64 callback carriers: self=x0, cmd=x1, tongue=x2, distance=d0,
/// velocity=d1, gesture=x3. The callback doubles are NEVER touch coordinates.
final class BottomGestureHooks {
    typealias PullCall = @convention(c) (AnyObject, Selector, AnyObject?, Double, Double, AnyObject?) -> Void
    typealias Installer = (AnyClass, Selector, IMP, UnsafeMutablePointer<IMP?>) -> Void
    enum Phase: Int, CaseIterable { case began, updated, ended, canceled }
    static let selectors = [
        "grabberTongueBeganPulling:withDistance:andVelocity:andGesture:",
        "grabberTongueUpdatedPulling:withDistance:andVelocity:andGesture:",
        "grabberTongueEndedPulling:withDistance:andVelocity:andGesture:",
        "grabberTongueCanceledPulling:withDistance:andVelocity:andGesture:"
    ].map(NSSelectorFromString)

    private static let registryLock = NSLock()
    private static var registry: [ObjectIdentifier: BottomGestureHooks] = [:]
    private let stateLock = NSLock()
    private var originals: [IMP?] = []
    private var edgeOriginal: IMP?
    private static let edgeSelector = NSSelectorFromString("_shouldProtectEdgeLocation:")
    private typealias EdgeCall = @convention(c) (AnyObject, Selector, Double) -> Bool
    private var started = false
    let session: BottomGestureSession

    init(session: BottomGestureSession) { self.session = session }

    /// No partial four-callback capability: validate the ENTIRE set before any
    /// mutation. Seed every predecessor before making a replacement reachable.
    @discardableResult
    func install(on type: AnyClass, installer: Installer = { type, selector, imp, old in
        MSHookMessageEx(type, selector, imp, old)
    }) -> Bool {
        #if BOTTOM_PANEL_DIAGNOSTIC
        BottomPanelDiagnostic.mark(.hookAttempt)
        #endif
        guard Thread.isMainThread else { return false }
        guard !started else { return true }
        let methods = Self.selectors.compactMap {
            PrivateAPI.checkedMethod(in: type, selector: $0,
                                     returns: "v", arguments: ["@", "d", "d", "@"])
        }
        guard methods.count == Self.selectors.count else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.hookRejected)
            #endif
            return false
        }
        let edgeMethod = PrivateAPI.checkedMethod(in: type, selector: Self.edgeSelector,
                                                 returns: "B", arguments: ["d"])
        Self.registryLock.lock()
        guard Self.registry[ObjectIdentifier(type)] == nil else {
            Self.registryLock.unlock()
            return false
        }
        originals = methods.map { method_getImplementation($0) }
        edgeOriginal = edgeMethod.map { method_getImplementation($0) }
        started = true
        Self.registry[ObjectIdentifier(type)] = self
        Self.registryLock.unlock()
        let replacements: [PullCall] = [Self.began, Self.updated, Self.ended, Self.canceled]
        for index in Self.selectors.indices {
            let seed = method_getImplementation(methods[index])
            var previous: IMP? = seed
            installer(type, Self.selectors[index], unsafeBitCast(replacements[index], to: IMP.self), &previous)
            stateLock.lock()
            originals[index] = previous ?? seed
            stateLock.unlock()
        }
        // Optional, separately proven one-double ABI. Never guess the two-arg
        // edge enum, and do not make the primary callbacks depend on this gate.
        if let method = edgeMethod {
            let seed = method_getImplementation(method)
            var previous: IMP? = seed
            installer(type, Self.edgeSelector, unsafeBitCast(Self.edge, to: IMP.self), &previous)
            stateLock.lock()
            edgeOriginal = previous ?? seed
            stateLock.unlock()
        }
        #if BOTTOM_PANEL_DIAGNOSTIC
        BottomPanelDiagnostic.mark(.hookInstalled)
        #endif
        return true
    }

    private static func owner(for receiver: AnyObject) -> BottomGestureHooks? {
        registryLock.lock()
        defer { registryLock.unlock() }
        var candidate: AnyClass? = object_getClass(receiver)
        while let type = candidate {
            if let owner = registry[ObjectIdentifier(type)] { return owner }
            candidate = class_getSuperclass(type)
        }
        return nil
    }

    private static func route(_ phase: Phase, _ receiver: AnyObject, _ selector: Selector,
                              _ tongue: AnyObject?, _ distance: Double, _ velocity: Double,
                              _ gesture: AnyObject?) {
        #if BOTTOM_PANEL_DIAGNOSTIC
        BottomPanelDiagnostic.callback(phase.rawValue)
        #endif
        guard let owner = owner(for: receiver) else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.callbackOwnerMissing)
            #endif
            return
        }
        owner.stateLock.lock()
        let original = owner.originals[phase.rawValue]
        owner.stateLock.unlock()
        guard let original = original else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.callbackOriginalMissing)
            #endif
            return
        }
        let previous = unsafeBitCast(original, to: PullCall.self)
        // This seam, including the off-main branch, is exercised through real
        // installed ObjC IMPs by BottomGestureNativeApp (not a Python model).
        let forward = { previous(receiver, selector, tongue, distance, velocity, gesture) }
        guard Thread.isMainThread else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.callbackOffMain)
            #endif
            forward(); return
        }
        owner.session.receive(phase, receiver: receiver, tongue: tongue, gesture: gesture, forward: forward)
    }

    private static let began: PullCall = { route(.began, $0, $1, $2, $3, $4, $5) }
    private static let updated: PullCall = { route(.updated, $0, $1, $2, $3, $4, $5) }
    private static let ended: PullCall = { route(.ended, $0, $1, $2, $3, $4, $5) }
    private static let canceled: PullCall = { route(.canceled, $0, $1, $2, $3, $4, $5) }

    private static let edge: EdgeCall = { receiver, selector, location in
        guard let owner = owner(for: receiver) else { return true }
        owner.stateLock.lock()
        let original = owner.edgeOriginal
        owner.stateLock.unlock()
        guard let original = original else { return true }
        let previous = unsafeBitCast(original, to: EdgeCall.self)
        let protected = previous(receiver, selector, location)
        guard Thread.isMainThread, protected else { return protected }
        return owner.session.shouldRelaxEdge(location, receiver: receiver) ? false : protected
    }
}

private let bottomPreferencesChanged: CFNotificationCallback = { _, _, _, _, _ in
    DispatchQueue.main.async { BottomGestureRuntime.reloadPreferences() }
}
private let bottomLockChanged: CFNotificationCallback = { _, _, _, _, _ in
    DispatchQueue.main.async {
        #if BOTTOM_PANEL_DIAGNOSTIC
        BottomPanelDiagnostic.mark(.lockNotification)
        #endif
        BottomGestureRuntime.invalidate()
    }
}

/// Process-lifetime owner; parent adds the single activation call to old startup.
enum BottomGestureRuntime {
    private static var started = false
    private static var observers: [NSObjectProtocol] = []
    private static let owner = BottomGestureSession(
        sample: BottomGestureSample.capture,
        edgeSample: BottomGestureSample.captureEdge,
        unlocked: { LockAction.unlockedManager() != nil },
        trigger: { BottomActionCoordinator.shared.trigger($0, in: $1, allowWhileLocked: $2) },
        cancelPendingFlow: { BottomActionCoordinator.shared.cancelPendingFlow() },
        cancelAll: { BottomActionCoordinator.shared.cancelAll() })
    private static let hooks = BottomGestureHooks(session: owner)

    static func activate() {
        guard Thread.isMainThread, !started else { return }
        started = true
        #if BOTTOM_PANEL_DIAGNOSTIC
        BottomPanelDiagnostic.mark(.activated)
        #endif
        reloadPreferences()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil,
            bottomPreferencesChanged, TapLockPreferences.changedNotification as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil,
            bottomLockChanged, "com.apple.springboard.lockstate" as CFString, nil, .deliverImmediately)
        let center = NotificationCenter.default
        for name in [UIApplication.didFinishLaunchingNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                reloadPreferences()
            })
        }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                     UIDevice.orientationDidChangeNotification,
                     UIApplication.didChangeStatusBarOrientationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                #if BOTTOM_PANEL_DIAGNOSTIC
                if name == UIDevice.orientationDidChangeNotification {
                    BottomPanelDiagnostic.mark(.systemOrientationChanged)
                } else { BottomPanelDiagnostic.mark(.applicationLifecycleObserved) }
                #endif
                invalidate()
            })
        }
        for name in [UIScene.willDeactivateNotification, UIScene.didDisconnectNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let scene = note.object as? UIWindowScene else { return }
                #if BOTTOM_PANEL_DIAGNOSTIC
                BottomPanelDiagnostic.mark(.sceneLifecycleObserved)
                #endif
                owner.invalidate(in: scene)
            })
        }
        if let type = NSClassFromString("SBFluidSwitcherGestureManager") { hooks.install(on: type) }
        else {
            #if BOTTOM_PANEL_DIAGNOSTIC
            BottomPanelDiagnostic.mark(.managerMissing)
            #endif
        }
    }

    fileprivate static func reloadPreferences() {
        guard Thread.isMainThread else { return }
        #if BOTTOM_PANEL_DIAGNOSTIC
        BottomPanelDiagnostic.mark(.preferenceReload)
        #endif
        let snapshot = BottomGesturePreferences.readSnapshot()
        #if BOTTOM_PANEL_DIAGNOSTIC
        var enabled = 0, actions = 0, flow = 0
        for (index, id) in BottomGesturePreferences.GestureID.allCases.enumerated() {
            let selection = snapshot.selection(id)
            if selection.enabled { enabled |= 1 << index }
            if !selection.actions.isEmpty { actions |= 1 << index }
            if selection.flowEnabled { flow |= 1 << index }
        }
        BottomPanelDiagnostic.preferences(available: snapshot.available, enabled: enabled, actions: actions, flow: flow)
        #endif
        owner.reload(snapshot)
    }

    fileprivate static func invalidate() {
        guard Thread.isMainThread else { return }
        owner.invalidate()
    }
}
