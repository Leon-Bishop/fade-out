import Foundation
import FadeOutAudio
import FadeOutDSP
import Testing

struct FadeOutAudioTests {
    @Test func gainRampAndMute() {
        let state = UnsafeMutablePointer<FOGainState>.allocate(capacity: 1)
        defer { state.deallocate() }
        FOGainInit(state, 1)
        FOGainSetTarget(state, 0)
        let source = [Float](repeating: 1, count: 1_024)
        var result = [Float](repeating: 0, count: source.count)
        source.withUnsafeBufferPointer { src in
            result.withUnsafeMutableBufferPointer { dst in
                FOGainProcess(state, src.baseAddress!, dst.baseAddress!, 512, 2)
            }
        }
        #expect(result[0] > result[1_022])
        #expect(result[1_022] < 0.02)
    }

    @Test func settingsRestoreAndClamp() {
        let suite = "com.howldev.fadeout.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.setVolume(0.42, for: "com.example.music")
        settings.masterVolume = -1
        #expect(SettingsStore(defaults: defaults).volume(for: "com.example.music") == 0.42)
        #expect(settings.masterVolume == 0)
        settings.setVolume(1, for: "com.example.music")
        #expect(settings.volume(for: "com.example.music") == 1)
    }

    @Test func appListDeduplicatesAndExcludesSelf() {
        let processes = [
            AudioProcess(id: 1, pid: 11, bundleID: "com.example.music"),
            AudioProcess(id: 2, pid: 12, bundleID: "com.example.music"),
            AudioProcess(id: 3, pid: 13, bundleID: "com.howldev.fadeout")
        ]
        #expect(AppListState.visible(processes, excluding: "com.howldev.fadeout").map(\.id) == [1])
    }

    @Test func appPriorityOrdersMusicBrowserCommunicationThenOther() {
        #expect(AppSortPriority.classify(bundleID: "com.spotify.client", name: "Spotify") == .music)
        #expect(AppSortPriority.classify(bundleID: "com.kv.Aural", name: "Aural") == .music)
        #expect(AppSortPriority.classify(bundleID: "com.google.Chrome.app.pwa", name: "YouTube Music") == .music)
        #expect(AppSortPriority.classify(bundleID: "com.apple.Safari", name: "Safari") == .browser)
        #expect(AppSortPriority.classify(bundleID: "com.hnc.Discord", name: "Discord") == .communication)
        #expect(AppSortPriority.classify(bundleID: "com.apple.ActivityMonitor", name: "Activity Monitor") == .other)
        #expect(AppSortPriority.music < .browser)
        #expect(AppSortPriority.browser < .communication)
        #expect(AppSortPriority.communication < .other)
    }

    @Test func musicDirectoryRecognizesDockAndMenuBarPlayers() {
        #expect(MusicAppDirectory.contains(bundleID: "com.kv.Aural", name: "Aural"))
        #expect(MusicAppDirectory.contains(bundleID: "com.spotify.client", name: "Spotify"))
        #expect(!MusicAppDirectory.contains(
            bundleID: "com.spotify.client.helper", name: "Spotify Networking"))
        #expect(MusicAppDirectory.contains(bundleID: "unknown.direct.build", name: "Plexamp"))
        #expect(!MusicAppDirectory.contains(bundleID: "com.apple.Terminal", name: "Terminal"))
        #expect(AppSortPriority.classify(bundleID: "unknown.direct.build", name: "Aural") == .music)
    }

    @Test func visibilityExcludesNonAudioUtilitiesButKeepsSilentCapableApps() {
        #expect(!AppVisibilityPolicy.shouldShow(
            bundleID: "com.apple.Terminal", name: "Terminal",
            categoryIdentifier: "public.app-category.utilities"))
        #expect(!AppVisibilityPolicy.shouldShow(
            bundleID: "com.apple.dt.Xcode", name: "Xcode",
            categoryIdentifier: "public.app-category.developer-tools"))
        #expect(!AppVisibilityPolicy.shouldShow(
            bundleID: "com.github.Copilot", name: "GitHub Copilot",
            categoryIdentifier: "public.app-category.developer-tools"))
        #expect(AppVisibilityPolicy.shouldShow(
            bundleID: "com.spotify.client", name: "Spotify",
            categoryIdentifier: "public.app-category.music",
            isActivelyProducingSound: false))
        #expect(AppVisibilityPolicy.shouldShow(
            bundleID: "com.kv.Aural", name: "Aural",
            categoryIdentifier: nil,
            isActivelyProducingSound: false))
        #expect(AppVisibilityPolicy.shouldShow(
            bundleID: "com.apple.Safari", name: "Safari",
            categoryIdentifier: "public.app-category.productivity",
            isActivelyProducingSound: false))
        #expect(AppVisibilityPolicy.shouldShow(
            bundleID: "com.hnc.Discord", name: "Discord",
            categoryIdentifier: "public.app-category.social-networking",
            isActivelyProducingSound: false))
        #expect(!AppVisibilityPolicy.shouldShow(
            bundleID: "com.apple.mail", name: "Mail",
            categoryIdentifier: "public.app-category.productivity",
            isActivelyProducingSound: false))
        #expect(AppVisibilityPolicy.shouldShow(
            bundleID: "com.apple.mail", name: "Mail",
            categoryIdentifier: "public.app-category.productivity",
            isActivelyProducingSound: true))
    }
}
