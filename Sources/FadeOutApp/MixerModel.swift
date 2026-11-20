import AppKit
import Combine
import Darwin
import FadeOutAudio
import OSLog
import ServiceManagement

struct AppRow: Identifiable {
    let id: String
    let bundleID: String
    let name: String
    let icon: NSImage
    let sortPriority: AppSortPriority
    var volume: Double
}

@MainActor
final class MixerModel: ObservableObject {
    private let logger = Logger(subsystem: "com.howldev.fadeout", category: "MixerModel")
    @Published private(set) var rows: [AppRow] = []
    @Published private(set) var devices: [OutputDevice] = []
    @Published var masterVolume: Double
    @Published var selectedOutputUID: String
    @Published var captureAcknowledged: Bool
    @Published var launchAtLogin = false
    @Published var errorMessage: String?

    private let engine: AudioControlling
    private let monitor: AppMonitor
    private let settings: SettingsStore
    private var rememberedUnmuted: [String: Double] = [:]
    private var observedProcesses: [AudioProcess] = []
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var followsSystemOutput: Bool
    private var didRequestCaptureThisLaunch = false
    private var captureAccessRequest: AudioHardwareSnapshot.CaptureAccessRequest?

    var hasReducedSound: Bool { masterVolume < 0.999 || rows.contains { $0.volume < 0.999 } }

