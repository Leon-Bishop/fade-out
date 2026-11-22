import Foundation

/// Known desktop music players whose identity should not depend on Dock visibility or current
/// playback. Bundle IDs are preferred; exact display names cover players whose identifiers vary
/// between App Store, direct-download, and regional builds.
public enum MusicAppDirectory {
    public static let bundleIDs: Set<String> = [
        "com.apple.music",
        "com.amazon.music",
        "com.audirvana.audirvana",
        "com.colliderli.iina",
        "com.coppertino.vox",
        "com.deezer.deezer",
        "com.kv.aural",
        "com.plexamp.plexamp",
        "com.qobuz.desktop",
        "com.roon.roon",
        "com.spotify.client",
        "com.tidal.desktop",
        "org.videolan.vlc"
    ]

    public static let displayNames: Set<String> = [
        "amazon music",
        "audirvana",
        "aural",
        "clementine",
        "cog",
        "colibri",
        "deezer",
        "doppler",
        "elmedia player",
        "fidelia",
        "foobar2000",
        "iina",
        "music",
        "musicbee",
        "pine player",
        "plexamp",
        "qobuz",
        "roon",
        "roon arc",
        "soundcloud",
        "spotify",
        "strawberry",
        "swinsian",
        "tidal",
        "vlc",
        "vox",
        "winamp",
        "youtube music"
    ]

    public static func contains(bundleID: String, name: String) -> Bool {
        let normalizedBundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bundleIDs.contains(normalizedBundleID) || displayNames.contains(normalizedName)
    }
}
