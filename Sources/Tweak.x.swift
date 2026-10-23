import UIKit
import Orion

// Only this desktop class is hooked. Native touch/event delivery is untouched.
class IconListHook: ClassHook<UIView> {
    static var targetName: String { "SBIconListView" }

    static func hookWillActivate() -> Bool {
        guard let type = NSClassFromString("SBIconListView") as? UIView.Type else {
            return false
        }
        return PrivateAPI.checkedMethod(
            in: type, selector: NSSelectorFromString("didMoveToWindow"), returns: "v"
        ) != nil
    }

    func didMoveToWindow() {
        orig.didMoveToWindow()
        HomeDoubleTap.shared.attach(to: target)
    }
}

struct TapLockTweak: Tweak {
    func tweakDidActivate() {
        DispatchQueue.main.async {
            HomeDoubleTap.shared.start()
        }
    }

    // Orion's default terminates the process on hook errors. Never do that here.
    static func handleError(_ error: OrionHookError) {
        NSLog("[TapLock] Hook unavailable: %@", String(describing: error))
    }
}
