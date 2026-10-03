//
//  AudioDevices.swift
//  Mesh Player
//
//  The Mac's real audio outputs from CoreAudio: speakers, headphones, AirPods and other
//  Bluetooth devices, USB and HDMI audio, and AirPlay speakers macOS has connected. Lists
//  update live as devices come and go.
//

import CoreAudio
import Foundation

enum AudioDevices {
    /// "Follow macOS": plays wherever the system's sound output is set.
    static let systemID = "system"

    /// Every visible device that can play sound, built-in first.
    static func outputs() -> [SwiftOutputDevice] {
        deviceIDs().compactMap(device(for:)).sorted { a, b in
            if (a.type == "built-in") != (b.type == "built-in") { return a.type == "built-in" }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// The device macOS currently plays through.
    static func defaultOutput() -> SwiftOutputDevice? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return nil }
        return device(for: id)
    }

    /// Calls `handler` on the main queue whenever devices are added or removed, or the
    /// system output changes. Keep the returned token alive.
    static func observe(_ handler: @escaping () -> Void) -> AnyObject {
        Observer(handler)
    }

    // MARK: CoreAudio

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func device(for id: AudioDeviceID) -> SwiftOutputDevice? {
        let channels = outputChannels(id)
        guard channels > 0, uint32(id, kAudioDevicePropertyIsHidden) != 1,
              let uid = string(id, kAudioDevicePropertyDeviceUID),
              let name = string(id, kAudioObjectPropertyName) else { return nil }
        let transport = uint32(id, kAudioDevicePropertyTransportType) ?? 0
        let rate = float64(id, kAudioDevicePropertyNominalSampleRate) ?? 0

        let type: String
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            type = name.localizedCaseInsensitiveContains("headphone") ? "wired-headphones" : "built-in"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            type = "bluetooth"
        case kAudioDeviceTransportTypeAirPlay:
            type = "airplay"
        case kAudioDeviceTransportTypeUSB:
            type = "usb"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            type = "display"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate:
            type = "virtual"
        default:
            type = "other"
        }
        let kind: String
        switch type {
        case "built-in": kind = "Built-in"
        case "wired-headphones": kind = "Headphones"
        case "bluetooth": kind = "Bluetooth"
        case "airplay": kind = "AirPlay"
        case "usb": kind = "USB"
        case "display": kind = "Display"
        case "virtual": kind = "Virtual"
        default: kind = "Output"
        }
        var details = [kind]
        if rate > 0 {
            let khz = rate / 1000
            details.append(khz == khz.rounded() ? "\(Int(khz)) kHz" : String(format: "%.1f kHz", khz))
        }
        if channels > 2 { details.append("\(channels) channels") }

        // Headphones Apple's spatial audio works with; multichannel outputs play Atmos beds as-is.
        let lowered = name.lowercased()
        let spatial = channels > 2 || lowered.contains("airpods") || lowered.contains("beats")
        return SwiftOutputDevice(id: uid, name: name, type: type, hasAtmos: spatial, model: details.joined(separator: " · "))
    }

    private static func outputChannels(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func uint32(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func float64(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Float64? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private final class Observer {
        private let block: AudioObjectPropertyListenerBlock
        private var addresses = [
            AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain),
            AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        ]

        init(_ handler: @escaping () -> Void) {
            block = { _, _ in handler() }
            for i in addresses.indices {
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addresses[i], .main, block)
            }
        }

        deinit {
            for i in addresses.indices {
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addresses[i], .main, block)
            }
        }
    }
}
