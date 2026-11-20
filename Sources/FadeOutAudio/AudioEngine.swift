import CoreAudio
import FadeOutDSP
import Foundation
import OSLog

public struct AudioProcess: Identifiable, Equatable {
    public let id: AudioObjectID
    public let pid: pid_t
    public let bundleID: String

    public init(id: AudioObjectID, pid: pid_t, bundleID: String) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
    }
}

public struct OutputDevice: Identifiable, Equatable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String

    public init(id: AudioObjectID, uid: String, name: String) {
        self.id = id
        self.uid = uid
        self.name = name
    }
}

public protocol AudioControlling: AnyObject {
    func setGain(_ gain: Float, for process: AudioProcess, output: OutputDevice) throws
    func remove(processID: AudioObjectID)
    func stopAll()
}

public enum AudioEngineError: LocalizedError {
    case status(String, OSStatus)
    case missingProperty(String)
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case let .status(operation, code): return "\(operation) failed (Core Audio \(code))."
        case let .missingProperty(name): return "The \(name) audio property is unavailable."
        case .unsupportedFormat: return "This output format is not supported for live mixing."
        }
    }
}

enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw AudioEngineError.status(operation, status) }
    }

    static func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                          as type: T.Type = T.self) throws -> T {
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size,
                                                       alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer), "Read property")
        guard size == MemoryLayout<T>.size else { throw AudioEngineError.missingProperty("requested") }
        return pointer.load(as: T.self)
    }

    static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), "Read property size")
        guard size > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try values.withUnsafeMutableBytes { bytes in
            try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, bytes.baseAddress!), "Read object list")
        }
        return values
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        try withUnsafeMutablePointer(to: &value) { pointer in
            try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer), "Read string property")
        }
        guard let value else { throw AudioEngineError.missingProperty("string") }
        return value as String
    }

    static func hasOutput(_ device: AudioObjectID) -> Bool {
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return false }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, memory) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(
            memory.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.contains { $0.mNumberChannels > 0 }
    }

    static func bufferCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, memory) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).count
    }
}

public enum AudioHardwareSnapshot {
    public final class CaptureAccessRequest {
        private let tapID: AudioObjectID
        private let aggregateID: AudioObjectID
        private let ioProc: AudioDeviceIOProcID

        fileprivate init() throws {
            var tap = AudioObjectID(kAudioObjectUnknown)
            var aggregate = AudioObjectID(kAudioObjectUnknown)
            var callback: AudioDeviceIOProcID?
            do {
                let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
                description.name = "Fade Out Permission Check"
                description.isPrivate = true
                description.muteBehavior = .unmuted
                try HAL.check(AudioHardwareCreateProcessTap(description, &tap), "Create permission tap")
                let tapUID = try HAL.string(tap, kAudioTapPropertyUID)
                let config: [String: Any] = [
                    kAudioAggregateDeviceUIDKey: "com.howldev.fadeout.permission.\(UUID().uuidString)",
                    kAudioAggregateDeviceNameKey: "Fade Out Permission Check",
                    kAudioAggregateDeviceIsPrivateKey: true,
                    kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID]]
                ]
                try HAL.check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate),
                              "Create permission aggregate")
                try HAL.check(AudioDeviceCreateIOProcID(aggregate, FONoopIOProc, nil, &callback),
                              "Create permission callback")
                guard let callback else { throw AudioEngineError.missingProperty("permission callback") }
                try HAL.check(AudioDeviceStart(aggregate, callback), "Start System Audio Recording request")
                tapID = tap
                aggregateID = aggregate
                ioProc = callback
            } catch {
                if let callback { AudioDeviceDestroyIOProcID(aggregate, callback) }
                if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
                if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
                throw error
            }
        }

        deinit {
            AudioDeviceStop(aggregateID, ioProc)
            AudioDeviceDestroyIOProcID(aggregateID, ioProc)
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
        }
    }

    /// macOS displays its consent dialog only after IO starts on an aggregate device
    /// containing a tap. Enumerating processes or creating a tap alone only preflights TCC.
    public static func requestCaptureAccess() throws -> CaptureAccessRequest {
        try CaptureAccessRequest()
    }

    public static func processes() -> [AudioProcess] {
        (try? HAL.ids(HAL.system, kAudioHardwarePropertyProcessObjectList))?.compactMap { id in
            // Always pass the concrete type when this generic read is wrapped in `try?`.
            // Otherwise Swift can infer T as Optional<UInt32>/Optional<pid_t>, ask HAL for
            // the wrong byte count, and silently turn every process into nil.
            // Keep every registered Core Audio client, including paused/silent clients. The
            // IsRunningOutput property only means "playing right now" and made useful faders
            // disappear whenever playback paused.
            guard let pid = try? HAL.scalar(id, kAudioProcessPropertyPID,
                                            as: pid_t.self) else { return nil }
            // Some browser and media helper processes don't publish a HAL bundle ID. The PID still
            // identifies their NSRunningApplication, so retain them and resolve the owning app in UI state.
            let bundle = (try? HAL.string(id, kAudioProcessPropertyBundleID)) ?? ""
            return AudioProcess(id: id, pid: pid, bundleID: bundle)
        } ?? []
    }

    public static func outputDevices() -> [OutputDevice] {
        ((try? HAL.ids(HAL.system, kAudioHardwarePropertyDevices)) ?? []).compactMap { id in
            guard HAL.hasOutput(id), let uid = try? HAL.string(id, kAudioDevicePropertyDeviceUID),
                  let name = try? HAL.string(id, kAudioObjectPropertyName) else { return nil }
            return OutputDevice(id: id, uid: uid, name: name)
        }
    }

    public static func defaultOutputID() -> AudioObjectID? {
        try? HAL.scalar(HAL.system, kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self)
    }
}

