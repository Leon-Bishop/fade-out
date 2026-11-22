import FadeOutAudio
import FadeOutDSP
import Foundation
import CoreAudio

// A no-permission smoke test for the DSP path and HAL process discovery.
// Live routing must be checked in the signed app so macOS can show its permission prompt.
let state = UnsafeMutablePointer<FOGainState>.allocate(capacity: 1)
defer { state.deallocate() }
FOGainInit(state, 1)
FOGainSetTarget(state, 0)
let input = [Float](repeating: 1, count: 1_024)
var output = [Float](repeating: 0, count: input.count)
input.withUnsafeBufferPointer { source in
    output.withUnsafeMutableBufferPointer { destination in
        FOGainProcess(state, source.baseAddress!, destination.baseAddress!, 512, 2)
    }
}
guard output[0] > output[1_022], output[1_022] < 0.02 else {
    fatalError("Gain ramp smoke test failed")
}
print("Gain ramp: passed")
let suite = "com.howldev.fadeout.harness.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
let settings = SettingsStore(defaults: defaults)
settings.setVolume(0.42, for: "com.example.music")
guard SettingsStore(defaults: defaults).volume(for: "com.example.music") == 0.42 else {
    fatalError("Settings round-trip failed")
}
defaults.removePersistentDomain(forName: suite)
let list = [AudioProcess(id: 1, pid: 1, bundleID: "com.example.music"),
            AudioProcess(id: 2, pid: 2, bundleID: "com.example.music")]
guard AppListState.visible(list, excluding: "com.howldev.fadeout").count == 1 else {
    fatalError("App list grouping failed")
}
print("Settings and app grouping: passed")
print("Active audio processes: \(AudioHardwareSnapshot.processes().count)")
print("Output devices: \(AudioHardwareSnapshot.outputDevices().count)")
var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size)
print("HAL device-list status: \(status), bytes: \(size)")
