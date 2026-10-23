import UIKit
import ObjectiveC

/// Per-settings-controller icon cache; never part of the SpringBoard target.
final class ApplicationIcons {
    private var cache: [String: UIImage] = [:]
    private var unavailable = Set<String>()

    func image(identifier: String) -> UIImage? {
        guard Thread.isMainThread, TapLockPreferences.validBundleIdentifier(identifier) else { return nil }
        if let image = cache[identifier] { return image }
        if unavailable.contains(identifier) { return nil }
        let image = Self.normalized(Self.load(identifier: identifier)) ??
            Self.normalized(UIImage(systemName: "app.dashed")?
                .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal))
        if let image = image { cache[identifier] = image }
        else { unavailable.insert(identifier) }
        return image
    }

    static func load(identifier: String) -> UIImage? {
        let selector = NSSelectorFromString("_applicationIconImageForBundleIdentifier:format:scale:")
        guard Thread.isMainThread, TapLockPreferences.validBundleIdentifier(identifier),
              let metaclass = object_getClass(UIImage.self),
              let method = PrivateAPI.checkedMethod(in: metaclass, selector: selector,
                                                    returns: "@", arguments: ["@", "i", "d"]) else { return nil }
        // The iOS 15 declaration uses int, not NSInteger/NSUInteger, for format.
        typealias Load = @convention(c) (AnyObject, Selector, NSString, Int32, CGFloat) -> Unmanaged<AnyObject>?
        let invoke = unsafeBitCast(method_getImplementation(method), to: Load.self)
        return invoke(UIImage.self as AnyObject, selector, identifier as NSString, 0,
                      UIScreen.main.scale)?.takeUnretainedValue() as? UIImage
    }

    static func normalized(_ source: UIImage?) -> UIImage? {
        guard let source = source, source.size.width.isFinite, source.size.height.isFinite,
              source.size.width > 0, source.size.height > 0 else { return nil }
        let canvas = CGSize(width: 32, height: 32)
        let factor = min(canvas.width / source.size.width, canvas.height / source.size.height)
        let fitted = CGSize(width: source.size.width * factor, height: source.size.height * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            source.draw(in: CGRect(x: (canvas.width - fitted.width) / 2,
                                   y: (canvas.height - fitted.height) / 2,
                                   width: fitted.width, height: fitted.height))
        }.withRenderingMode(.alwaysOriginal)
    }
}
