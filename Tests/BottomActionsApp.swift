import UIKit
import Darwin

// Executes the actual coordinator. Only clock/queue, provider effects and lock
// permission are replaced. UIKit ownership, admission and event paths are real.
@main
final class BottomActionsApp: UIResponder, UIApplicationDelegate, UIWindowSceneDelegate {
    var window: UIWindow?
    private var checks = 0
    private var events: [(TapLockPreferences.Action, TimeInterval)] = []
    private var allowed = true
    private var onInvoke: (() -> Void)?
    private var permissions: [Bool] = []
    private let clock = Clock()
    private var owner: BottomActionCoordinator!

    final class Clock {
        var now: TimeInterval = 0
        var jobs: [(TimeInterval, () -> Void)] = []
        func enqueue(_ delay: TimeInterval, _ block: @escaping () -> Void) {
            jobs.append((now + delay, block))
        }
        // Intentionally deliver invalidated jobs too: cancellation must be in
        // the production callback, not a cooperative scheduler fixture.
        func advance(to deadline: TimeInterval) {
            while let i = jobs.indices.filter({ jobs[$0].0 <= deadline }).min(by: { jobs[$0].0 < jobs[$1].0 }) {
                let job = jobs.remove(at: i)
                now = job.0
                job.1()
            }
            now = deadline
        }
    }
    private func finish(_ error: String? = nil) -> Never {
        if let error = error { print("BOTTOM_ACTIONS_UIKIT_FAIL: " + error) }
        else { print("BOTTOM_ACTIONS_UIKIT_PASS: assertions=\(checks)") }
        fflush(stdout)
        exit(error == nil ? 0 : 1)
    }
    private func require(_ predicate: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !predicate() { finish(message) }
    }
    private func selection(_ actions: [TapLockPreferences.Action], flow: Bool = true,
                           enabled: Bool = true) -> BottomGesturePreferences.Selection {
        .init(enabled: enabled, flowEnabled: flow, actions: actions)
    }
    private func reset() {
        owner.cancelAll()
        clock.jobs.removeAll()
        clock.now = 0
        events.removeAll()
        permissions.removeAll()
        onInvoke = nil
        allowed = true
    }
    private func testFlow(_ scene: UIWindowScene) {
        reset()
        owner.trigger(selection([.playPause, .previousTrack, .nextTrack]), in: scene, allowWhileLocked: false)
        require(events.map { $0.0 } == [.playPause], "first flow invocation must be immediate")
        require(events[0].1 == 0 && owner.panelWindow == nil, "flow must not allocate a shield/window")
        require(clock.jobs.map { $0.0 } == [0.3, 0.6], "flow must schedule fixed ordinal offsets")
        clock.advance(to: 0.299)
        require(events.count == 1, "flow ran early")
        clock.advance(to: 0.3)
        require(events.map { $0.0 } == [.playPause, .previousTrack], "wrong second invocation")
        clock.advance(to: 0.6)
        require(events.map { $0.0 } == [.playPause, .previousTrack, .nextTrack], "wrong ordered invocations")
        require(events.map { $0.1 } == [0, 0.3, 0.6], "wrong invocation offsets")
        reset()
        owner.trigger(selection([.playPause, .nextTrack]), in: scene, allowWhileLocked: false)
        owner.cancelPendingFlow()
        clock.advance(to: 1)
        require(events.map { $0.0 } == [.playPause], "new admitted Began must reject old delayed work")
        reset()
        owner.trigger(selection([.playPause, .nextTrack]), in: scene, allowWhileLocked: false)
        owner.trigger(selection([.flashlight, .systemMute]), in: scene, allowWhileLocked: false)
        clock.advance(to: 1)
        require(events.map { $0.0 } == [.playPause, .flashlight, .systemMute], "replacement flow leaked an old token")
        reset()
        owner.trigger(selection([.playPause, .nextTrack]), in: scene, allowWhileLocked: false)
        allowed = false
        clock.advance(to: 1)
        require(events.map { $0.0 } == [.playPause], "delayed work must recheck permission")
        reset()
        onInvoke = { [unowned self] in self.owner.cancelAll() }
        owner.trigger(selection([.playPause, .nextTrack]), in: scene, allowWhileLocked: false)
        require(events.map { $0.0 } == [.playPause] && clock.jobs.isEmpty,
                "provider reentry canceled its generation but old work was still scheduled")
        reset()
        onInvoke = { [unowned self] in self.clock.now = 0.2 }
        owner.trigger(selection([.playPause, .previousTrack, .nextTrack]), in: scene, allowWhileLocked: true)
        require(clock.jobs.count == 2 && abs(clock.jobs[0].0 - 0.3) < 0.000001 && abs(clock.jobs[1].0 - 0.6) < 0.000001,
                "provider duration shifted fixed trigger-relative deadlines")
        clock.advance(to: 1)
        require(!permissions.isEmpty && permissions.allSatisfy { $0 }, "allowWhileLocked must be carried through every delayed permission read")
        reset()
        for notification in [UIScene.willDeactivateNotification, UIScene.didDisconnectNotification,
                             UIDevice.orientationDidChangeNotification, UIAccessibility.voiceOverStatusDidChangeNotification] {
            owner.trigger(selection([.playPause, .nextTrack]), in: scene, allowWhileLocked: false)
            NotificationCenter.default.post(name: notification, object: scene)
            clock.advance(to: clock.now + 1)
            require(events.last?.0 == .playPause, "lifecycle/rotation/VoiceOver notification leaked delayed work")
        }
    }
    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
    private func button(_ id: String, in window: UIWindow? = nil) -> UIButton {
        guard let root = (window ?? owner.panelWindow)?.rootViewController?.view,
              let button = descendants(root).compactMap({ $0 as? UIButton }).first(where: { $0.accessibilityIdentifier == id }) else {
            finish("missing production control: " + id)
        }
        return button
    }
    private func settle(_ duration: TimeInterval = 0.25) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }
    private func testPanel(_ scene: UIWindowScene) {
        reset()
        let originalKey = scene.windows.first(where: { $0.isKeyWindow })
        let baseCount = scene.windows.count
        owner.trigger(selection([.flashlight], flow: false), in: scene, allowWhileLocked: false)
        guard let panelWindow = owner.panelWindow,
              let panel = panelWindow.rootViewController as? BottomActionPanelController else { finish("normal one-item panel missing") }
        require(panelWindow.windowScene === scene && panelWindow.screen === UIScreen.main, "panel must be scene-bound")
        require(!panelWindow.isHidden && !panelWindow.isKeyWindow && originalKey?.isKeyWindow == true, "panel must not steal key window")
        require(panelWindow.windowLevel.rawValue < UIWindow.Level.alert.rawValue && scene.windows.count == baseCount + 1, "unbounded/duplicate overlay")
        require(events.isEmpty, "one-item normal mode must not execute directly")
        let action = button("bottom.action.0")
        require(action.title(for: .normal) == "手电筒", "basic action label missing")
        owner.panelDidRequestDismissal(panel)
        require(owner.panelWindow === panelWindow && events.isEmpty, "forced delegate must not authorize a choice")
        action.isEnabled = false
        action.sendActions(for: .touchUpInside)
        require(owner.panelWindow === panelWindow && events.isEmpty, "disabled control dispatched")
        action.isEnabled = true
        action.tag = 99
        action.sendActions(for: .touchUpInside)
        require(owner.panelWindow === panelWindow && events.isEmpty, "tampered snapshot index dispatched")
        action.tag = 0
        require(action.titleLabel?.adjustsFontForContentSizeCategory == true, "action label must track Dynamic Type")
        let forged = UIButton(type: .system)
        forged.tag = 0
        _ = UIApplication.shared.sendAction(NSSelectorFromString("actionPressed:"), to: panel, from: forged, for: nil)
        require(owner.panelWindow === panelWindow && events.isEmpty, "foreign same-index control dispatched")
        owner.cancelPendingFlow()
        require(owner.panelWindow === panelWindow, "new Began must not hide an existing chooser")
        owner.trigger(selection([.lock], flow: false), in: scene, allowWhileLocked: false)
        require(owner.panelWindow == nil && panelWindow.rootViewController == nil && panel.delegate == nil,
                "normal trigger must toggle closed and release root/delegate")
        action.sendActions(for: .touchUpInside)
        settle()
        require(events.isEmpty, "stale retained button dispatched after toggle")
        var configured: [TapLockPreferences.Action] = [.playPause, .previousTrack, .nextTrack]
        owner.trigger(selection(configured, flow: false), in: scene, allowWhileLocked: false)
        configured[1] = .lock
        settle(0.03)
        let selected = button("bottom.action.1")
        selected.sendActions(for: .touchUpInside)
        selected.sendActions(for: .touchUpInside)
        require(events.isEmpty, "selection must wait for dismissal")
        settle()
        require(events.map { $0.0 } == [.previousTrack] && owner.panelWindow == nil, "selection must execute exactly one immutable index")
        require(scene.windows.first(where: { $0.isKeyWindow }) === originalKey, "other windows were mutated")
        reset()
        owner.trigger(selection([.lock], flow: false), in: scene, allowWhileLocked: false)
        let outside = button("bottom.outside")
        guard let showing = owner.panelWindow else { finish("missing outside panel") }
        let outsidePoint = CGPoint(x: showing.bounds.midX, y: showing.safeAreaInsets.top + 2)
        require(showing.hitTest(outsidePoint, with: nil) === outside, "outside point must dismiss, not leak through while shown")
        outside.sendActions(for: .touchUpInside)
        settle()
        require(owner.panelWindow == nil && events.isEmpty, "outside close must execute nothing")
        owner.trigger(selection([.lock], flow: false), in: scene, allowWhileLocked: false)
        button("bottom.cancel").sendActions(for: .touchUpInside)
        settle()
        require(owner.panelWindow == nil && events.isEmpty, "cancel must execute nothing")
        owner.trigger(selection([.lock], flow: false), in: scene, allowWhileLocked: false)
        settle(0.03)
        button("bottom.action.0").sendActions(for: .touchUpInside)
        owner.cancelAll()
        owner.trigger(selection([.flashlight], flow: false), in: scene, allowWhileLocked: false)
        let replacement = owner.panelWindow
        settle()
        require(events.isEmpty && replacement != nil && owner.panelWindow === replacement,
                "old animation completion dispatched/destroyed a replacement panel")
        owner.trigger(selection([.playPause, .nextTrack]), in: scene, allowWhileLocked: false)
        require(owner.panelWindow == nil && events.map { $0.0 } == [.playPause], "flow must close chooser before immediate invocation")
        clock.advance(to: 1)
        require(events.map { $0.0 } == [.playPause, .nextTrack], "flow replacement from panel failed")
        reset()
        owner.trigger(selection([.playPause, .nextTrack]), in: scene, allowWhileLocked: false)
        owner.trigger(selection([.flashlight], flow: false), in: scene, allowWhileLocked: false)
        clock.advance(to: 1)
        require(owner.panelWindow != nil && events.map { $0.0 } == [.playPause], "normal panel must interrupt an active flow")
        owner.cancelAll()
        require(owner.panelWindow == nil, "cancelAll must remove touch shield")
        let passthrough = BottomActionPanelWindow(windowScene: scene)
        passthrough.rootViewController = UIViewController()
        passthrough.isHidden = false
        require(passthrough.hitTest(CGPoint(x: 10, y: 10), with: nil) == nil, "absent-panel overlay must be touch pass-through")
        passthrough.isHidden = true
        passthrough.rootViewController = nil
    }
    private func testRejections(_ scene: UIWindowScene) {
        for flow in [false, true] {
            for input in [selection([], flow: flow), selection([.unavailable], flow: flow),
                          selection([.openApp("bad identifier")], flow: flow),
                          selection([.playPause, .unavailable], flow: flow),
                          selection([.flashlight], flow: flow, enabled: false)] {
                reset()
                owner.trigger(input, in: scene, allowWhileLocked: false)
                clock.advance(to: 2)
                require(owner.panelWindow == nil && events.isEmpty && clock.jobs.isEmpty,
                        "empty/invalid/disabled list must reject without fallback")
            }
        }
        reset()
        allowed = false
        owner.trigger(selection([.lock], flow: false), in: scene, allowWhileLocked: false)
        require(owner.panelWindow == nil && events.isEmpty, "permission rejection created a panel")
        allowed = true
        owner.trigger(selection([.playPause, .nextTrack]), in: scene, allowWhileLocked: false)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        clock.advance(to: 1)
        require(events.map { $0.0 } == [.playPause], "suspension did not invalidate delayed work")
        reset()
        owner.trigger(selection([.lock], flow: false), in: scene, allowWhileLocked: false)
        NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)
        require(owner.panelWindow == nil && events.isEmpty, "rotation must release panel without action")
        reset()
        owner.trigger(selection([.lock], flow: false), in: scene, allowWhileLocked: false)
        allowed = false
        button("bottom.action.0").sendActions(for: .touchUpInside)
        settle()
        require(owner.panelWindow == nil && events.isEmpty, "selection-time permission change dispatched")
        reset()
        owner.trigger(selection([.lock], flow: false), in: scene, allowWhileLocked: false)
        settle(0.03)
        button("bottom.action.0").sendActions(for: .touchUpInside)
        allowed = false
        settle()
        require(owner.panelWindow == nil && events.isEmpty, "dismiss-completion permission change dispatched")
        reset()
        owner.trigger(selection([.openApp("com.example.Example")], flow: false), in: scene, allowWhileLocked: false)
        require(button("bottom.action.0").title(for: .normal) == "com.example.Example", "App label must use captured ID without LS lookup")
        owner.cancelAll()
        weak var released: UIWindow?
        autoreleasepool {
            owner.trigger(selection([.lock], flow: false), in: scene, allowWhileLocked: false)
            released = owner.panelWindow
            owner.cancelAll()
        }
        settle()
        require(released == nil, "dismissed overlay leaked window/root/closure ownership")
    }
    private func testOffMainAdmission(_ scene: UIWindowScene) {
        reset()
        let coordinator = owner!
        let input = selection([.lock], flow: false)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            coordinator.trigger(input, in: scene, allowWhileLocked: false)
            coordinator.cancelPendingFlow()
            coordinator.cancelAll()
            finished.signal()
        }
        require(finished.wait(timeout: .now() + 1) == .success, "off-main guards failed to return")
        require(events.isEmpty && owner.panelWindow == nil && clock.jobs.isEmpty, "off-main input touched panel/provider/scheduler")
        owner.trigger(input, in: scene, allowWhileLocked: false)
        let showing = owner.panelWindow
        DispatchQueue.global().async {
            coordinator.cancelAll()
            finished.signal()
        }
        require(finished.wait(timeout: .now() + 1) == .success && owner.panelWindow === showing,
                "off-main cancellation mutated live UIKit ownership")
        owner.cancelAll()
    }
    private func run(_ scene: UIWindowScene) {
        guard scene.activationState == .foregroundActive,
              UIApplication.shared.applicationState == .active else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.run(scene) }
            return
        }
        UIView.setAnimationsEnabled(true)
        owner = BottomActionCoordinator(io: .init(now: { [unowned self] in self.clock.now },
            schedule: { [unowned self] in self.clock.enqueue($0, $1) },
            invoke: { [unowned self] action in
                self.require(Thread.isMainThread, "provider invoked off-main")
                self.events.append((action, self.clock.now))
                let reentry = self.onInvoke
                self.onInvoke = nil
                reentry?()
            }, permission: { [unowned self] _, allowWhileLocked in
                self.permissions.append(allowWhileLocked)
                return self.allowed
            }))
        testFlow(scene)
        testPanel(scene)
        testRejections(scene)
        testOffMainAdmission(scene)
        owner.cancelAll()
        finish()
    }
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "BottomActions", sessionRole: connectingSceneSession.role)
        config.delegateClass = BottomActionsApp.self
        return config
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { finish("missing UIWindowScene") }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .systemBackground
        self.window = window
        window.makeKeyAndVisible()
        DispatchQueue.main.async { self.run(scene) }
    }
}