    init(engine: AudioControlling = CoreAudioEngine(), monitor: AppMonitor = AppMonitor(),
         settings: SettingsStore = SettingsStore(), previewRows: [AppRow]? = nil) {
        self.engine = engine
        self.monitor = monitor
        self.settings = settings
        masterVolume = settings.masterVolume
        // Always follow the Mac's current system output. Fade Out no longer retains or
        // presents a separate routing choice.
        selectedOutputUID = ""
        followsSystemOutput = true
        settings.outputDeviceUID = nil
        captureAcknowledged = UserDefaults(suiteName: "com.howldev.fadeout")?.bool(forKey: "captureExplained") ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if let previewRows {
            rows = previewRows
            captureAcknowledged = true
            return
        }
        monitor.onChange = { [weak self] processes, devices, defaultID in
            Task { @MainActor [weak self] in self?.update(processes, devices: devices, defaultID: defaultID) }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        lifecycleObservers.append(workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildRows() }
        })
        lifecycleObservers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildRows() }
        })
        lifecycleObservers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.engine.stopAll() }
        })
        lifecycleObservers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.monitor.stop(); self?.monitor.start() }
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        })
        // Populate the menu immediately; HAL discovery is independent and may complete later.
        rebuildRows()
        monitor.start()
    }

    private func update(_ processes: [AudioProcess], devices: [OutputDevice], defaultID: UInt32?) {
        let audible = processes.filter { process in
            process.bundleID != "com.howldev.fadeout" && process.pid != ProcessInfo.processInfo.processIdentifier
        }
        let removed = Set(observedProcesses.map(\.id)).subtracting(audible.map(\.id))
        for id in removed { engine.remove(processID: id) }
        observedProcesses = audible
        logger.info("HAL reports \(audible.count, privacy: .public) registered audio clients")
        if !audible.isEmpty { captureAccessRequest = nil }
        self.devices = devices
        if followsSystemOutput || selectedOutputUID.isEmpty || !devices.contains(where: { $0.uid == selectedOutputUID }) {
            selectedOutputUID = devices.first(where: { $0.id == defaultID })?.uid ?? devices.first?.uid ?? ""
        }
        rebuildRows()
        if hasReducedSound { requestCaptureAccessIfNeeded() }
        syncAudio()
    }

    private func rebuildRows() {
        let fallbackIcon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
                !$0.isTerminated &&
                $0.bundleIdentifier != "com.howldev.fadeout" &&
                $0.bundleIdentifier != nil
        }

        var visible: [String: AppRow] = [:]
        for process in observedProcesses {
            guard let identity = canonicalIdentity(for: process, among: runningApps),
                  !isExcludedFromMixer(identity.bundleID) else { continue }
            visible[identity.bundleID] = AppRow(
                id: identity.bundleID,
                bundleID: identity.bundleID,
                name: identity.name,
                icon: identity.app?.icon ?? fallbackIcon,
                sortPriority: AppSortPriority.classify(
                    bundleID: identity.bundleID,
                    name: identity.name,
                    categoryIdentifier: identity.app.flatMap(appCategoryIdentifier(for:))
                ),
                volume: settings.volume(for: identity.bundleID)
            )
        }

        rows = visible.values.sorted {
            if $0.sortPriority != $1.sortPriority { return $0.sortPriority < $1.sortPriority }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func canonicalIdentity(for process: AudioProcess, among apps: [NSRunningApplication])
        -> (bundleID: String, name: String, app: NSRunningApplication?)? {
        let directApp = NSRunningApplication(processIdentifier: process.pid)
        let ownerBundleID = owningApplicationBundleID(for: process.pid)
        let identifiers = [ownerBundleID, process.bundleID, directApp?.bundleIdentifier]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        let directName = directApp?.localizedName ?? ""
        let normalizedDirectName = directName.lowercased()

        // Safari's renderer can advertise its own bundle as if it were an application. It is
        // always controlled by the Safari row and must never appear as a separate channel.
        if normalizedDirectName.contains("safari graphics and media") ||
            process.bundleID.lowercased().contains("safari.graphics") {
            guard let safari = apps.first(where: { $0.bundleIdentifier == "com.apple.Safari" }) else {
                return nil
            }
            return ("com.apple.Safari", safari.localizedName ?? "Safari", safari)
        }

        // Fold helpers named "<App> Helper" or "<App> Graphics…" into their visible parent
        // before considering the helper's own exact bundle identifier.
        if let app = apps
            .filter({ candidate in
                guard candidate.activationPolicy == .regular,
                      let name = candidate.localizedName?.lowercased() else { return false }
                return normalizedDirectName.hasPrefix(name + " ")
            })
            .max(by: { ($0.localizedName?.count ?? 0) < ($1.localizedName?.count ?? 0) }),
           let bundleID = app.bundleIdentifier {
            return (bundleID, app.localizedName ?? bundleID, app)
        }

        // A browser can expose several audible renderer/GPU processes. Prefer the outer .app
        // bundle discovered from the executable path, then exact and reverse-DNS parent matches.
        for identifier in identifiers {
            if let app = apps.first(where: { $0.bundleIdentifier == identifier }),
               let bundleID = app.bundleIdentifier {
                return (bundleID, app.localizedName ?? bundleID, app)
            }
        }
        for identifier in identifiers {
            if let app = apps
                .filter({ candidate in
                    guard let bundleID = candidate.bundleIdentifier else { return false }
                    return identifier.hasPrefix(bundleID + ".")
                })
                .max(by: { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }),
               let bundleID = app.bundleIdentifier {
                return (bundleID, app.localizedName ?? bundleID, app)
            }
        }

        // Unresolved renderer/helper processes should never become duplicate mixer rows.
        let helperIdentity = (directName + " " + process.bundleID).lowercased()
        let helperMarkers = ["graphics and media", " helper", "renderer", "web content", "gpu process"]
        if helperMarkers.contains(where: helperIdentity.contains) { return nil }

        // A HAL client that cannot be resolved to a regular .app is a daemon/process, not a
        // mixer channel (for example assistantd or com.apple.accessibility.heard).
        return nil
    }

    private func isExcludedFromMixer(_ bundleID: String) -> Bool {
        let excluded: Set<String> = [
            "com.apple.finder",
            "com.apple.ActivityMonitor",
            "com.howldev.fadeout"
        ]
        return excluded.contains(bundleID)
    }

    private func appCategoryIdentifier(for app: NSRunningApplication) -> String? {
        guard let url = app.bundleURL, let bundle = Bundle(url: url) else { return nil }
        return bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
    }

    private func appBundleID(for process: AudioProcess, among bundleIDs: [String]? = nil) -> String? {
        let candidates = bundleIDs ?? rows.map(\.bundleID)
        let runningBundleID = NSRunningApplication(processIdentifier: process.pid)?.bundleIdentifier
        let owningBundleID = owningApplicationBundleID(for: process.pid)
        for identifier in [owningBundleID, process.bundleID, runningBundleID].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if candidates.contains(identifier) { return identifier }
            if let owner = candidates
                .filter({ identifier.hasPrefix($0 + ".") })
                .max(by: { $0.count < $1.count }) {
                return owner
            }
        }
        return nil
    }

    private func owningApplicationBundleID(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let components = String(cString: buffer).split(separator: "/", omittingEmptySubsequences: true)
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let bundlePath = "/" + components[...appIndex].joined(separator: "/")
        return Bundle(path: bundlePath)?.bundleIdentifier
    }

    func acknowledgeCapture() {
        captureAcknowledged = true
        UserDefaults(suiteName: "com.howldev.fadeout")?.set(true, forKey: "captureExplained")
        requestCaptureAccessIfNeeded()
        syncAudio()
    }

    func setMaster(_ value: Double) {
        masterVolume = value
        settings.masterVolume = value
        beginCaptureIfNeeded(for: value)
        syncAudio()
    }

    func setVolume(_ value: Double, for row: AppRow) {
        settings.setVolume(value, for: row.bundleID)
        if value > 0 { rememberedUnmuted[row.bundleID] = value }
        for index in rows.indices where rows[index].bundleID == row.bundleID {
            rows[index].volume = value
        }
        beginCaptureIfNeeded(for: value)
        syncAudio()
    }

    func toggleMute(_ row: AppRow) {
        let newValue = row.volume == 0 ? rememberedUnmuted[row.bundleID] ?? 1 : 0
        if row.volume > 0 { rememberedUnmuted[row.bundleID] = row.volume }
        setVolume(newValue, for: row)
    }

    private func beginCaptureIfNeeded(for value: Double) {
        guard value < 0.999 else { return }
        if !captureAcknowledged {
            captureAcknowledged = true
            UserDefaults(suiteName: "com.howldev.fadeout")?.set(true, forKey: "captureExplained")
        }
        requestCaptureAccessIfNeeded()
    }

    private func requestCaptureAccessIfNeeded() {
        guard !didRequestCaptureThisLaunch else { return }
        didRequestCaptureThisLaunch = true
        do {
            captureAccessRequest = try AudioHardwareSnapshot.requestCaptureAccess()
            // TCC updates asynchronously after the user responds. Refresh both promptly and
            // once more after the permission sheet has had time to close.
            Task { @MainActor [weak self] in
                // The consent sheet is asynchronous and the user may take several seconds.
                // Refresh for a bounded period so the newly authorized process list is picked
                // up without requiring a manual app restart.
                for _ in 0..<30 {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self else { return }
                    self.monitor.refresh()
                    if !self.observedProcesses.isEmpty { return }
                }
            }
        } catch {
            errorMessage = "System Audio Recording is unavailable. Allow Fade Out in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen Fade Out."
        }
    }

    func chooseOutput(_ uid: String) {
        selectedOutputUID = uid
        followsSystemOutput = false
        settings.outputDeviceUID = uid
        engine.stopAll()
        syncAudio()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            errorMessage = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func syncAudio() {
        guard captureAcknowledged, let output = devices.first(where: { $0.uid == selectedOutputUID }) else {
            engine.stopAll()
            return
        }
        var firstError: String?
        var mappedCount = 0
        for process in observedProcesses {
            guard let bundleID = appBundleID(for: process),
                  let row = rows.first(where: { $0.bundleID == bundleID }) else { continue }
            mappedCount += 1
            do {
                try engine.setGain(Float(row.volume * masterVolume), for: process, output: output)
            } catch {
                engine.remove(processID: process.id)
                if firstError == nil { firstError = "\(row.name): \(error.localizedDescription)" }
            }
        }
        logger.info("Mapped \(mappedCount, privacy: .public) of \(self.observedProcesses.count, privacy: .public) active processes to app rows")
        errorMessage = firstError
    }

    func stop() {
        monitor.stop()
        engine.stopAll()
        for observer in lifecycleObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycleObservers.removeAll()
    }

    static func preview() -> MixerModel {
        let icon = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage()
        let rows = [
            AppRow(id: "com.example.music", bundleID: "com.example.music",
                   name: "Music", icon: icon, sortPriority: .music, volume: 0.64),
            AppRow(id: "com.example.browser", bundleID: "com.example.browser",
                   name: "Browser", icon: icon, sortPriority: .browser, volume: 1)
        ]
        return MixerModel(engine: PreviewAudioEngine(), previewRows: rows)
    }
}

private final class PreviewAudioEngine: AudioControlling {
    func setGain(_ gain: Float, for process: AudioProcess, output: OutputDevice) throws {}
    func remove(processID: UInt32) {}
    func stopAll() {}
}
