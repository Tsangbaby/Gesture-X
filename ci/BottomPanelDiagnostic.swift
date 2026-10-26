import Foundation
// Only this build flag enables storage. Normal builds retain no diagnostic state.
// The build script supplies exact-SHA metadata; no runtime/App identity is read.
#if BOTTOM_PANEL_DIAGNOSTIC
import Darwin
#endif

enum BottomPanelDiagnostic {
    enum Event: String, CaseIterable {
        case hookAttempt, hookRejected, hookInstalled, callbackOwnerMissing, callbackOriginalMissing
        case callbackOffMain, lockNotification, activated, systemOrientationChanged, applicationLifecycleObserved
        case sceneLifecycleObserved, managerMissing, preferenceReload, sampleOffMain, sampleApplicationInactive
        case sampleReceiverUnavailable, sampleReceiverWrongType, sampleDeckUnavailable, sampleDeckMismatch, sampleDeckWrongType
        case sampleRecognizerUnavailable, sampleRecognizerMismatch, sampleRecognizerDetached, sampleContainerDetached, sampleWrongScreen
        case sampleSceneUnavailable, sampleSceneInactive, sampleSceneWrongScreen, sampleReferenceUnavailable, sampleOrientationUnavailable
        case sampleOrientationMismatch, sampleReferenceMismatch, sampleRawNonfinite, sampleConvertedNonfinite, contextTongueChanged
        case contextSceneChanged, contextContainerChanged, contextRecognizerChanged, contextDeckChanged, contextScreenChanged
        case contextReferenceChanged, contextRectangleChanged, contextOrientationChanged, contextSizeChanged, sessionInvalidated
        case classificationBoundsRejected, classificationOutsideSide, classificationNonfinite, classificationBelowMinimum, classificationAboveMaximum
        case classificationOrdinary, classificationExtra, classificationExtraPlus, classificationDisabledTier, classificationEmptyActions
        case classificationInvalidActions, beganAlreadyOwned, beganGestureUnavailable, beganTongueUnavailable, beganPreferencesUnavailable
        case beganLockedOrUnknown, beganSampleUnavailable, beganBoundsUnavailable, beganOutsideSide, beganSideDisabled
        case beganAdmitted, updateLocked, updateContextRejected, updateSampleRejected, endedLocked
        case endedSampleRejected, endedContextRejected, actionSubmitted, endedClassificationRejected, endedWithoutOwner
        case coordinatorOffMain, coordinatorEntered, coordinatorSelectionRejected, coordinatorFlow, panelToggledClosed
        case coordinatorCanceled, coordinatorWrongScreen, coordinatorSceneInactive, coordinatorApplicationInactive, coordinatorVoiceOver
        case coordinatorOrientationUnknown, coordinatorOrientationChanged, coordinatorPermissionDenied, panelCreated, panelNotHidden
        case panelSceneAttached, panelViewAttached, panelBoundsEmpty, panelDeferredReleased, panelDeferredHidden
        case panelDeferredNotHidden, panelDeferredSceneDetached, panelDeferredViewDetached, panelReleased, panelGeometryChanged
        case callbackBegan, callbackUpdated, callbackEnded, callbackCanceled
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
        #if BOTTOM_PANEL_DIAGNOSTIC
        lock.lock()
        counts[event] = min((counts[event] ?? 0) + 1, 65535)
        if admissionDepth > 0, firstRejection == nil,
           event.rawValue.hasPrefix("sample") || event.rawValue.hasPrefix("began"),
           event != .beganAdmitted {
            firstRejection = event
        }
        if failures.contains(event), gestureNumber > 0, gestureFirstFailure == nil { gestureFirstFailure = event }
        if event != .callbackUpdated {
            trace.append("\(serial + 1):\(gestureNumber):" + event.rawValue)
            if trace.count > maximumTrace {
                trace.removeFirst(trace.count - maximumTrace)
                traceDropped = min(traceDropped + 1, 1_000_000_000)
            }
        }
        changedLocked()
        lock.unlock()
        #endif
    }

    static func callback(_ phase: Int) {
        #if BOTTOM_PANEL_DIAGNOSTIC
        if phase == 0 {
            lock.lock(); gestureNumber = min(gestureNumber + 1, 65535); gestureFirstFailure = nil; lock.unlock()
        }
        #endif
        switch phase {
        case 0: mark(.callbackBegan)
        case 1: mark(.callbackUpdated)
        case 2: mark(.callbackEnded)
        case 3: mark(.callbackCanceled)
        default: break
        }
    }

    static func admission(_ entering: Bool) {
        #if BOTTOM_PANEL_DIAGNOSTIC
        lock.lock()
        admissionDepth = entering ? admissionDepth + 1 : max(0, admissionDepth - 1)
        lock.unlock()
        #endif
    }

    static func preferences(available: Bool, enabled: Int, actions: Int, flow: Int) {
        #if BOTTOM_PANEL_DIAGNOSTIC
        lock.lock()
        preferencesAvailable = available
        enabledMask = enabled & 63; actionsMask = actions & 63; flowMask = flow & 63
        preferenceRevision = min(preferenceRevision + 1, 65535)
        firstRejection = nil
        changedLocked()
        lock.unlock()
        #endif
    }

