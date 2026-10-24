import Foundation
import CoreFoundation
import ObjectiveC
import Darwin

#if !MEDIA_TRACKS_BASELINE
@objc(TLMediaTrackLockManagerFixture)
class MediaTrackLockFixture: NSObject {
    static var current: NSObject?
    static var getters = 0
    @objc class func sharedInstanceIfExists() -> NSObject? { getters += 1; return current }
}
class MediaTrackUnlockedFixture: MediaTrackLockFixture {
    var locked = false, visible = false, unlocking = false
    @objc func isUILocked() -> Bool { locked }
    @objc func isLockScreenVisible() -> Bool { visible }
    @objc func isUIUnlocking() -> Bool { unlocking }
}
class MediaTrackBadLockABIFixture: MediaTrackLockFixture {
    var stateCalls = 0
    @objc func isUILocked() -> Int64 { stateCalls += 1; return 0 }
    @objc func isLockScreenVisible() -> Bool { false }
    @objc func isUIUnlocking() -> Bool { false }
}
#endif

// Same real preferences harness compiles against original 0.1.10 and current.
// Native service is an independent C fixture, never a live player connection.
@main
struct MediaTracksRuntimeTests {
    static var assertions = 0
    static var cleanup: (() -> Bool)?
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            if cleanup?() == false { print("MEDIA_TRACKS_RUNTIME_FAIL: preference restoration failed"); fflush(stdout); exit(2) }
            cleanup = nil
            print("MEDIA_TRACKS_RUNTIME_FAIL: " + message); fflush(stdout); exit(1)
        }
        assertions += 1
    }
    static func same(_ lhs: CFPropertyList?, _ rhs: CFPropertyList?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (left?, right?): return CFEqual(left, right)
        default: return false
        }
    }
    static func sync() -> Bool {
        CFPreferencesSynchronize(TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    static func stored(_ key: String) -> CFPropertyList? {
        CFPreferencesCopyValue(key as CFString, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    static func raw(_ value: CFPropertyList?) {
        CFPreferencesSetValue(TapLockPreferences.actionKey as CFString, value, TapLockPreferences.domain as CFString,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        require(sync(), "fixture preference write failed")
    }
    #if !MEDIA_TRACKS_BASELINE
    static func preferences(_ enabled: CFPropertyList?) {
        let actions: [(TapLockPreferences.Action, [String: String])] = [
            (.lock, ["kind": "lock"]),
            (.openApp("com.example.app"), ["kind": "openApp", "bundleIdentifier": "com.example.app"]),
            (.controlCenter, ["kind": "controlCenter"]), (.notificationCenter, ["kind": "notificationCenter"]),
            (.screenshot, ["kind": "screenshot"]), (.appSwitcher, ["kind": "appSwitcher"]),
            (.playPause, ["kind": "playPause"]), (.nextTrack, ["kind": "nextTrack"]),
            (.previousTrack, ["kind": "previousTrack"])
        ]
        for (before, record) in actions {
            for (after, replacement) in actions {
                raw(record as CFDictionary)
                require(TapLockPreferences.readAction() == before, "existing action decode changed")
                require(TapLockPreferences.writeAction(after), "single action replacement failed")
                require(TapLockPreferences.readAction() == after, "replacement did not round-trip")
                require(same(stored(TapLockPreferences.actionKey), replacement as CFDictionary), "replacement retained another action or App payload")
                require(same(stored(TapLockPreferences.enabledKey), enabled), "replacement changed enable state")
            }
        }
        for kind in ["nextTrack", "previousTrack"] {
            let malformed: [[String: Any]] = [
                ["kind": kind, "extra": "bad"], ["kind": kind, "bundleIdentifier": "com.example.app"],
                ["kind": kind, "enabled": true], ["kind": kind + " "], ["kind": kind.uppercased()]
            ]
            for record in malformed {
                raw(record as CFDictionary)
                require(TapLockPreferences.readAction() == .unavailable, "malformed track admitted")
                require(same(stored(TapLockPreferences.actionKey), record as CFDictionary), "invalid read rewrote preferences")
            }
        }
        for value in ["nextTrack" as CFString, ["previousTrack"] as CFArray, NSNumber(value: true),
                      ["kind": "Siri"] as CFDictionary, ["kind": true] as CFDictionary,
                      ["kind": 4] as CFDictionary, ["kind": ["nextTrack"]] as CFDictionary,
                      [:] as CFDictionary] as [CFPropertyList] {
            raw(value)
            require(TapLockPreferences.readAction() == .unavailable, "malformed action admitted")
            require(same(stored(TapLockPreferences.actionKey), value), "malformed action was rewritten")
        }
        raw(nil)
        require(TapLockPreferences.readAction() == .lock && stored(TapLockPreferences.actionKey) == nil, "missing action default changed or persisted")
        require(TapLockPreferences.writeAction(.nextTrack), "final next selection failed")
        let previous = stored(TapLockPreferences.actionKey)
        require(!TapLockPreferences.writeAction(.unavailable) && !TapLockPreferences.writeAction(.openApp("")), "invalid write accepted")
        require(same(stored(TapLockPreferences.actionKey), previous) && same(stored(TapLockPreferences.enabledKey), enabled), "invalid write or selection changed unrelated state")
    }
    static func copyFixture(_ source: String, _ target: String) {
        do {
            if FileManager.default.fileExists(atPath: target) { try FileManager.default.removeItem(atPath: target) }
            try FileManager.default.copyItem(atPath: source, toPath: target)
        } catch { require(false, "disposable fixture copy failed: \(error)") }
    }
    static func rejectAll(_ message: String) {
        let operations: [() -> Bool] = [MediaPlayPauseAction.nextTrack, MediaPlayPauseAction.previousTrack, MediaPlayPauseAction.toggle]
        for operation in operations { require(!operation(), message) }
    }
    static func rejectOffMain() {
        let before = MediaTrackLockFixture.getters
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            require(!Thread.isMainThread, "off-main test ran on main")
            rejectAll("off-main media request admitted")
            done.signal()
        }
        require(done.wait(timeout: .now() + 5) == .success, "off-main test timed out")
        require(MediaTrackLockFixture.getters == before, "off-main request acquired lock state")
    }
    static func runtime(_ mode: String, target: String, working: String, missingSymbol: String) {
        require(Thread.isMainThread, "not running on main")
        require(NSClassFromString("TLMediaTrackLockManagerFixture").map { ObjectIdentifier($0) } == ObjectIdentifier(MediaTrackLockFixture.self), "fixture identity collision")
        require(!FileManager.default.fileExists(atPath: target), "runner must begin with absent loader path")
        let lock = MediaTrackUnlockedFixture(), bad = MediaTrackBadLockABIFixture()
        MediaTrackLockFixture.current = lock
        rejectOffMain()
        lock.locked = true; rejectAll("locked request admitted"); lock.locked = false
        lock.visible = true; rejectAll("visible lock admitted"); lock.visible = false
        lock.unlocking = true; rejectAll("unlock transition admitted"); lock.unlocking = false
        for value in [nil, NSObject(), MediaTrackLockFixture(), bad] as [NSObject?] {
            MediaTrackLockFixture.current = value
            rejectAll("missing/wrong lock receiver or ABI admitted")
        }
        require(bad.stateCalls == 0, "bad lock ABI invoked")
        MediaTrackLockFixture.current = lock
        require(LockAction.unlockedManager() != nil, "valid lock state did not recover")
        let snapshot = CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        if mode == "--missing-library" {
            require(!MediaPlayPauseAction.nextTrack(), "missing library accepted")
            copyFixture(working, target)
            rejectAll("missing-library cache retried through another media operation")
        } else if mode == "--missing-symbol" {
            copyFixture(missingSymbol, target)
            require(!MediaPlayPauseAction.previousTrack(), "missing symbol accepted")
            copyFixture(working, target)
            rejectAll("missing-symbol cache retried through another media operation")
        } else {
            require(mode == "--working", "unknown runtime mode")
            // All rejections above ran without an image. Success now also proves
            // none of them prematurely initialized the shared failure cache.
            copyFixture(working, target)
            require(MediaPlayPauseAction.nextTrack(), "native next-track result rejected")
            guard let handle = dlopen(target, RTLD_NOW | RTLD_LOCAL) else { require(false, "fixture control open failed"); return }
            defer { dlclose(handle) }
            func symbol(_ name: String) -> UnsafeMutableRawPointer {
                guard let value = dlsym(handle, name) else { require(false, "fixture control symbol missing: " + name); exit(2) }
                return value
            }
            typealias Reset = @convention(c) (UInt8) -> Void
            typealias Read = @convention(c) () -> UInt32
            let reset = unsafeBitCast(symbol("TLMediaFixtureReset"), to: Reset.self)
            let calls = unsafeBitCast(symbol("TLMediaFixtureCalls"), to: Read.self)
            let command = unsafeBitCast(symbol("TLMediaFixtureCommand"), to: Read.self)
            let options = unsafeBitCast(symbol("TLMediaFixtureOptions"), to: Read.self)
            let main = unsafeBitCast(symbol("TLMediaFixtureMainThread"), to: Read.self)
            require(calls() == 1 && command() == 4 && options() == 0 && main() == 1, "must send next exactly once on main: enum32=4, options=nil")
            let operations: [(UInt32, () -> Bool)] = [
                (4, MediaPlayPauseAction.nextTrack), (5, MediaPlayPauseAction.previousTrack), (2, MediaPlayPauseAction.toggle)
            ]
            for nativeResult in [UInt8(0), UInt8(255), UInt8(1)] {
                for (expectedCommand, operation) in operations {
                    reset(nativeResult)
                    require(operation() == (nativeResult != 0), "native unsigned-byte refusal/nonzero result changed")
                    require(calls() == 1 && command() == expectedCommand && options() == 0 && main() == 1,
                            "wrong/duplicate media command, options or thread")
                }
            }
            lock.locked = true
            rejectAll("cached provider bypassed lock admission")
            lock.locked = false
            rejectOffMain()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            require(calls() == 1 && command() == 2 && options() == 0 && main() == 1, "rejected/refused request scheduled later work")
        }
        require(same(CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost), snapshot), "media provider changed preferences")
        MediaTrackLockFixture.current = nil
    }
    #endif
    static func main() {
        let args = CommandLine.arguments
        require(TapLockPreferences.domain == "com.tsangbaby.taplock" && TapLockPreferences.actionKey == "DoubleTapAction" && TapLockPreferences.enabledKey == "Enabled", "preference namespace changed")
        require(sync(), "initial synchronization failed")
        let action = stored(TapLockPreferences.actionKey), enabled = stored(TapLockPreferences.enabledKey)
        cleanup = {
            CFPreferencesSetValue(TapLockPreferences.actionKey as CFString, action, TapLockPreferences.domain as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return sync() && same(stored(TapLockPreferences.actionKey), action) && same(stored(TapLockPreferences.enabledKey), enabled)
        }
        #if MEDIA_TRACKS_BASELINE
        require(args.count == 2 && ["--baseline-next", "--baseline-previous"].contains(args[1]), "expected exact baseline mode")
        let kind = args[1] == "--baseline-next" ? "nextTrack" : "previousTrack"
        raw(["kind": kind] as CFDictionary)
        require(TapLockPreferences.readAction() != .unavailable, "persisted " + kind + " action is unavailable")
        require(cleanup?() == true, "preference restoration failed"); cleanup = nil
        print("MEDIA_TRACKS_BASELINE_UNEXPECTED_SUCCESS")
        #else
        require(args.count == 5, "expected isolated mode and three fixture paths")
        preferences(enabled)
        runtime(args[1], target: args[2], working: args[3], missingSymbol: args[4])
        require(cleanup?() == true, "preference restoration failed"); cleanup = nil
        print("MEDIA_TRACKS_RUNTIME_PASS: \(assertions) assertions; mode=\(args[1]); actual Swift/C loader fixture, NOT handset track-change proof")
        #endif
        fflush(stdout)
    }
}
