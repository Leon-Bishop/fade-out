import Foundation

public enum AppSortPriority: Int, Comparable, Sendable {
    case music = 0
    case browser = 1
    case communication = 2
    case other = 3

    public static func < (lhs: AppSortPriority, rhs: AppSortPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func classify(bundleID: String, name: String,
                                categoryIdentifier: String? = nil) -> AppSortPriority {
        let identity = "\(bundleID) \(name)".lowercased()
        let category = categoryIdentifier?.lowercased() ?? ""

        // Check music first so a YouTube Music or Spotify PWA ranks above its browser host.
        if category.contains("music") || category.contains("audio") || musicMarkers.contains(where: identity.contains) {
            return .music
        }
        if browserMarkers.contains(where: identity.contains) {
            return .browser
        }
        if category.contains("social-networking") || communicationMarkers.contains(where: identity.contains) {
            return .communication
        }
        return .other
    }

    private static let musicMarkers = [
        "spotify", "com.apple.music", "youtube music", "youtubemusic", "tidal", "deezer",
        "soundcloud", "amazon music", "qobuz", "plexamp", "audirvana", "roon", "foobar",
        "vlc", "iina", "musicbee", "winamp"
    ]

    private static let browserMarkers = [
        "com.apple.safari", "google chrome", "com.google.chrome", "firefox", "microsoft edge",
        "com.microsoft.edgemac", "brave browser", "com.brave.browser", "arc", "dia browser",
        "opera", "vivaldi", "orion", "zen browser", "duckduckgo"
    ]

    private static let communicationMarkers = [
        "discord", "slack", "microsoft teams", "com.microsoft.teams", "zoom", "facetime",
        "skype", "telegram", "whatsapp", "signal", "webex", "guilded", "element",
        "mumble", "teamspeak", "messenger", "chatgpt", "com.openai"
    ]
}
