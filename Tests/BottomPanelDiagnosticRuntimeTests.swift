import Foundation
import Darwin

@main
struct BottomPanelDiagnosticRuntimeTests {
    static var checks = 0
    static func require(_ condition: @autoclosure () throws -> Bool, _ label: String) {
        checks += 1
        if (try? condition()) != true { fputs("BOTTOM_DIAGNOSTIC_RUNTIME_FAIL: " + label + "\n", stderr); exit(1) }
    }
    static func record() -> [String: String] {
        #if BOTTOM_PANEL_DIAGNOSTIC
        return Dictionary(uniqueKeysWithValues: BottomPanelDiagnostic.reportForTesting().split(separator: "\n").map {
            let parts = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(parts[0]), String(parts[1]))
        })
        #else
        return [:]
        #endif
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let fm = FileManager.default
        var evaluated = 0
        func condition() -> Bool { evaluated += 1; return false }
        require(!BottomPanelDiagnostic.check(condition(), .beganLockedOrUnknown), "predicate result")
        require(evaluated == 1, "predicate evaluated exactly once")
        let absent: NSObject? = nil
        require(BottomPanelDiagnostic.value(absent, .beganGestureUnavailable) == nil, "optional nil result")
        let object = NSObject()
        require(BottomPanelDiagnostic.value(object, .beganGestureUnavailable) === object, "optional identity")
        #if BOTTOM_PANEL_DIAGNOSTIC
        BottomPanelDiagnostic.mark(.activated)
        BottomPanelDiagnostic.preferences(available: true, enabled: 1, actions: 1, flow: 0)
        BottomPanelDiagnostic.admission(true)
        require(!BottomPanelDiagnostic.check(false, .sampleSceneUnavailable), "rejection result")
        _ = BottomPanelDiagnostic.value(absent, .beganSampleUnavailable)
        BottomPanelDiagnostic.admission(false)
        var fields = record()
        require(fields["first_rejection_since_preferences_reload"] == "sampleSceneUnavailable", "first inner rejection retained")
        require(fields["source_sha"] == BottomDiagnosticBuild.sourceSHA, "exact generated identity")
        require(fields["enabled_mask"] == "1" && fields["actions_present_mask"] == "1", "preferences masks")
        for phase in 0...3 { BottomPanelDiagnostic.callback(phase) }
        for name in ["callbackBegan", "callbackUpdated", "callbackEnded", "callbackCanceled"] {
            require(record()[name] == "1", "four callback carriers")
        }
        DispatchQueue.concurrentPerform(iterations: 70000) { _ in BottomPanelDiagnostic.mark(.callbackUpdated) }
        require(record()["callbackUpdated"] == "65535", "counter saturation and concurrent admission")
        BottomPanelDiagnostic.preferences(available: false, enabled: 127, actions: 127, flow: 127)
        require(record()["first_rejection_since_preferences_reload"] == "none", "preference-revision reset")
        require(record()["enabled_mask"] == "63", "closed six-bit masks")
        BottomPanelDiagnostic.callback(0)
        require(record()["first_failure_current_gesture"] == "none", "new gesture resets its first failure")
        BottomPanelDiagnostic.mark(.classificationExtra)
        BottomPanelDiagnostic.mark(.classificationDisabledTier)
        BottomPanelDiagnostic.mark(.coordinatorPermissionDenied)
        require(record()["first_failure_current_gesture"] == "classificationDisabledTier", "first failure per gesture is stable")
        for _ in 0..<200 { BottomPanelDiagnostic.mark(.panelCreated) }
        require(record()["trace_count"] == "96", "trace bounded independent of callback rate")
        require(Int(record()["trace_dropped"] ?? "0")! > 0, "trace rollover disclosed")
        require(record()["schema"] == "2", "schema revision")
        require(record()["observation_base"] == "b606238d93bb71e7caf1c219767aefaad63a0bb7", "failed functional observation base")
        for event in BottomPanelDiagnostic.Event.allCases {
            require(record()[event.rawValue] != nil, "every fixed event emitted")
        }
        let bytes = Array(BottomPanelDiagnostic.reportForTesting().utf8)
        require(bytes.count < 32768, "reachable report bound")
        let normal = root.appendingPathComponent("normal")
        try fm.createDirectory(at: normal, withIntermediateDirectories: false)
        require(BottomPanelDiagnostic.persistForTesting(bytes, parent: normal.path), "real production sink write")
        let directory = normal.appendingPathComponent("TapLockBottomDiag2")
        let file = directory.appendingPathComponent("report.txt")
        require(try Data(contentsOf: file) == Data(bytes), "fd-bound snapshot bytes")
        var statBuffer = stat()
        require(stat(file.path, &statBuffer) == 0 && statBuffer.st_mode & 0o777 == 0o600, "file mode")
        require(stat(directory.path, &statBuffer) == 0 && statBuffer.st_mode & 0o777 == 0o700, "directory mode")
        require(!BottomPanelDiagnostic.persistForTesting(Array(repeating: 65, count: 32769), parent: normal.path), "oversized rejected before mutation")
        require(try Data(contentsOf: file) == Data(bytes), "oversized preserves previous snapshot")
        require(BottomPanelDiagnostic.persistForTesting(Array("fresh\n".utf8), parent: normal.path), "shorter snapshot reset")
        require(try String(contentsOf: file, encoding: .utf8) == "fresh\n", "stale suffix removed")
        let lockedFD = open(file.path, O_RDONLY)
        require(lockedFD >= 0 && flock(lockedFD, LOCK_EX | LOCK_NB) == 0, "external lock setup")
        require(!BottomPanelDiagnostic.persistForTesting(bytes, parent: normal.path), "interprocess lock is nonblocking")
        _ = flock(lockedFD, LOCK_UN); close(lockedFD)
        let victim = root.appendingPathComponent("victim")
        try Data("keep\n".utf8).write(to: victim)
        for kind in ["symlink", "hardlink", "fifo"] {
            let parent = root.appendingPathComponent(kind)
            let child = parent.appendingPathComponent("TapLockBottomDiag2")
            try fm.createDirectory(at: child, withIntermediateDirectories: true)
            let target = child.appendingPathComponent("report.txt")
            if kind == "symlink" { try fm.createSymbolicLink(atPath: target.path, withDestinationPath: victim.path) }
            else if kind == "hardlink" { require(link(victim.path, target.path) == 0, "hardlink setup") }
            else { require(mkfifo(target.path, 0o600) == 0, "FIFO setup") }
            require(!BottomPanelDiagnostic.persistForTesting(bytes, parent: parent.path), "unsafe final inode rejected")
            require(try String(contentsOf: victim, encoding: .utf8) == "keep\n", "unrelated victim untouched")
        }
        let badParent = root.appendingPathComponent("directory-symlink")
        try fm.createDirectory(at: badParent, withIntermediateDirectories: false)
        try fm.createSymbolicLink(atPath: badParent.appendingPathComponent("TapLockBottomDiag2").path,
                                  withDestinationPath: directory.path)
        require(!BottomPanelDiagnostic.persistForTesting(bytes, parent: badParent.path), "symlink directory rejected")
        require(!BottomPanelDiagnostic.persistForTesting(bytes, parent: root.appendingPathComponent("absent").path), "missing parent fails safely")
        fields = record()
        require(fields["package_version"] == "0.1.13+bottomfix1.diag1" && fields["mode"] == "diagnostic_only", "diagnostic label")
        print("BOTTOM_DIAGNOSTIC_RUNTIME_PASS: assertions=\(checks)")
        #else
        BottomPanelDiagnostic.mark(.activated)
        BottomPanelDiagnostic.preferences(available: true, enabled: 1, actions: 1, flow: 0)
        BottomPanelDiagnostic.callback(0)
        require(!fm.fileExists(atPath: root.path), "disabled collector creates no sink")
        print("BOTTOM_DIAGNOSTIC_DISABLED_PASS: assertions=\(checks)")
        #endif
    }
}
