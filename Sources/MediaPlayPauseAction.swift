import Foundation
import Darwin

/// Sends one system media toggle. Nonzero is the native submission result,
/// not proof that a player exists, accepted the command or changed playback.
enum MediaPlayPauseAction {
    private typealias SendCommand = @convention(c) (UInt32, AnyObject?) -> UInt8

    // Resolve only after admission. Keep a successful handle for the process
    // lifetime so the cached function pointer cannot outlive its image.
    // Cache failure too: no retry or alternate media/button route.
    private static let sendCommand: SendCommand? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW | RTLD_LOCAL) else {
            return nil
        }
        guard let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else {
            dlclose(handle)
            return nil
        }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    @discardableResult
    static func toggle() -> Bool {
        guard Thread.isMainThread,
              LockAction.unlockedManager() != nil,
              let send = sendCommand else { return false }
        return send(2, nil) != 0
    }

    @discardableResult
    static func previousTrack() -> Bool {
        guard Thread.isMainThread,
              LockAction.unlockedManager() != nil,
              let send = sendCommand else { return false }
        return send(5, nil) != 0
    }

    @discardableResult
    static func nextTrack() -> Bool {
        guard Thread.isMainThread,
              LockAction.unlockedManager() != nil,
              let send = sendCommand else { return false }
        return send(4, nil) != 0
    }
}
