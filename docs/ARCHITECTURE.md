# Architecture and audio plan

Apple's [Core Audio process tap sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) and [tap description reference](https://developer.apple.com/documentation/coreaudio/catapdescription) informed this design.

1. `AppMonitor` watches the HAL process list, each process's `IsRunningOutput`, device list, and default output. It emits snapshots only after property changes.
2. `MixerModel` groups process objects by bundle ID for display. It saves volume per bundle ID and applies that level to every active process object in the group.
3. `CoreAudioEngine` creates a private `CATapDescription` for each adjusted process, with `mutedWhenTapped`, and a private aggregate device with the selected physical output as its clock source. The aggregate input contains the tap; the aggregate output points at the physical device.
4. The aggregate's IOProc runs in C. It copies Float32 samples into output buffers, accepting planar or interleaved channel layouts, and approaches an atomic target gain over about 128 frames. It never allocates, locks, logs, or invokes Swift.
5. A return to full effective volume destroys the IOProc, aggregate, and tap in reverse order. Changing device, sleep, and quit use the same cleanup path. Private aggregates also disappear when the process exits unexpectedly.

## Limits and risks

- Output and tap must have compatible sample rate, channel count, and Float32 PCM format. The engine rejects other combinations before starting. The IOProc leaves unsupported runtime layouts silent and records a mismatch flag. Device format coverage needs testing on physical hardware, including Bluetooth and multi-output setups.
- Muting the original process while replaying introduces at least one HAL buffer of latency. This may be noticeable for games or calls.
- macOS asks for System Audio Recording permission when the aggregate starts; this cannot be validated in a headless build.
- Some DRM-protected audio and apps using unusual routes may not appear or may not be capturable.
- There is no telemetry or periodic CPU work. The stated CPU and memory goals still need measurement on a real Mac with several taps.

## Verification

`FadeOutHarness` checks the gain ramp, settings persistence, and one-row-per-bundle state, and reports HAL discovery. Swift Testing covers the same independent logic. A manual release check must play audio in at least two apps, lower just one, mute and unmute, switch outputs, disconnect the output, sleep and wake, and confirm that 100% restores the normal route.
