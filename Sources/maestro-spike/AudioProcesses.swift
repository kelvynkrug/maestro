import AppKit
import CoreAudio
import Foundation

struct AudioProcess {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let name: String
    let isPlayingOutput: Bool
}

func listAudioProcesses() throws -> [AudioProcess] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    let objectIDs = try readArray(
        system,
        address(kAudioHardwarePropertyProcessObjectList),
        of: AudioObjectID.self,
        "listar processos de áudio"
    )

    var result: [AudioProcess] = []
    for objectID in objectIDs {
        var pid: pid_t = -1
        try? readProperty(objectID, address(kAudioProcessPropertyPID), into: &pid, "PID do processo")
        let bundleID = (try? readString(objectID, address(kAudioProcessPropertyBundleID), "bundle ID")) ?? ""

        var isRunningOutput: UInt32 = 0
        try? readProperty(
            objectID,
            address(kAudioProcessPropertyIsRunningOutput),
            into: &isRunningOutput,
            "estado de saída do processo"
        )

        let name = NSRunningApplication(processIdentifier: pid)?.localizedName
            ?? (bundleID.isEmpty ? "pid \(pid)" : bundleID)

        result.append(AudioProcess(
            objectID: objectID,
            pid: pid,
            bundleID: bundleID,
            name: name,
            isPlayingOutput: isRunningOutput != 0
        ))
    }
    return result.sorted { ($0.isPlayingOutput ? 0 : 1, $0.name) < ($1.isPlayingOutput ? 0 : 1, $1.name) }
}

func matchProcesses(_ processes: [AudioProcess], query: String) -> [AudioProcess] {
    let query = query.lowercased()
    return processes.filter {
        $0.bundleID.lowercased().contains(query) || $0.name.lowercased().contains(query)
    }
}
