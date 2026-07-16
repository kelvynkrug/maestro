import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

/// Pipeline de um app controlado: process tap (silencia o original) →
/// aggregate device privado (tap + saída escolhida) → IOProc com ganho.
final class AppAudioController: @unchecked Sendable {
    let groupID: String
    private(set) var outputUID: String
    private(set) var processObjectIDs: [AudioObjectID]

    private let gainBits: Atomic<UInt32>
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var tapUUID = UUID()
    private var aggregateID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private let aggregateUID = "com.kelvynkrug.maestro.aggregate." + UUID().uuidString

    var volume: Float {
        get { Float(bitPattern: gainBits.load(ordering: .relaxed)) }
        set { gainBits.store(max(0, newValue).bitPattern, ordering: .relaxed) }
    }

    init(groupID: String, processObjectIDs: [AudioObjectID], outputUID: String, volume: Float) throws {
        self.groupID = groupID
        self.processObjectIDs = processObjectIDs
        self.outputUID = outputUID
        self.gainBits = Atomic(max(0, volume).bitPattern)
        try createTap()
        do {
            try startPlayback()
        } catch {
            // Sem isso o tap vaza: quem chamou nunca recebe a referência para dispor.
            destroyTap()
            throw error
        }
    }

    deinit {
        dispose()
    }

    func setOutput(uid: String) throws {
        guard uid != outputUID else { return }
        outputUID = uid
        stopPlayback()
        try startPlayback()
    }

    /// O conjunto de processos de um app muda (relaunch, novo helper em call):
    /// recria o tap mantendo volume e saída.
    func setProcesses(_ objectIDs: [AudioObjectID]) throws {
        guard objectIDs != processObjectIDs else { return }
        processObjectIDs = objectIDs
        stopPlayback()
        destroyTap()
        try createTap()
        try startPlayback()
    }

    func dispose() {
        stopPlayback()
        destroyTap()
    }

    private func createTap() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        tapUUID = UUID()
        description.uuid = tapUUID
        description.name = "Maestro · \(groupID)"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true

        var tap: AudioObjectID = kAudioObjectUnknown
        try check(
            AudioHardwareCreateProcessTap(description, &tap),
            "criar process tap — verifique a permissão de Gravação de Áudio do Sistema"
        )
        tapID = tap
    }

    private func destroyTap() {
        guard tapID != kAudioObjectUnknown else { return }
        AudioHardwareDestroyProcessTap(tapID)
        tapID = kAudioObjectUnknown
    }

    private func startPlayback() throws {
        precondition(tapID != kAudioObjectUnknown)

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Maestro · \(groupID)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]

        var aggregate: AudioObjectID = kAudioObjectUnknown
        try check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate), "criar aggregate device")
        aggregateID = aggregate

        do {
            var procID: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil) { [self] _, inputData, _, outputData, _ in
                renderWithGain(input: inputData, output: outputData)
            }
            try check(status, "criar IOProc")
            ioProcID = procID
            try check(AudioDeviceStart(aggregate, procID), "iniciar aggregate device")
        } catch {
            // AudioDeviceStart pode falhar com o IOProc já registrado; o IOProc
            // retém self, então sem esta limpeza nem o deinit dispararia.
            stopPlayback()
            throw error
        }
    }

    private func stopPlayback() {
        guard aggregateID != kAudioObjectUnknown else { return }
        if let procID = ioProcID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            ioProcID = nil
        }
        AudioHardwareDestroyAggregateDevice(aggregateID)
        aggregateID = kAudioObjectUnknown
    }

    private func renderWithGain(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let gain = Float(bitPattern: gainBits.load(ordering: .relaxed))
        let inputList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputList = UnsafeMutableAudioBufferListPointer(output)

        for index in 0..<outputList.count {
            let outBuffer = outputList[index]
            guard let outData = outBuffer.mData else { continue }
            let outSamples = outData.assumingMemoryBound(to: Float32.self)
            let outCount = Int(outBuffer.mDataByteSize) / MemoryLayout<Float32>.size

            if index < inputList.count, let inData = inputList[index].mData {
                let inSamples = inData.assumingMemoryBound(to: Float32.self)
                let inCount = Int(inputList[index].mDataByteSize) / MemoryLayout<Float32>.size
                let shared = min(outCount, inCount)
                for sample in 0..<shared {
                    outSamples[sample] = inSamples[sample] * gain
                }
                for sample in shared..<outCount {
                    outSamples[sample] = 0
                }
            } else {
                memset(outData, 0, Int(outBuffer.mDataByteSize))
            }
        }
    }
}
