import AppKit

/// The logos of the services CopyTrading connects to, shipped with the app. Where they come from
/// and their licenses are in `Resources/BrandIcons/NOTICE.md`.
public enum BrandIcon {
    /// The logo for a service ("discord", "deepseek", …), or nil when the app has none.
    public static func image(named name: String) -> NSImage? {
        let file = "brand-\(name)"
        guard
            let url = Bundle.module.url(forResource: file, withExtension: "png")
                ?? Bundle.module.url(forResource: file, withExtension: "png", subdirectory: "BrandIcons")
        else { return nil }
        return NSImage(contentsOf: url)
    }
}
