import CoreAudio
import Foundation

public struct OutputDevice: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let isDefault: Bool
}

public func listOutputDevices() throws -> [OutputDevice] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    let deviceIDs = try readArray(
        system,
        address(kAudioHardwarePropertyDevices),
        of: AudioDeviceID.self,
        "listar devices"
    )

    var defaultOutput: AudioDeviceID = kAudioObjectUnknown
    try? readProperty(system, address(kAudioHardwarePropertyDefaultOutputDevice), into: &defaultOutput, "saída padrão")

    var result: [OutputDevice] = []
    for deviceID in deviceIDs {
        let outputStreams = (try? readArray(
            deviceID,
            address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput),
            of: AudioStreamID.self,
            "streams de saída"
        )) ?? []
        guard !outputStreams.isEmpty else { continue }

        guard let uid = try? readString(deviceID, address(kAudioDevicePropertyDeviceUID), "UID do device"),
              let name = try? readString(deviceID, address(kAudioObjectPropertyName), "nome do device")
        else { continue }

        result.append(OutputDevice(id: deviceID, uid: uid, name: name, isDefault: deviceID == defaultOutput))
    }
    return result
}
