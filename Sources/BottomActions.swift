import UIKit

/// Bottom-only consumer of an immutable gesture selection. The scheduler,
/// provider effects and permission read are I/O seams, not alternate policies.
/// Fixed offsets order invocation only; no provider completion is inferred.
final class BottomActionCoordinator: BottomActionPanelDelegate {
    struct IO {
        let now: () -> TimeInterval
        let schedule: (TimeInterval, @escaping () -> Void) -> Void
        let invoke: (TapLockPreferences.Action) -> Void
        let permission: (UIWindowScene, Bool) -> Bool

        static let live = IO(now: { ProcessInfo.processInfo.systemUptime }, schedule: { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }, invoke: { action in
            switch action {
            case .lock: LockAction.requestLock()
            case .openApp(let identifier):
                guard TapLockPreferences.validBundleIdentifier(identifier) else { return }
                AppAction.open(identifier: identifier)
            case .controlCenter: ControlCenterAction.open()
            case .notificationCenter: NotificationCenterAction.open()
            case .screenshot: ScreenshotAction.capture()
            case .appSwitcher: AppSwitcherAction.open()
            case .playPause: MediaPlayPauseAction.toggle()
            case .previousTrack: MediaPlayPauseAction.previousTrack()
            case .nextTrack: MediaPlayPauseAction.nextTrack()
            case .flashlight: FlashlightAction.toggle()
            case .systemMute: SystemMuteAction.toggle()
            case .unavailable: return
            }
        }, permission: { _, allowWhileLocked in
            // This relaxes only consumer permission. Unchanged providers still
            // enforce their own lock/capability/target guards; no bypass route.
            allowWhileLocked || LockAction.unlockedManager() != nil
        })
    }

    static let shared = BottomActionCoordinator()
    private let io: IO
    private var generation: UInt64 = 0
    private var observations: [NSObjectProtocol] = []
    private weak var flowScene: UIWindowScene?
    private weak var panelScene: UIWindowScene?
    private var panelOrientation = UIInterfaceOrientation.unknown
    private var panelAllowsLocked = false
    // Read-only ownership visibility; callers cannot install a replacement.
    private(set) var panelWindow: UIWindow?

