import Foundation
import CoreFoundation
import ObjectiveC
import Darwin

#if !MEDIA_PLAY_PAUSE_BASELINE
@objc(TLMediaLockManagerFixture)
class MediaLockFixture: NSObject {
    static var current: NSObject?
    static var getters = 0
    @objc class func sharedInstanceIfExists() -> NSObject? { getters += 1; return current }
}
class MediaUnlockedFixture: MediaLockFixture {
    var locked = false, visible = false, unlocking = false
    @objc func isUILocked() -> Bool { locked }
    @objc func isLockScreenVisible() -> Bool { visible }
    @objc func isUIUnlocking() -> Bool { unlocking }
}
class MediaBadLockABIFixture: MediaLockFixture {
    var stateCalls = 0
    @objc func isUILocked() -> Int64 { stateCalls += 1; return 0 }
    @objc func isLockScreenVisible() -> Bool { false }
    @objc func isUIUnlocking() -> Bool { false }
}
#endif

@main
struct MediaPlayPauseRuntimeTests {
    static var assertions = 0
    static var cleanup: (() -> Bool)?
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            if cleanup?() == false { print("MEDIA_PLAY_PAUSE_RUNTIME_FAIL: preference restoration failed"); fflush(stdout); exit(2) }
            cleanup = nil
            print("MEDIA_PLAY_PAUSE_RUNTIME_FAIL: " + message); fflush(stdout); exit(1)
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
    #if !MEDIA_PLAY_PAUSE_BASELINE
    static func preferences(_ enabled: CFPropertyList?) {
        require(TapLockPreferences.readAction() == .playPause, "wrong media decode")
        require(TapLockPreferences.writeAction(.playPause), "media write failed")
        require(TapLockPreferences.readAction() == .playPause && same(stored(TapLockPreferences.actionKey), ["kind": "playPause"] as CFDictionary), "media must round-trip one kind without a target")
        let malformed: [[String: Any]] = [
            ["kind": "playPause", "extra": "bad"], ["kind": "playPause", "bundleIdentifier": "com.example.app"],
            ["kind": "playPause", "enabled": true], ["kind": "PlayPause"], ["kind": "playPause "],
            // Track actions are now valid; their extra-key records remain malformed.
            ["kind": "Siri"], ["kind": "nextTrack", "extra": "bad"], ["kind": "previousTrack", "extra": "bad"], ["kind": true],
            ["kind": 2], ["kind": ["playPause"]], [:]
        ]
        for record in malformed {
            raw(record as CFDictionary)
            require(TapLockPreferences.readAction() == .unavailable, "malformed or unimplemented action admitted")
            require(same(stored(TapLockPreferences.actionKey), record as CFDictionary), "invalid read rewrote state")
        }
        for value in ["playPause" as CFString, ["playPause"] as CFArray, NSNumber(value: true)] as [CFPropertyList] {
            raw(value); require(TapLockPreferences.readAction() == .unavailable, "non-dictionary action admitted")
        }
        raw(nil)
        require(TapLockPreferences.readAction() == .lock && stored(TapLockPreferences.actionKey) == nil, "missing default changed or persisted")
        let older: [(TapLockPreferences.Action, [String: String])] = [
            (.lock, ["kind": "lock"]), (.openApp("com.example.app"), ["kind": "openApp", "bundleIdentifier": "com.example.app"]),
            (.controlCenter, ["kind": "controlCenter"]), (.notificationCenter, ["kind": "notificationCenter"]),
            (.screenshot, ["kind": "screenshot"]), (.appSwitcher, ["kind": "appSwitcher"])
        ]
        for (action, record) in older {
            raw(record as CFDictionary)
            require(TapLockPreferences.readAction() == action, "older action decode changed")
            require(TapLockPreferences.writeAction(.playPause) && TapLockPreferences.readAction() == .playPause, "old-to-media replacement failed")
            require(same(stored(TapLockPreferences.actionKey), ["kind": "playPause"] as CFDictionary), "media retained older payload")
            require(TapLockPreferences.writeAction(action) && TapLockPreferences.readAction() == action, "media-to-old replacement failed")
            require(same(stored(TapLockPreferences.actionKey), record as CFDictionary), "older record changed")
        }
        require(TapLockPreferences.writeAction(.playPause), "final selection failed")
        let previous = stored(TapLockPreferences.actionKey)
        require(!TapLockPreferences.writeAction(.unavailable) && !TapLockPreferences.writeAction(.openApp("")), "invalid write accepted")
        require(same(stored(TapLockPreferences.actionKey), previous) && same(stored(TapLockPreferences.enabledKey), enabled), "selection changed unrelated state")
    }
    static func copyFixture(_ source: String, _ target: String) {
        do {
            if FileManager.default.fileExists(atPath: target) { try FileManager.default.removeItem(atPath: target) }
            try FileManager.default.copyItem(atPath: source, toPath: target)
        } catch { require(false, "disposable fixture copy failed: \(error)") }
    }
    static func runtime(_ mode: String, target: String, working: String, missingSymbol: String) {
        require(Thread.isMainThread, "not running on main")
        require(NSClassFromString("TLMediaLockManagerFixture").map { ObjectIdentifier($0) } == ObjectIdentifier(MediaLockFixture.self), "fixture identity collision")
        require(!FileManager.default.fileExists(atPath: target), "runner must begin with absent loader path")
        let lock = MediaUnlockedFixture(), bad = MediaBadLockABIFixture()
        MediaLockFixture.current = lock
        let beforeGetters = MediaLockFixture.getters
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            require(!Thread.isMainThread && !MediaPlayPauseAction.toggle(), "off-main request admitted")
            done.signal()
        }
        require(done.wait(timeout: .now() + 5) == .success, "off-main test timed out")
        require(MediaLockFixture.getters == beforeGetters, "off-main request acquired lock state")
        lock.locked = true; require(!MediaPlayPauseAction.toggle(), "locked request admitted"); lock.locked = false
        lock.visible = true; require(!MediaPlayPauseAction.toggle(), "visible lock admitted"); lock.visible = false
        lock.unlocking = true; require(!MediaPlayPauseAction.toggle(), "unlock transition admitted"); lock.unlocking = false
        for value in [nil, NSObject(), MediaLockFixture(), bad] as [NSObject?] {
            MediaLockFixture.current = value; require(!MediaPlayPauseAction.toggle(), "missing/wrong lock receiver or ABI admitted")
        }
        require(bad.stateCalls == 0, "bad lock ABI invoked")
        MediaLockFixture.current = lock
        let snapshot = CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        if mode == "--missing-library" {
            require(!MediaPlayPauseAction.toggle(), "missing library accepted")
            copyFixture(working, target)
            require(!MediaPlayPauseAction.toggle(), "missing-library result retried instead of cached")
        } else if mode == "--missing-symbol" {
            copyFixture(missingSymbol, target)
            require(!MediaPlayPauseAction.toggle(), "missing symbol accepted")
            copyFixture(working, target)
            require(!MediaPlayPauseAction.toggle(), "missing-symbol result retried instead of cached")
        } else {
            require(mode == "--working", "unknown runtime mode")
            // All rejection paths above ran while the image was absent. Success
            // now also proves none of them initialized/cached the loader early.
            copyFixture(working, target)
            require(MediaPlayPauseAction.toggle(), "native nonzero result rejected")
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
            require(calls() == 1 && command() == 2 && options() == 0 && main() == 1, "must send exactly once on main: enum32=2, options=nil")
            reset(0)
            require(!MediaPlayPauseAction.toggle() && calls() == 1, "native refusal retried or reported as success")
            reset(255)
            require(MediaPlayPauseAction.toggle() && calls() == 1, "unsigned byte nonzero result was not preserved")
            reset(1)
            require(MediaPlayPauseAction.toggle() && calls() == 1, "valid request did not recover after refusal")
            lock.locked = true
            require(!MediaPlayPauseAction.toggle() && calls() == 1, "cached provider bypassed lock admission")
            lock.locked = false
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            require(calls() == 1 && command() == 2 && options() == 0 && main() == 1, "rejected request scheduled later work")
        }
        require(same(CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost), snapshot), "provider changed preferences")
        MediaLockFixture.current = nil
    }
    #endif
    static func main() {
        require(TapLockPreferences.domain == "com.tsangbaby.taplock" && TapLockPreferences.actionKey == "DoubleTapAction" && TapLockPreferences.enabledKey == "Enabled", "preference namespace changed")
        require(sync(), "initial synchronization failed")
        let action = stored(TapLockPreferences.actionKey), enabled = stored(TapLockPreferences.enabledKey)
        cleanup = {
            CFPreferencesSetValue(TapLockPreferences.actionKey as CFString, action, TapLockPreferences.domain as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return sync() && same(stored(TapLockPreferences.actionKey), action) && same(stored(TapLockPreferences.enabledKey), enabled)
        }
        raw(["kind": "playPause"] as CFDictionary)
        require(TapLockPreferences.readAction() != .unavailable, "persisted media action is unavailable")
        #if MEDIA_PLAY_PAUSE_BASELINE
        require(cleanup?() == true, "preference restoration failed"); cleanup = nil
        print("MEDIA_PLAY_PAUSE_BASELINE_UNEXPECTED_SUCCESS")
        #else
        let args = CommandLine.arguments
        require(args.count == 5, "expected isolated mode and three fixture paths")
        preferences(enabled)
        runtime(args[1], target: args[2], working: args[3], missingSymbol: args[4])
        require(cleanup?() == true, "preference restoration failed"); cleanup = nil
        print("MEDIA_PLAY_PAUSE_RUNTIME_PASS: \(assertions) assertions; mode=\(args[1]); actual Swift/C loader fixture, NOT handset playback proof")
        #endif
        fflush(stdout)
    }
}