// Each adjusted process gets its own private tap and aggregate. A 100% process has neither.
public final class CoreAudioEngine: AudioControlling {
    private let logger = Logger(subsystem: "com.howldev.fadeout", category: "AudioEngine")
    private struct Session {
        let processID: AudioObjectID
        let outputID: AudioObjectID
        let tapID: AudioObjectID
        let aggregateID: AudioObjectID
        let ioProc: AudioDeviceIOProcID
        let gain: UnsafeMutablePointer<FOGainState>
    }

    private var sessions: [AudioObjectID: Session] = [:]

    public init() {}

    public func setGain(_ gain: Float, for process: AudioProcess, output: OutputDevice) throws {
        if gain >= 0.9999 {
            remove(processID: process.id)
            return
        }
        if let session = sessions[process.id], session.outputID == output.id {
            if FOGainHasFormatMismatch(session.gain) {
                remove(processID: process.id)
                throw AudioEngineError.unsupportedFormat
            }
            FOGainSetTarget(session.gain, gain)
            return
        }
        remove(processID: process.id)
        let state = UnsafeMutablePointer<FOGainState>.allocate(capacity: 1)
        FOGainInit(state, gain)
        // Use the HAL's stereo mixdown. Browser and media helpers may publish multichannel
        // streams even when the selected speakers are stereo; forwarding their native format
        // makes the aggregate reject or silently bypass the route.
        let description = CATapDescription(stereoMixdownOfProcesses: [process.id])
        description.name = "Fade Out \(process.bundleID)"
        description.isPrivate = true
        description.muteBehavior = .muted
        var tap = AudioObjectID(kAudioObjectUnknown)
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        var ioProc: AudioDeviceIOProcID?
        do {
            try HAL.check(AudioHardwareCreateProcessTap(description, &tap), "Create process tap")
            let tapUID = try HAL.string(tap, kAudioTapPropertyUID)
            let config: [String: Any] = [
                kAudioAggregateDeviceUIDKey: "com.howldev.fadeout.\(UUID().uuidString)",
                kAudioAggregateDeviceNameKey: "Fade Out Mix",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: output.uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            try HAL.check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "Create aggregate device")
            let formats = try validatedFormats(aggregate, tap: tap)
            let inputOffset = HAL.bufferCount(output.id, scope: kAudioDevicePropertyScopeInput)
            FOGainConfigure(state, UInt32(inputOffset), formats.input.mChannelsPerFrame,
                            formats.input.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0,
                            formats.output.mChannelsPerFrame,
                            formats.output.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0)
            try HAL.check(AudioDeviceCreateIOProcID(aggregate, FOGainIOProc, state, &ioProc), "Create audio callback")
            try HAL.check(AudioDeviceStart(aggregate, ioProc), "Start audio")
            guard let ioProc else { throw AudioEngineError.missingProperty("audio callback") }
            sessions[process.id] = Session(processID: process.id, outputID: output.id, tapID: tap,
                                           aggregateID: aggregate, ioProc: ioProc, gain: state)
            logger.info("Started fader session for process \(process.id, privacy: .public) on output \(output.name, privacy: .public), input offset \(inputOffset, privacy: .public), \(formats.input.mChannelsPerFrame, privacy: .public)→\(formats.output.mChannelsPerFrame, privacy: .public) channels")
        } catch {
            logger.error("Fader session failed for process \(process.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if let ioProc { AudioDeviceDestroyIOProcID(aggregate, ioProc) }
            if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
            if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
            state.deallocate()
            throw error
        }
    }

    private func validatedFormats(_ device: AudioObjectID, tap: AudioObjectID)
        throws -> (input: AudioStreamBasicDescription, output: AudioStreamBasicDescription) {
        guard let outputStream = try HAL.ids(device, kAudioDevicePropertyStreams,
                                            scope: kAudioDevicePropertyScopeOutput).first else {
            throw AudioEngineError.unsupportedFormat
        }
        let input: AudioStreamBasicDescription = try HAL.scalar(tap, kAudioTapPropertyFormat)
        let output: AudioStreamBasicDescription = try HAL.scalar(outputStream, kAudioStreamPropertyVirtualFormat)
        guard input.mFormatID == kAudioFormatLinearPCM, output.mFormatID == kAudioFormatLinearPCM,
              input.mBitsPerChannel == 32, output.mBitsPerChannel == 32,
              input.mChannelsPerFrame > 0, output.mChannelsPerFrame > 0,
              input.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              output.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            throw AudioEngineError.unsupportedFormat
        }
        return (input, output)
    }

    public func remove(processID: AudioObjectID) {
        guard let session = sessions.removeValue(forKey: processID) else { return }
        AudioDeviceStop(session.aggregateID, session.ioProc)
        AudioDeviceDestroyIOProcID(session.aggregateID, session.ioProc)
        AudioHardwareDestroyAggregateDevice(session.aggregateID)
        AudioHardwareDestroyProcessTap(session.tapID)
        session.gain.deallocate()
    }

    public func stopAll() {
        for id in Array(sessions.keys) { remove(processID: id) }
    }

    deinit { stopAll() }
}
