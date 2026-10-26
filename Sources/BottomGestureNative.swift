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
        BottomGestureDiagnostic.mark(.hookAttempt)
        guard Thread.isMainThread else { return false }
        guard !started else { return true }
        let methods = Self.selectors.compactMap {
            PrivateAPI.checkedMethod(in: type, selector: $0,
                                     returns: "v", arguments: ["@", "d", "d", "@"])
        }
        guard methods.count == Self.selectors.count else {
            BottomGestureDiagnostic.mark(.hookRejected)
            return false
        }
        let edgeMethod = PrivateAPI.checkedMethod(in: type, selector: Self.edgeSelector,
                                                 returns: "B", arguments: ["d"])
        Self.registryLock.lock()
        guard Self.registry[ObjectIdentifier(type)] == nil else {
            Self.registryLock.unlock()
            BottomGestureDiagnostic.mark(.hookRejected)
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
        BottomGestureDiagnostic.mark(.hookInstalled)
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
        BottomGestureDiagnostic.callback(phase.rawValue)
        guard let owner = owner(for: receiver) else {
            BottomGestureDiagnostic.mark(.callbackOwnerMissing)
            return
        }
        owner.stateLock.lock()
        let original = owner.originals[phase.rawValue]
        owner.stateLock.unlock()
        guard let original = original else {
            BottomGestureDiagnostic.mark(.callbackOriginalMissing)
            return
        }
        let previous = unsafeBitCast(original, to: PullCall.self)
        // This seam, including the off-main branch, is exercised through real
        // installed ObjC IMPs by BottomGestureNativeApp (not a Python model).
        let forward = { previous(receiver, selector, tongue, distance, velocity, gesture) }
        guard Thread.isMainThread else {
            BottomGestureDiagnostic.mark(.callbackOffMain)
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
    DispatchQueue.main.async { BottomGestureRuntime.invalidate() }
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
        BottomGestureDiagnostic.mark(.activated)
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
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in invalidate() })
        }
        for name in [UIScene.willDeactivateNotification, UIScene.didDisconnectNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let scene = note.object as? UIWindowScene else { return }
                owner.invalidate(in: scene)
            })
        }
        if let type = NSClassFromString("SBFluidSwitcherGestureManager") { hooks.install(on: type) }
        else { BottomGestureDiagnostic.mark(.managerMissing) }
    }

    fileprivate static func reloadPreferences() {
        guard Thread.isMainThread else { return }
        let snapshot = BottomGesturePreferences.readSnapshot()
        owner.reload(snapshot)
        #if BOTTOM_GESTURE_DIAGNOSTIC
        var enabled = 0, actions = 0, flow = 0
        for (index, id) in BottomGesturePreferences.GestureID.allCases.enumerated() {
            let selection = snapshot.selection(id)
            if selection.enabled { enabled |= 1 << index }
            if !selection.actions.isEmpty { actions |= 1 << index }
            if selection.flowEnabled { flow |= 1 << index }
        }
        BottomGestureDiagnostic.preferences(available: snapshot.available, enabled: enabled, actions: actions, flow: flow)
        #endif
    }

    fileprivate static func invalidate() {
        guard Thread.isMainThread else { return }
        owner.invalidate()
    }
}

// BOTTOM_DIAGNOSTIC_COLLECTOR_BEGIN
// Only this build flag enables storage. Normal builds retain no diagnostic state.
// The build script supplies exact-SHA metadata; no runtime/App identity is read.
#if BOTTOM_GESTURE_DIAGNOSTIC
import Darwin
#endif

enum BottomGestureDiagnostic {
    enum Event: String, CaseIterable {
        case activated, managerMissing, hookAttempt, hookRejected, hookInstalled
        case callbackBegan, callbackUpdated, callbackEnded, callbackCanceled, callbackOffMain
        case callbackOwnerMissing, callbackOriginalMissing
        case sampleOffMain, sampleApplicationInactive, sampleReceiverUnavailable, sampleReceiverWrongType
        case sampleDeckUnavailable, sampleDeckMismatch, sampleDeckWrongType
        case sampleContainerUnavailable, sampleRecognizerUnavailable, sampleRecognizerMismatch
        case sampleRecognizerDetached, sampleContainerDetached, sampleWrongScreen
        case sampleSceneUnavailable, sampleSceneInactive, sampleSceneWrongScreen
        case sampleReferenceUnavailable, sampleOrientationUnavailable, sampleOrientationMismatch
        case sampleReferenceMismatch, sampleNonfinitePoint, sampleCapabilitiesUnavailable
        case beganAlreadyOwned, beganGestureUnavailable, beganTongueUnavailable
        case beganPreferencesUnavailable, beganLockedOrUnknown, beganSampleUnavailable
        case beganBoundsUnavailable, beganOutsideSide, beganSideDisabled, beganAdmitted
        case sessionInvalidated, endedWithoutOwner, endedClassificationRejected, actionSubmitted
    }

