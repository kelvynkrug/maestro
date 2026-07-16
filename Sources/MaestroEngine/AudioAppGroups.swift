import AppKit
import CoreAudio
import Foundation

/// Um app "de verdade" agregando todos os seus processos com áudio
/// (ex.: Teams = app principal + modulehost + webviews).
public struct AudioAppGroup: Identifiable {
    public let id: String // bundle ID do app responsável
    public let name: String
    public let icon: NSImage?
    public let processObjectIDs: [AudioObjectID]
    public let isPlaying: Bool
}

/// `responsibility_get_pid_responsible_for_pid` mapeia processos helper
/// (Teams modulehost, Chrome Helper, WebKit GPU) para o app responsável.
private let responsiblePID: (@convention(c) (pid_t) -> pid_t)? = {
    guard let handle = dlopen(nil, RTLD_NOW),
          let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid")
    else { return nil }
    return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
}()

private struct AudioProcessInfo {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let isPlayingOutput: Bool
}

private func listAudioProcessInfos() throws -> [AudioProcessInfo] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    let objectIDs = try readArray(
        system,
        address(kAudioHardwarePropertyProcessObjectList),
        of: AudioObjectID.self,
        "listar processos de áudio"
    )

    return objectIDs.map { objectID in
        var pid: pid_t = -1
        try? readProperty(objectID, address(kAudioProcessPropertyPID), into: &pid, "PID do processo")
        let bundleID = (try? readString(objectID, address(kAudioProcessPropertyBundleID), "bundle ID")) ?? ""
        var isRunningOutput: UInt32 = 0
        try? readProperty(
            objectID,
            address(kAudioProcessPropertyIsRunningOutput),
            into: &isRunningOutput,
            "estado de saída"
        )
        return AudioProcessInfo(
            objectID: objectID,
            pid: pid,
            bundleID: bundleID,
            isPlayingOutput: isRunningOutput != 0
        )
    }
}

/// Agrupa os processos de áudio por app visível (activationPolicy == .regular),
/// resolvendo helpers pelo PID responsável com fallback por prefixo de bundle ID.
public func listAudioAppGroups(excludingBundleID ownBundleID: String?) throws -> [AudioAppGroup] {
    let processes = try listAudioProcessInfos()
    let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    let appsByPID = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })

    var grouped: [String: (app: NSRunningApplication, processes: [AudioProcessInfo])] = [:]

    for process in processes {
        var owner: NSRunningApplication?

        if let responsiblePID, process.pid > 0 {
            owner = appsByPID[responsiblePID(process.pid)]
        }
        if owner == nil, !process.bundleID.isEmpty {
            owner = runningApps
                .filter { app in
                    guard let appBundle = app.bundleIdentifier else { return false }
                    return process.bundleID == appBundle || process.bundleID.hasPrefix(appBundle + ".")
                }
                .max { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }
        }

        guard let owner, let ownerBundleID = owner.bundleIdentifier else { continue }
        guard ownerBundleID != ownBundleID else { continue }
        grouped[ownerBundleID, default: (owner, [])].processes.append(process)
    }

    return grouped.map { bundleID, entry in
        AudioAppGroup(
            id: bundleID,
            name: entry.app.localizedName ?? bundleID,
            icon: entry.app.icon,
            processObjectIDs: entry.processes.map(\.objectID).sorted(),
            isPlaying: entry.processes.contains { $0.isPlayingOutput }
        )
    }
    // Sempre alfabética: a lista não muda de ordem quando um app pausa/toca.
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}