    #if BOTTOM_PANEL_DIAGNOSTIC
    private static let maximumBytes = 32768
    private static let maximumTrace = 96
    private static let failures: Set<Event> = [
        .sampleOffMain, .sampleApplicationInactive, .sampleReceiverUnavailable, .sampleReceiverWrongType, .sampleDeckUnavailable,
        .sampleDeckMismatch, .sampleDeckWrongType, .sampleRecognizerUnavailable, .sampleRecognizerMismatch, .sampleRecognizerDetached,
        .sampleContainerDetached, .sampleWrongScreen, .sampleSceneUnavailable, .sampleSceneInactive, .sampleSceneWrongScreen,
        .sampleReferenceUnavailable, .sampleOrientationUnavailable, .sampleOrientationMismatch, .sampleReferenceMismatch, .sampleRawNonfinite,
        .sampleConvertedNonfinite, .contextTongueChanged, .contextSceneChanged, .contextContainerChanged, .contextRecognizerChanged,
        .contextDeckChanged, .contextScreenChanged, .contextReferenceChanged, .contextRectangleChanged, .contextOrientationChanged,
        .contextSizeChanged, .classificationBoundsRejected, .classificationOutsideSide, .classificationNonfinite, .classificationBelowMinimum,
        .classificationAboveMaximum, .classificationDisabledTier, .classificationEmptyActions, .classificationInvalidActions, .beganAlreadyOwned,
        .beganGestureUnavailable, .beganTongueUnavailable, .beganPreferencesUnavailable, .beganLockedOrUnknown, .beganSampleUnavailable,
        .beganBoundsUnavailable, .beganOutsideSide, .beganSideDisabled, .updateLocked, .updateContextRejected,
        .updateSampleRejected, .endedLocked, .endedSampleRejected, .endedContextRejected, .endedClassificationRejected,
        .endedWithoutOwner, .coordinatorOffMain, .coordinatorSelectionRejected, .coordinatorWrongScreen, .coordinatorSceneInactive,
        .coordinatorApplicationInactive, .coordinatorVoiceOver, .coordinatorOrientationUnknown, .coordinatorOrientationChanged, .coordinatorPermissionDenied,
        .panelBoundsEmpty, .panelDeferredReleased, .panelDeferredHidden, .panelDeferredSceneDetached, .panelDeferredViewDetached,
        .panelGeometryChanged,
    ]
    private static var gestureNumber = 0, traceDropped = 0
    private static var gestureFirstFailure: Event?
    private static var trace: [String] = []
    private static let maximumFlushes = 256
    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "com.tsangbaby.taplock.bottom-diag2", qos: .utility)
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
        let gestureNumber: Int, traceDropped: Int
        let gestureFirstFailure: Event?
        let trace: [String]
    }

    private static func snapshotLocked() -> Snapshot {
        Snapshot(serial: serial, flushes: flushes, preferenceRevision: preferenceRevision,
                 preferencesAvailable: preferencesAvailable, enabledMask: enabledMask,
                 actionsMask: actionsMask, flowMask: flowMask, firstRejection: firstRejection, counts: counts,
                 gestureNumber: gestureNumber, traceDropped: traceDropped, gestureFirstFailure: gestureFirstFailure, trace: trace)
    }

    // Formatting/public OS metadata are outside the short counter lock.
    private static func report(_ snapshot: Snapshot) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var lines = ["schema=2", "mode=diagnostic_only", "revision=bottomdiag2",
                     "package_version=0.1.13+bottomfix1.diag1", "source_sha=" + BottomDiagnosticBuild.sourceSHA,
                     "observation_base=b606238d93bb71e7caf1c219767aefaad63a0bb7",
                     "os_version=\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                     "sequence=\(snapshot.serial)", "writes=\(snapshot.flushes)", "write_limit=\(maximumFlushes)",
                     "preferences_revision=\(snapshot.preferenceRevision)",
                     "preferences_available=\(snapshot.preferencesAvailable ? 1 : 0)",
                     "enabled_mask=\(snapshot.enabledMask)", "actions_present_mask=\(snapshot.actionsMask)", "flow_mask=\(snapshot.flowMask)",
                     "first_rejection_since_preferences_reload=" + (snapshot.firstRejection?.rawValue ?? "none")]
        lines += ["gesture_number=\(snapshot.gestureNumber)",
                  "first_failure_current_gesture=" + (snapshot.gestureFirstFailure?.rawValue ?? "none"),
                  "trace_count=\(snapshot.trace.count)", "trace_dropped=\(snapshot.traceDropped)",
                  "trace_scope=last_96_events_except_callbackUpdated;sequence:gesture:event"]
        for (index, entry) in snapshot.trace.enumerated() { lines.append("trace.\(index)=" + entry) }
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
        if mkdirat(parentFD, "TapLockBottomDiag2", mode_t(0o700)) != 0 && errno != EEXIST { return false }
        let directoryFD = openat(parentFD, "TapLockBottomDiag2", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
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
