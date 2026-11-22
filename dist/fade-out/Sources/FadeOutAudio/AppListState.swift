import Foundation

public enum AppListState {
    // One row per app, even if HAL reports several audio clients for the same bundle.
    public static func visible(_ processes: [AudioProcess], excluding ownBundleID: String) -> [AudioProcess] {
        var seen = Set<String>()
        return processes
            .filter { $0.bundleID != ownBundleID && seen.insert($0.bundleID).inserted }
            .sorted { $0.bundleID.localizedStandardCompare($1.bundleID) == .orderedAscending }
    }
}