    @inline(__always)
    static func check(_ condition: Bool, _ reason: Event) -> Bool {
        if !condition { mark(reason) }
        return condition
    }

    @inline(__always)
    static func value<T>(_ candidate: T?, _ reason: Event) -> T? {
        if candidate == nil { mark(reason) }
        return candidate
    }

    static func mark(_ event: Event) {
        #if BOTTOM_GESTURE_DIAGNOSTIC
        lock.lock()
        counts[event] = min((counts[event] ?? 0) + 1, 65535)
        if admissionDepth > 0, firstRejection == nil,
           event.rawValue.hasPrefix("sample") || event.rawValue.hasPrefix("began"),
           event != .beganAdmitted {
            firstRejection = event
        }
        changedLocked()
        lock.unlock()
        #endif
    }

    static func callback(_ phase: Int) {
        switch phase {
        case 0: mark(.callbackBegan)
        case 1: mark(.callbackUpdated)
        case 2: mark(.callbackEnded)
        case 3: mark(.callbackCanceled)
        default: break
        }
    }

    static func admission(_ entering: Bool) {
        #if BOTTOM_GESTURE_DIAGNOSTIC
        lock.lock()
        admissionDepth = entering ? admissionDepth + 1 : max(0, admissionDepth - 1)
        lock.unlock()
        #endif
    }

    static func preferences(available: Bool, enabled: Int, actions: Int, flow: Int) {
        #if BOTTOM_GESTURE_DIAGNOSTIC
        lock.lock()
        preferencesAvailable = available
        enabledMask = enabled & 63; actionsMask = actions & 63; flowMask = flow & 63
        preferenceRevision = min(preferenceRevision + 1, 65535)
        firstRejection = nil
        changedLocked()
        lock.unlock()
        #endif
    }

