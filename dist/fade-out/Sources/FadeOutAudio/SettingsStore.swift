import Foundation

public final class SettingsStore {
    private let defaults: UserDefaults
    private let volumesKey = "appVolumes"
    private let masterKey = "masterVolume"
    private let outputKey = "outputDeviceUID"

    public init(defaults: UserDefaults = UserDefaults(suiteName: "com.howldev.fadeout") ?? .standard) {
        self.defaults = defaults
    }

    public var masterVolume: Double {
        get { defaults.object(forKey: masterKey) as? Double ?? 1 }
        set { defaults.set(min(1, max(0, newValue)), forKey: masterKey) }
    }

    public var outputDeviceUID: String? {
        get { defaults.string(forKey: outputKey) }
        set { defaults.set(newValue, forKey: outputKey) }
    }

    public func volume(for bundleID: String) -> Double {
        (defaults.dictionary(forKey: volumesKey)?[bundleID] as? Double) ?? 1
    }

    public func setVolume(_ volume: Double, for bundleID: String) {
        var volumes = defaults.dictionary(forKey: volumesKey) ?? [:]
        let bounded = min(1, max(0, volume))
        if bounded == 1 { volumes.removeValue(forKey: bundleID) }
        else { volumes[bundleID] = bounded }
        defaults.set(volumes, forKey: volumesKey)
    }
}
