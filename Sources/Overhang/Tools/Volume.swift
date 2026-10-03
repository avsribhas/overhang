import AudioToolbox
import Combine
import CoreAudio
import SwiftUI

/// Reads and sets the default output device's volume via CoreAudio, and reports
/// changes made elsewhere (keyboard keys, Control Center) so the notch can show a HUD.
final class VolumeService: ObservableObject {
    static let shared = VolumeService()

    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false
    @Published private(set) var deviceName = ""
    @Published private(set) var supportsVolume = true

    let externalChange = PassthroughSubject<(Float, Bool), Never>()

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var lastOwnChange = Date.distantPast
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, DispatchQueue.main) { [weak self] _, _ in
            self?.attachToDefaultDevice()
        }
        attachToDefaultDevice()
    }

    private func attachToDefaultDevice() {
        if deviceID != kAudioObjectUnknown, let block = listenerBlock {
            AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, block)
            AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, block)
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return }
        deviceID = id
        deviceName = Self.name(of: id)
        supportsVolume = AudioObjectHasProperty(id, &volumeAddress)

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.read()
            if Date().timeIntervalSince(self.lastOwnChange) > 0.6 {
                self.externalChange.send((self.volume, self.muted))
            }
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(id, &volumeAddress, DispatchQueue.main, block)
        AudioObjectAddPropertyListenerBlock(id, &muteAddress, DispatchQueue.main, block)
        read()
    }

    private func read() {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &value) == noErr { volume = value }
        var mute = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &mute) == noErr { muted = mute != 0 }
    }

    func setVolume(_ value: Float) {
        lastOwnChange = Date()
        var newValue = Float32(min(max(value, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil, size, &newValue)
        if muted, newValue > 0 { setMuted(false) }
        volume = newValue
    }

    func setMuted(_ value: Bool) {
        lastOwnChange = Date()
        var newValue = UInt32(value ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, size, &newValue)
        muted = value
    }

    private static func name(of id: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let value = name else { return "Output" }
        return value.takeRetainedValue() as String
    }
}

struct VolumeView: View {
    @ObservedObject private var service = VolumeService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "hifispeaker.fill").foregroundStyle(Theme.secondary)
                Text(service.deviceName).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int((service.muted ? 0 : service.volume) * 100))%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
            }
            if service.supportsVolume {
                HStack(spacing: 12) {
                    IconButton(symbol: service.muted ? "speaker.slash.fill" : "speaker.fill", size: 30,
                               tint: service.muted ? Theme.negative : .white) { service.setMuted(!service.muted) }
                    Slider(value: Binding(get: { Double(service.volume) }, set: { service.setVolume(Float($0)) }), in: 0...1)
                        .tint(Theme.accent)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 6) {
                    ForEach([0, 25, 50, 75, 100], id: \.self) { level in
                        PillButton(title: "\(level)%") { service.setVolume(Float(level) / 100) }
                    }
                }
            } else {
                EmptyState(symbol: "speaker.slash", title: "This output has no software volume",
                           message: "Some devices (HDMI, some USB DACs) only allow volume changes on the device itself.")
            }
            Text("Changes from the keyboard or Control Center show as a HUD in the closed notch.")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }
}