    #if BOTTOM_GESTURE_DIAGNOSTIC
    private static let maximumBytes = 32768
    private static let maximumFlushes = 256
    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "com.tsangbaby.taplock.bottom-diag1", qos: .utility)
    private static var counts: [Event: Int] = [:]
    private static var pending = false // Includes the executing write; at most one writer is admitted.
    private static var serial = 0
    private static var flushes = 0
    private static var admissionDepth = 0
    private static var firstRejection: Event?
    private static var preferencesAvailable = false
    private static var enabledMask = 0, actionsMask = 0, flowMask = 0, preferenceRevision = 0

    // Call only with lock held. No filesystem or private/UIKit reads on this path.
    private static func changedLocked() {
        serial = min(serial + 1, 1_000_000_000)
        guard !pending, flushes < maximumFlushes else { return }
        pending = true
        queue.asyncAfter(deadline: .now() + 0.5) { flush() }
    }

    private struct Snapshot {
        let serial: Int, flushes: Int, preferenceRevision: Int
        let preferencesAvailable: Bool
        let enabledMask: Int, actionsMask: Int, flowMask: Int
        let firstRejection: Event?
        let counts: [Event: Int]
    }

    private static func snapshotLocked() -> Snapshot {
        Snapshot(serial: serial, flushes: flushes, preferenceRevision: preferenceRevision,
                 preferencesAvailable: preferencesAvailable, enabledMask: enabledMask,
                 actionsMask: actionsMask, flowMask: flowMask, firstRejection: firstRejection, counts: counts)
    }

    // Formatting/public OS metadata are outside the short counter lock.
    private static func report(_ snapshot: Snapshot) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var lines = ["schema=1", "mode=diagnostic_only", "revision=bottomdiag1",
                     "package_version=0.1.13+bottomdiag1", "source_sha=" + BottomDiagnosticBuild.sourceSHA,
                     "observation_base=08bdc7823db6d68ef7a438234439364569c1265c",
                     "os_version=\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                     "sequence=\(snapshot.serial)", "writes=\(snapshot.flushes)", "write_limit=\(maximumFlushes)",
                     "preferences_revision=\(snapshot.preferenceRevision)",
                     "preferences_available=\(snapshot.preferencesAvailable ? 1 : 0)",
                     "enabled_mask=\(snapshot.enabledMask)", "actions_present_mask=\(snapshot.actionsMask)", "flow_mask=\(snapshot.flowMask)",
                     "first_rejection_since_preferences_reload=" + (snapshot.firstRejection?.rawValue ?? "none")]
        for event in Event.allCases { lines.append(event.rawValue + "=\(snapshot.counts[event] ?? 0)") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func flush() {
        lock.lock()
        flushes += 1
        let observed = serial
        let snapshot = snapshotLocked()
        lock.unlock()
        let bytes = Array(report(snapshot).utf8)
        _ = persist(bytes, parent: BottomDiagnosticBuild.parentDirectory)
        lock.lock()
        pending = false
        // Re-arm only when events arrived during this write. No polling/timer loop.
        if observed != serial { changedLocked() }
        lock.unlock()
    }

    /// Direct final-fd snapshots: an interrupted write may be incomplete, never
    /// append to stale bytes. No pathname rename or truncation before fd validation.
    private static func persist(_ bytes: [UInt8], parent: String) -> Bool {
        guard !bytes.isEmpty, bytes.count <= maximumBytes else { return false }
        let parentFD = open(parent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
        guard parentFD >= 0 else { return false }
        defer { close(parentFD) }
        var parentStat = stat()
        guard fstat(parentFD, &parentStat) == 0,
              parentStat.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              parentStat.st_uid == geteuid() else { return false }
        if mkdirat(parentFD, "TapLockBottomDiag1", mode_t(0o700)) != 0 && errno != EEXIST { return false }
        let directoryFD = openat(parentFD, "TapLockBottomDiag1", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
        guard directoryFD >= 0 else { return false }
        defer { close(directoryFD) }
        var directoryStat = stat()
        guard fstat(directoryFD, &directoryStat) == 0,
              directoryStat.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              directoryStat.st_uid == geteuid(), fchmod(directoryFD, mode_t(0o700)) == 0,
              fstat(directoryFD, &directoryStat) == 0,
              directoryStat.st_mode & mode_t(0o777) == mode_t(0o700) else { return false }
        var fd = openat(directoryFD, "report.txt", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK, mode_t(0o600))
        if fd < 0 && errno == EEXIST {
            fd = openat(directoryFD, "report.txt", O_WRONLY | O_NOFOLLOW | O_NONBLOCK)
        }
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var fileStat = stat()
        guard fstat(fd, &fileStat) == 0,
              fileStat.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              fileStat.st_uid == geteuid(), fileStat.st_nlink == 1,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else { return false }
        defer { flock(fd, LOCK_UN) }
        guard fchmod(fd, mode_t(0o600)) == 0, fstat(fd, &fileStat) == 0,
              fileStat.st_mode & mode_t(0o777) == mode_t(0o600) else { return false }
        #if os(iOS)
        // Darwin F_SETPROTECTIONCLASS/F_GETPROTECTIONCLASS, kernel class C (3).
        // Bind protection and its readback to the same validated file descriptor.
        guard fcntl(fd, F_SETPROTECTIONCLASS, 3) == 0,
              fcntl(fd, F_GETPROTECTIONCLASS) == 3 else { return false }
        #endif
        var reset: Int32
        repeat { reset = ftruncate(fd, 0) } while reset != 0 && errno == EINTR
        guard reset == 0 else { return false }
        var offset = 0
        let success = bytes.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            while offset < bytes.count {
                let count = write(fd, base.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { _ = ftruncate(fd, 0); return false }
                offset += count
            }
            return true
        }
        return success
    }

    #if BOTTOM_DIAGNOSTIC_TESTS
    static func reportForTesting() -> String {
        lock.lock(); let snapshot = snapshotLocked(); lock.unlock()
        return report(snapshot)
    }
    static func persistForTesting(_ bytes: [UInt8], parent: String) -> Bool { persist(bytes, parent: parent) }
    #endif
    #endif
}
// BOTTOM_DIAGNOSTIC_COLLECTOR_END
