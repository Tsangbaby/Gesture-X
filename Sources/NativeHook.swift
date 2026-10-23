import UIKit
import ObjectiveC
import TapLockNativeRuntime

/// One process-lifetime native hook, preserving the predecessor exactly once.
enum TapLockRuntime {
    private typealias DidMoveCall = @convention(c) (UIView, Selector) -> Void
    private static var original: IMP?
    private static var started = false

    private static let didMove: DidMoveCall = { view, selector in
        guard let original = original else { return }
        let previous = unsafeBitCast(original, to: DidMoveCall.self)
        previous(view, selector)
        HomeDoubleTap.shared.attach(to: view)
    }

    static func activate() {
        guard Thread.isMainThread else { return }
        guard !started else { return }
        started = true
        if let type = NSClassFromString("SBIconListView") as? UIView.Type {
            let selector = NSSelectorFromString("didMoveToWindow")
            if let method = PrivateAPI.checkedMethod(in: type, selector: selector, returns: "v") {
                // Seed before installation; a backend must never expose a nil predecessor.
                original = method_getImplementation(method)
                MSHookMessageEx(type, selector, unsafeBitCast(didMove, to: IMP.self), &original)
            }
        }
        HomeDoubleTap.shared.start()
    }
}