    init(io: IO = .live) {
        self.io = io
        let center = NotificationCenter.default
        let global: [Notification.Name] = [UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification, UIDevice.orientationDidChangeNotification,
            UIAccessibility.voiceOverStatusDidChangeNotification]
        for name in global {
            observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.cancelAll()
            })
        }
        for name in [UIScene.willDeactivateNotification, UIScene.didDisconnectNotification] {
            observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self = self, let scene = note.object as? UIWindowScene,
                      scene === self.panelScene || scene === self.flowScene else { return }
                self.cancelAll()
            })
        }
    }

    deinit {
        for observer in observations { NotificationCenter.default.removeObserver(observer) }
        if Thread.isMainThread { releasePanel() }
    }

    func trigger(_ selection: BottomGesturePreferences.Selection,
                 in scene: UIWindowScene, allowWhileLocked: Bool) {
        guard Thread.isMainThread else { return }
        cancelPendingFlow()
        guard selection.enabled, !selection.actions.isEmpty,
              selection.actions.allSatisfy(Self.isValid),
              isEligible(scene, orientation: scene.interfaceOrientation, allowWhileLocked: allowWhileLocked) else {
            releasePanel()
            return
        }
        if selection.flowEnabled {
            releasePanel()
            startFlow(selection.actions, in: scene, allowWhileLocked: allowWhileLocked)
            return
        }
        // Canonical maintained policy intentionally differs from the original
        // single-item direct-action optimization: normal ALWAYS shows a chooser.
        if panelWindow != nil {
            releasePanel()
            return // An existing chooser toggles closed; do not replace/reopen it.
        }
        presentPanel(selection.actions, in: scene, allowWhileLocked: allowWhileLocked)
    }

    /// New admitted native Began invalidates pending actions, not a shown panel.
    func cancelPendingFlow() {
        guard Thread.isMainThread else { return }
        generation &+= 1
        flowScene = nil
    }

    /// Runtime owns lock-transition/preferences-reload cancellation and calls this
    /// as well as the public UIKit scene/orientation/suspension notifications above.
    func cancelAll() {
        guard Thread.isMainThread else { return }
        cancelPendingFlow()
        releasePanel()
    }

    private static func isValid(_ action: TapLockPreferences.Action) -> Bool {
        switch action {
        case .unavailable: return false
        case .openApp(let identifier): return TapLockPreferences.validBundleIdentifier(identifier)
        default: return true
        }
    }

    private func isEligible(_ scene: UIWindowScene, orientation: UIInterfaceOrientation,
                            allowWhileLocked: Bool) -> Bool {
        guard Thread.isMainThread, scene.screen === UIScreen.main,
              scene.activationState == .foregroundActive,
              UIApplication.shared.applicationState == .active,
              !UIAccessibility.isVoiceOverRunning,
              orientation != .unknown, scene.interfaceOrientation == orientation else { return false }
        return io.permission(scene, allowWhileLocked)
    }

    private func startFlow(_ actions: [TapLockPreferences.Action], in scene: UIWindowScene,
                           allowWhileLocked: Bool) {
        let token = generation
        let orientation = scene.interfaceOrientation
        let origin = io.now()
        flowScene = scene
        for (ordinal, action) in actions.enumerated() {
            guard generation == token,
                  isEligible(scene, orientation: orientation, allowWhileLocked: allowWhileLocked) else {
                if generation == token { cancelAll() }
                return
            }
            if ordinal == 0 {
                io.invoke(action) // Immediate on main, not a provider-success claim.
            } else {
                // Anchor every deadline to the trigger, not the duration of an
                // earlier provider. A slow call never adds another 0.3s per item.
                let delay = max(0, origin + 0.3 * Double(ordinal) - io.now())
                io.schedule(delay) { [weak self, weak scene] in
                    guard Thread.isMainThread, let self = self, self.generation == token else { return }
                    guard let scene = scene,
                          self.isEligible(scene, orientation: orientation, allowWhileLocked: allowWhileLocked) else {
                        self.cancelAll()
                        return
                    }
                    self.io.invoke(action)
                }
            }
        }
    }

    private func presentPanel(_ actions: [TapLockPreferences.Action], in scene: UIWindowScene,
                              allowWhileLocked: Bool) {
        let controller = BottomActionPanelController(actions: actions)
        controller.delegate = self
        let window = BottomActionPanelWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.statusBar.rawValue + 1)
        // Below system alerts; never mutate native windows.
        window.backgroundColor = .clear
        window.rootViewController = controller
        panelScene = scene
        panelOrientation = scene.interfaceOrientation
        panelAllowsLocked = allowWhileLocked
        panelWindow = window
        window.hasPresentedPanel = true
        window.isHidden = false // Do not steal key status or change another app's input view.
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        controller.activate()
    }

    private func releasePanel() {
        guard let window = panelWindow else { return }
        let controller = window.rootViewController as? BottomActionPanelController
        (window as? BottomActionPanelWindow)?.hasPresentedPanel = false
        controller?.invalidate()
        window.isHidden = true
        window.rootViewController = nil
        window.windowScene = nil
        panelWindow = nil
        panelScene = nil
        panelOrientation = .unknown
        panelAllowsLocked = false
    }

    func panelDidRequestDismissal(_ panel: BottomActionPanelController) {
        guard Thread.isMainThread, let window = panelWindow,
              window.rootViewController === panel,
              let choice = panel.consumeChoice() else { return }
        guard let scene = panelScene, window.windowScene === scene,
              isEligible(scene, orientation: panelOrientation, allowWhileLocked: panelAllowsLocked) else {
            cancelAll()
            return
        }
        cancelPendingFlow()
        let token = generation
        let orientation = panelOrientation
        let allowWhileLocked = panelAllowsLocked
        let selected: TapLockPreferences.Action?
        switch choice {
        case .cancel: selected = nil
        case .action(let index):
            guard panel.actions.indices.contains(index) else { cancelAll(); return }
            selected = panel.actions[index]
        }
        UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .curveEaseIn], animations: {
            panel.view.alpha = 0
        }, completion: { [weak self, weak window, weak panel, weak scene] finished in
            guard Thread.isMainThread, let self = self, let window = window, let panel = panel,
                  self.panelWindow === window, window.rootViewController === panel else { return }
            self.releasePanel() // Clear root/delegate/window even for canceled/obsolete work.
            guard finished, self.generation == token, let action = selected, let scene = scene,
                  self.isEligible(scene, orientation: orientation, allowWhileLocked: allowWhileLocked),
                  Self.isValid(action) else { return }
            self.io.invoke(action) // Exactly the tapped snapshot item, after dismissal.
        })
    }

    func panelGeometryWillChange(_ panel: BottomActionPanelController) {
        guard Thread.isMainThread, panelWindow?.rootViewController === panel else { return }
        cancelAll()
    }
}

