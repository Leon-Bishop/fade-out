import Foundation

public enum AppVisibilityPolicy {
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.activitymonitor",
        "com.apple.automator",
        "com.apple.console",
        "com.apple.diskutility",
        "com.apple.finder",
        "com.apple.fontbook",
        "com.apple.scripteditor2",
        "com.apple.systempreferences",
        "com.apple.systemprofiler",
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.microsoft.vscode",
        "com.todesktop.230313mzl4w4u92",
        "dev.warp.warp-stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "org.wezfurlong.wezterm"
    ]

    private static let excludedNameMarkers = [
        "activity monitor",
        "disk utility",
        "github copilot",
        "system information"
    ]

    /// Music, browsers, communication, games, and media stay available while paused. General
    /// applications such as Mail are transient and appear only while Core Audio reports output.
    public static func shouldShow(bundleID: String, name: String,
                                  categoryIdentifier: String?,
                                  isActivelyProducingSound: Bool = true) -> Bool {
        let bundle = bundleID.lowercased()
        let normalizedName = name.lowercased()
        let category = categoryIdentifier?.lowercased() ?? ""

        if excludedBundleIDs.contains(bundle) { return false }
        if bundle.hasPrefix("com.apple.dt.") { return false }
        if category.contains("developer-tools") { return false }
        if excludedNameMarkers.contains(where: normalizedName.contains) { return false }

        if AppSortPriority.classify(bundleID: bundleID, name: name,
                                    categoryIdentifier: categoryIdentifier) != .other {
            return true
        }
        let persistentCategories = ["games", "video", "entertainment", "music", "audio"]
        if persistentCategories.contains(where: category.contains) { return true }
        return isActivelyProducingSound
    }
}
