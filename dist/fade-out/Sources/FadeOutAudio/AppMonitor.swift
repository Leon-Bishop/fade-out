import CoreAudio
import Foundation

// HAL property listeners wake the UI only when a process or output device changes.
// No timer runs while the menu is closed or the system is silent.
public final class AppMonitor {
    public var onChange: (([AudioProcess], [OutputDevice], AudioObjectID?) -> Void)?

    private struct Registration {
        let object: AudioObjectID
        let selector: AudioObjectPropertySelector
        let block: AudioObjectPropertyListenerBlock
    }
    private var registrations: [Registration] = []
    private var watchedProcesses: Set<AudioObjectID> = []
    private let listenerQueue = DispatchQueue(label: "com.howldev.fadeout.monitor")

    public init() {}

    public func start() {
        guard registrations.isEmpty else { return }
        listen(on: HAL.system, for: kAudioHardwarePropertyProcessObjectList)
        listen(on: HAL.system, for: kAudioHardwarePropertyDevices)
        listen(on: HAL.system, for: kAudioHardwarePropertyDefaultOutputDevice)
        refresh()
    }

    public func stop() {
        for registration in registrations {
            var address = HAL.address(registration.selector)
            AudioObjectRemovePropertyListenerBlock(registration.object, &address, listenerQueue, registration.block)
        }
        registrations.removeAll()
        watchedProcesses.removeAll()
    }

    private func listen(on object: AudioObjectID, for selector: AudioObjectPropertySelector) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        var address = HAL.address(selector)
        guard AudioObjectAddPropertyListenerBlock(object, &address, listenerQueue, block) == noErr else { return }
        registrations.append(Registration(object: object, selector: selector, block: block))
    }

    public func refresh() {
        let allIDs = Set((try? HAL.ids(HAL.system, kAudioHardwarePropertyProcessObjectList)) ?? [])
        for id in allIDs.subtracting(watchedProcesses) {
            // HAL reports process IO lifecycle changes through IsRunning. Registering for
            // IsRunningOutput succeeds, but it does not reliably emit notifications when
            // playback begins, so rows discovered through NSWorkspace never reached the engine.
            listen(on: id, for: kAudioProcessPropertyIsRunning)
        }
        for id in watchedProcesses.subtracting(allIDs) {
            if let index = registrations.firstIndex(where: { $0.object == id }) {
                let registration = registrations.remove(at: index)
                var address = HAL.address(registration.selector)
                AudioObjectRemovePropertyListenerBlock(id, &address, listenerQueue, registration.block)
            }
        }
        watchedProcesses = allIDs
        onChange?(AudioHardwareSnapshot.processes(), AudioHardwareSnapshot.outputDevices(),
                  AudioHardwareSnapshot.defaultOutputID())
    }

    deinit { stop() }
}