protocol BottomActionPanelDelegate: AnyObject {
    func panelDidRequestDismissal(_ panel: BottomActionPanelController)
    func panelGeometryWillChange(_ panel: BottomActionPanelController)
}

/// No singleton/permanent shield: the coordinator allocates this only for a
/// chooser, then hides, disconnects and releases it. Defensive hit-testing is nil
/// even if a caller temporarily retains the old window after dismissal.
final class BottomActionPanelWindow: UIWindow {
    var hasPresentedPanel = false
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard Thread.isMainThread, hasPresentedPanel, !isHidden, rootViewController != nil else { return nil }
        return super.hitTest(point, with: event)
    }
}

final class BottomActionPanelController: UIViewController {
    enum Choice { case action(Int), cancel }
    let actions: [TapLockPreferences.Action]
    weak var delegate: BottomActionPanelDelegate?
    private let outside = UIButton(type: .custom)
    private let cancel = UIButton(type: .system)
    private var buttons: [UIButton] = []
    private var acceptingInput = false
    private var pendingChoice: Choice?

    init(actions: [TapLockPreferences.Action]) {
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { return nil }

    override func loadView() {
        let root = UIView()
        root.backgroundColor = .clear
        view = root
        outside.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        outside.accessibilityIdentifier = "bottom.outside"
        outside.accessibilityLabel = "关闭操作面板"
        outside.addTarget(self, action: #selector(cancelPressed(_:)), for: .touchUpInside)
        outside.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(outside)
        let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        card.layer.cornerRadius = 20
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(card)
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(content)
        let title = UILabel()
        title.text = "底部操作"
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        title.accessibilityTraits = .header
        content.addArrangedSubview(title)
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = false
        scroll.clipsToBounds = true
        content.addArrangedSubview(scroll)
        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 6
        list.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(list)
        for (index, action) in actions.enumerated() {
            let button = UIButton(type: .system)
            let appearance = Self.appearance(action)
            button.setTitle(appearance.0, for: .normal)
            button.setImage(UIImage(systemName: appearance.1), for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .body)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.numberOfLines = 0
            button.contentHorizontalAlignment = .leading
            button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
            button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: -10)
            button.tag = index
            button.accessibilityIdentifier = "bottom.action.\(index)"
            button.addTarget(self, action: #selector(actionPressed(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            list.addArrangedSubview(button)
            buttons.append(button)
        }
        cancel.setTitle("取消", for: .normal)
        cancel.titleLabel?.font = .preferredFont(forTextStyle: .body)
        cancel.titleLabel?.adjustsFontForContentSizeCategory = true
        cancel.accessibilityIdentifier = "bottom.cancel"
        cancel.addTarget(self, action: #selector(cancelPressed(_:)), for: .touchUpInside)
        cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        content.addArrangedSubview(cancel)
        let preferredWidth = card.widthAnchor.constraint(equalToConstant: 560)
        preferredWidth.priority = .defaultHigh
        let preferredHeight = scroll.heightAnchor.constraint(equalTo: list.heightAnchor)
        preferredHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            outside.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            outside.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            outside.topAnchor.constraint(equalTo: root.topAnchor),
            outside.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            card.centerXAnchor.constraint(equalTo: root.safeAreaLayoutGuide.centerXAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: root.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(lessThanOrEqualTo: root.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            card.topAnchor.constraint(greaterThanOrEqualTo: root.safeAreaLayoutGuide.topAnchor, constant: 12),
            card.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            preferredWidth,
            content.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -12),
            list.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            list.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            scroll.heightAnchor.constraint(lessThanOrEqualTo: root.safeAreaLayoutGuide.heightAnchor, multiplier: 0.6),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 44), preferredHeight
        ])
        root.accessibilityViewIsModal = true
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        delegate?.panelGeometryWillChange(self)
    }

    func activate() {
        guard Thread.isMainThread, view.window != nil else { return }
        acceptingInput = true
    }

    func invalidate() {
        acceptingInput = false
        pendingChoice = nil
        delegate = nil
        for button in buttons + [outside, cancel] {
            button.isEnabled = false
            button.removeTarget(self, action: nil, for: .allEvents)
        }
    }

    private func isVisible(_ control: UIControl) -> Bool {
        guard acceptingInput, isViewLoaded, control.isEnabled,
              let window = view.window, !window.isHidden,
              window.rootViewController === self, control.window === window,
              control.isDescendant(of: view) else { return false }
        var rect = control.convert(control.bounds, to: window)
        var ancestor: UIView? = control
        while let current = ancestor {
            guard !current.isHidden, current.alpha > 0.01, current.isUserInteractionEnabled else { return false }
            if current.clipsToBounds || current === window {
                rect = rect.intersection(current.convert(current.bounds, to: window))
            }
            ancestor = current.superview
        }
        return !rect.isNull && !rect.isEmpty
    }

    @objc private func actionPressed(_ sender: UIButton) {
        guard Thread.isMainThread,
              let index = buttons.firstIndex(where: { $0 === sender }),
              actions.indices.contains(index), sender.tag == index, isVisible(sender) else { return }
        request(.action(index))
    }

    @objc private func cancelPressed(_ sender: UIButton) {
        guard Thread.isMainThread, sender === outside || sender === cancel, isVisible(sender) else { return }
        request(.cancel)
    }

    private func request(_ choice: Choice) {
        guard acceptingInput else { return }
        acceptingInput = false
        for button in buttons + [outside, cancel] { button.isEnabled = false }
        pendingChoice = choice
        delegate?.panelDidRequestDismissal(self)
    }

    /// Delegate cannot manufacture a selection with a forced index. Only a
    /// currently owned, visible control arms this one-shot synchronous authority.
    func consumeChoice() -> Choice? {
        defer { pendingChoice = nil }
        return pendingChoice
    }

    private static func appearance(_ action: TapLockPreferences.Action) -> (String, String) {
        switch action {
        case .lock: return ("锁屏", "lock")
        case .openApp(let identifier): return (identifier, "app")
        case .controlCenter: return ("控制中心", "switch.2")
        case .notificationCenter: return ("通知中心", "bell")
        case .screenshot: return ("截图", "camera.viewfinder")
        case .appSwitcher: return ("多任务", "square.stack.3d.up")
        case .playPause: return ("播放/暂停", "playpause")
        case .previousTrack: return ("上一首", "backward.end")
        case .nextTrack: return ("下一首", "forward.end")
        case .flashlight: return ("手电筒", "flashlight.on.fill")
        case .systemMute: return ("静音", "bell.slash")
        case .unavailable: return ("不可用", "nosign")
        }
    }
}
