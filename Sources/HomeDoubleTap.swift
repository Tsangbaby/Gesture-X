import UIKit
import ObjectiveC
import CoreFoundation

private let preferencesChanged: CFNotificationCallback = { _, observer, _, _, _ in
    guard let observer = observer else { return }
    let owner = Unmanaged<HomeDoubleTap>.fromOpaque(observer).takeUnretainedValue()
    DispatchQueue.main.async {
        owner.reloadPreferences()
    }
}

/// Process-lifetime owner. Views retain their recognizers; this owner retains
/// neither views nor recognizers, and registers observers exactly once.
final class HomeDoubleTap: NSObject, UIGestureRecognizerDelegate {
    static let shared = HomeDoubleTap()

    private let recognizers = NSHashTable<UIGestureRecognizer>.weakObjects()
    private var started = false
    private var enabled = false
    private var action: TapLockPreferences.Action = .lock
    private var isDispatchingAction = false

    private override init() { super.init() }

    func start() {
        guard Thread.isMainThread else { return }
        guard !started else { return }
        started = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), preferencesChanged,
            TapLockPreferences.changedNotification as CFString, nil, .deliverImmediately
        )
        let center = NotificationCenter.default
        for name in [UIApplication.didFinishLaunchingNotification,
                     UIApplication.didBecomeActiveNotification,
                     UIAccessibility.voiceOverStatusDidChangeNotification] {
            center.addObserver(self, selector: #selector(activate), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(suspend),
                           name: UIApplication.willResignActiveNotification, object: nil)
        activate()
    }

    func attach(to host: UIView) {
        guard Thread.isMainThread else { return }
        if let existing = recognizers.allObjects.first(where: { $0.view === host }) {
            existing.isEnabled = false // Moving/detaching invalidates a partial double tap.
            if host.window == nil {
                host.removeGestureRecognizer(existing)
                recognizers.remove(existing)
            } else {
                existing.isEnabled = canListen
            }
            return
        }
        guard host.window != nil,
              let listType = NSClassFromString("SBIconListView"),
              ObjectIdentifier(type(of: host)) == ObjectIdentifier(listType) else {
            return
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(recognized(_:)))
        tap.numberOfTapsRequired = 2
        tap.numberOfTouchesRequired = 1
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        tap.isEnabled = canListen
        host.addGestureRecognizer(tap)
        recognizers.add(tap)
    }

    fileprivate func reloadPreferences() {
        guard Thread.isMainThread else { return }
        cancelAll() // Invalidate pending recognition even if off->on was coalesced.
        enabled = TapLockPreferences.readEnabled()
        action = TapLockPreferences.readAction()
        refreshRecognizers()
    }

    @objc private func activate() {
        guard Thread.isMainThread else { return }
        reloadPreferences()
        discoverExistingLists()
    }

    @objc private func suspend() {
        guard Thread.isMainThread else { return }
        cancelAll()
    }

    private var canListen: Bool {
        enabled && !UIAccessibility.isVoiceOverRunning &&
            UIApplication.shared.applicationState == .active &&
            LockAction.unlockedManager() != nil
    }

    private func cancelAll() {
        for recognizer in recognizers.allObjects { recognizer.isEnabled = false }
    }

    private func refreshRecognizers() {
        let allowed = canListen
        for recognizer in recognizers.allObjects {
            recognizer.isEnabled = allowed && recognizer.view?.window != nil
        }
    }

    /// Only at bootstrap/activation, never for every touch and never on a timer.
    private func discoverExistingLists() {
        guard let homeWindowType = NSClassFromString("SBHomeScreenWindow") else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.isKind(of: homeWindowType) {
                var pending: [UIView] = [window]
                while let view = pending.popLast() {
                    attach(to: view)
                    pending.append(contentsOf: view.subviews)
                }
            }
        }
    }

    private func isEligible(in host: UIView) -> Bool {
        guard Thread.isMainThread, enabled, !UIAccessibility.isVoiceOverRunning,
              UIApplication.shared.applicationState == .active,
              let window = host.window,
              window.screen === UIScreen.main,
              let scene = window.windowScene,
              scene.activationState == .foregroundActive,
              scene.interfaceOrientation.isPortrait,
              let homeWindowType = NSClassFromString("SBHomeScreenWindow"),
              window.isKind(of: homeWindowType),
              let location = PrivateAPI.object(host, "iconLocation") as? NSString,
              (location as String == "SBIconLocationRoot" ||
               location as String == "SBIconLocationRootWithWidgets"),
              LockAction.unlockedManager() != nil,
              PrivateAPI.bool(UIApplication.shared, "isShowingHomescreen") == true,
              let switcherType = NSClassFromString("SBMainSwitcherViewController"),
              let switcher = PrivateAPI.object(switcherType as AnyObject, "sharedInstanceIfExists"),
              PrivateAPI.bool(switcher, "isMainSwitcherVisible") == false,
              let controllerType = NSClassFromString("SBIconController"),
              let controller = PrivateAPI.object(controllerType as AnyObject, "sharedInstance"),
              let manager = PrivateAPI.object(controller, "iconManager"),
              PrivateAPI.bool(manager, "isEditing") == false else {
            return false
        }
        var ancestor: UIView? = host
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0.01, view.isUserInteractionEnabled else {
                return false
            }
            if let scroll = view as? UIScrollView,
               scroll.isDragging || scroll.isDecelerating { return false }
            // Do not lock during an already active pan/long press/drag.
            for peer in view.gestureRecognizers ?? [] where !recognizers.contains(peer) {
                if peer.state == .began || peer.state == .changed { return false }
            }
            ancestor = view.superview
        }
        return true
    }

    private func isBlankHit(in host: UIView, point: CGPoint) -> Bool {
        guard let window = host.window, host.bounds.contains(point) else { return false }
        return window.hitTest(host.convert(point, to: window), with: nil) === host
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard Thread.isMainThread,
              recognizers.contains(gestureRecognizer),
              touch.type == .direct,
              let host = gestureRecognizer.view, touch.view === host,
              isEligible(in: host) else { return false }
        return isBlankHit(in: host, point: touch.location(in: host))
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard Thread.isMainThread,
              recognizers.contains(gestureRecognizer),
              let host = gestureRecognizer.view, isEligible(in: host) else { return false }
        return isBlankHit(in: host, point: gestureRecognizer.location(in: host))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Permit coexistence with our tap only; never modify native/native rules.
        recognizers.contains(gestureRecognizer)
    }

    @objc private func recognized(_ sender: UITapGestureRecognizer) {
        guard Thread.isMainThread, sender.state == .ended, !isDispatchingAction,
              recognizers.contains(sender), let host = sender.view,
              isEligible(in: host),
              isBlankHit(in: host, point: sender.location(in: host)) else { return }
        isDispatchingAction = true
        defer { isDispatchingAction = false }
        switch action {
        case .lock:
            LockAction.requestLock()
        case .openApp(let identifier):
            AppAction.open(identifier: identifier)
        case .controlCenter:
            ControlCenterAction.open()
        case .notificationCenter:
            NotificationCenterAction.open()
        case .screenshot:
            ScreenshotAction.capture()
        case .appSwitcher:
            AppSwitcherAction.open()
        case .playPause:
            MediaPlayPauseAction.toggle()
        case .previousTrack:
            MediaPlayPauseAction.previousTrack()
        case .nextTrack:
            MediaPlayPauseAction.nextTrack()
        case .unavailable:
            break
        }
    }
}
