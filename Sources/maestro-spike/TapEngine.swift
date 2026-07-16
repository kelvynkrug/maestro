import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

/// Pipeline por app: process tap (silencia o original) → aggregate device privado
/// contendo o tap + a saída escolhida → IOProc que copia o áudio aplicando ganho.
final class TapEngine: @unchecked Sendable {
    private let gainBits = Atomic<UInt32>(Float(0.5).bitPattern)
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var tapUUID = UUID()
    private var aggregateID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?

    var volume: Float {
        get { Float(bitPattern: gainBits.load(ordering: .relaxed)) }
        set { gainBits.store(max(0, newValue).bitPattern, ordering: .relaxed) }
    }

    func createTap(processObjectIDs: [AudioObjectID]) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        tapUUID = UUID()
        description.uuid = tapUUID
        description.name = "Maestro Spike Tap"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true

        var tap: AudioObjectID = kAudioObjectUnknown
        try check(
            AudioHardwareCreateProcessTap(description, &tap),
            "criar process tap — verifique a permissão de Gravação de Áudio do Sistema em Ajustes > Privacidade"
        )
        tapID = tap
    }

    func startPlayback(outputUID: String) throws {
        precondition(tapID != kAudioObjectUnknown, "createTap deve ser chamado antes de startPlayback")

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Maestro Spike",
            kAudioAggregateDeviceUIDKey: "com.kelvynkrug.maestro.spike.aggregate",
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

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil) { [self] _, inputData, _, outputData, _ in
            renderWithGain(input: inputData, output: outputData)
        }
        try check(status, "criar IOProc")
        ioProcID = procID
        try check(AudioDeviceStart(aggregate, procID), "iniciar aggregate device")
    }

    func stopPlayback() {
        guard aggregateID != kAudioObjectUnknown else { return }
        if let procID = ioProcID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            ioProcID = nil
        }
        AudioHardwareDestroyAggregateDevice(aggregateID)
        aggregateID = kAudioObjectUnknown
    }

    func switchOutput(to outputUID: String) throws {
        stopPlayback()
        try startPlayback(outputUID: outputUID)
    }

    func dispose() {
        stopPlayback()
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
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
