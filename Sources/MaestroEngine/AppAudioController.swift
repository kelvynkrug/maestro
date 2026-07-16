import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

/// Pipeline de um app controlado: process tap (silencia o original) →
/// aggregate device privado (tap + saída escolhida) → IOProc com ganho,
/// EQ de 3 bandas e limiter.
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

    // EQ: coeficientes publicados pelo main thread via seqlock (versão ímpar = escrita
    // em andamento); o render mantém cópia local e só a atualiza em leitura consistente.
    private static let coefficientCount = 15 // 3 bandas × (b0 b1 b2 a1 a2)
    private let paramsVersion = Atomic<UInt32>(0)
    private let eqActive = Atomic<Bool>(false)
    private let sharedCoefficients: UnsafeMutablePointer<Float>
    private var eqLowDB: Float = 0
    private var eqMidDB: Float = 0
    private var eqHighDB: Float = 0
    private var sampleRate: Float = 48000

    // Estado exclusivo do thread de render (pré-alocado; nunca realoca).
    private var renderCoefficients = [Float](repeating: 0, count: coefficientCount)
    private var coefficientScratch = [Float](repeating: 0, count: coefficientCount)
    private var renderCoefficientsVersion: UInt32 = .max
    private static let maxBuffers = 2, maxChannels = 8
    private var filterState = [Float](repeating: 0, count: 3 * maxBuffers * maxChannels * 2)
    private var limiterEnvelopes = [Float](repeating: 0, count: maxBuffers)
    private var limiterRelease: Float = 0.9996
    private var renderEQWasActive = false

    var volume: Float {
        get { Float(bitPattern: gainBits.load(ordering: .relaxed)) }
        set { gainBits.store(max(0, newValue).bitPattern, ordering: .relaxed) }
    }

    init(groupID: String, processObjectIDs: [AudioObjectID], outputUID: String, volume: Float) throws {
        self.groupID = groupID
        self.processObjectIDs = processObjectIDs
        self.outputUID = outputUID
        self.gainBits = Atomic(max(0, volume).bitPattern)
        self.sharedCoefficients = .allocate(capacity: Self.coefficientCount)
        self.sharedCoefficients.initialize(repeating: 0, count: Self.coefficientCount)

        do {
            try createTap()
        } catch {
            sharedCoefficients.deallocate()
            throw error
        }
        do {
            try startPlayback()
        } catch {
            // Sem isso o tap vaza: quem chamou nunca recebe a referência para dispor.
            destroyTap()
            sharedCoefficients.deallocate()
            throw error
        }
    }

    deinit {
        dispose()
        sharedCoefficients.deallocate()
    }

    func setEQ(lowDB: Float, midDB: Float, highDB: Float) {
        eqLowDB = min(12, max(-12, lowDB))
        eqMidDB = min(12, max(-12, midDB))
        eqHighDB = min(12, max(-12, highDB))
        publishCoefficients()
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

    // MARK: - Tap e aggregate

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

        // Sample rate real do device define os coeficientes do EQ e o release do limiter.
        var nominalRate: Float64 = 48000
        try? readProperty(aggregate, address(kAudioDevicePropertyNominalSampleRate), into: &nominalRate, "sample rate")
        sampleRate = Float(nominalRate)
        limiterRelease = exp(-1 / (0.05 * sampleRate))
        for index in filterState.indices { filterState[index] = 0 }
        for index in limiterEnvelopes.indices { limiterEnvelopes[index] = 0 }
        renderCoefficientsVersion = .max
        publishCoefficients()

        do {
            var procID: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil) { [self] _, inputData, _, outputData, _ in
                renderProcessed(input: inputData, output: outputData)
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

    // MARK: - Publicação de coeficientes (main thread)

    private func publishCoefficients() {
        let bands = [
            Biquad.lowShelf(frequency: 120, sampleRate: sampleRate, gainDB: eqLowDB),
            Biquad.peaking(frequency: 1000, sampleRate: sampleRate, gainDB: eqMidDB),
            Biquad.highShelf(frequency: 8000, sampleRate: sampleRate, gainDB: eqHighDB),
        ]
        // Abertura com barreira full (acq_rel): impede os stores dos coeficientes
        // de serem reordenados para antes do marcador ímpar ficar visível.
        _ = paramsVersion.wrappingAdd(1, ordering: .acquiringAndReleasing)
        var offset = 0
        for band in bands {
            sharedCoefficients[offset] = band.b0
            sharedCoefficients[offset + 1] = band.b1
            sharedCoefficients[offset + 2] = band.b2
            sharedCoefficients[offset + 3] = band.a1
            sharedCoefficients[offset + 4] = band.a2
            offset += 5
        }
        _ = paramsVersion.wrappingAdd(1, ordering: .releasing)
        eqActive.store(
            abs(eqLowDB) > 0.01 || abs(eqMidDB) > 0.01 || abs(eqHighDB) > 0.01,
            ordering: .relaxed
        )
    }

    // MARK: - Render (thread de tempo real: sem alocações, sem locks)

    private func renderProcessed(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let gain = Float(bitPattern: gainBits.load(ordering: .relaxed))
        let eqOn = eqActive.load(ordering: .relaxed)
        if eqOn {
            refreshRenderCoefficientsIfNeeded()
            // EQ religado: zera z1/z2 antigos para não soltar um transiente.
            if !renderEQWasActive {
                for index in filterState.indices { filterState[index] = 0 }
            }
        }
        renderEQWasActive = eqOn

        let inputList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputList = UnsafeMutableAudioBufferListPointer(output)

        for index in 0..<outputList.count {
            let outBuffer = outputList[index]
            guard let outData = outBuffer.mData else { continue }
            let outSamples = outData.assumingMemoryBound(to: Float32.self)
            let outCount = Int(outBuffer.mDataByteSize) / MemoryLayout<Float32>.size

            guard index < inputList.count, let inData = inputList[index].mData else {
                memset(outData, 0, Int(outBuffer.mDataByteSize))
                continue
            }
            let inSamples = inData.assumingMemoryBound(to: Float32.self)
            let inCount = Int(inputList[index].mDataByteSize) / MemoryLayout<Float32>.size
            let shared = min(outCount, inCount)

            for sample in 0..<shared {
                outSamples[sample] = inSamples[sample] * gain
            }
            for sample in shared..<outCount {
                outSamples[sample] = 0
            }

            let channels = Int(outBuffer.mNumberChannels)
            if eqOn, index < Self.maxBuffers, channels >= 1, channels <= Self.maxChannels {
                applyEQ(samples: outSamples, count: shared, channels: channels, bufferIndex: index)
            }
            if gain > 1 || eqOn, index < Self.maxBuffers {
                applyLimiter(samples: outSamples, count: shared, bufferIndex: index)
            }
        }
    }

    private func refreshRenderCoefficientsIfNeeded() {
        let version = paramsVersion.load(ordering: .acquiring)
        guard version != renderCoefficientsVersion, version & 1 == 0 else { return }
        for index in 0..<Self.coefficientCount {
            coefficientScratch[index] = sharedCoefficients[index]
        }
        // Fence de aquisição: a cópia acima não pode ser reordenada para depois
        // da releitura da versão (padrão clássico de leitor de seqlock).
        atomicMemoryFence(ordering: .acquiring)
        // Leitura consistente só quando a versão não mudou durante a cópia;
        // caso contrário mantém os coeficientes locais anteriores.
        guard paramsVersion.load(ordering: .acquiring) == version else { return }
        swap(&renderCoefficients, &coefficientScratch)
        renderCoefficientsVersion = version
    }

    private func applyEQ(samples: UnsafeMutablePointer<Float32>, count: Int, channels: Int, bufferIndex: Int) {
        let frames = count / channels
        for band in 0..<3 {
            let c = band * 5
            let b0 = renderCoefficients[c], b1 = renderCoefficients[c + 1], b2 = renderCoefficients[c + 2]
            let a1 = renderCoefficients[c + 3], a2 = renderCoefficients[c + 4]
            if b0 == 0 || (b0 == 1 && b1 == 0 && b2 == 0 && a1 == 0 && a2 == 0) { continue }

            let stateBase = ((band * Self.maxBuffers) + bufferIndex) * Self.maxChannels * 2
            for channel in 0..<channels {
                var z1 = filterState[stateBase + channel * 2]
                var z2 = filterState[stateBase + channel * 2 + 1]
                var position = channel
                for _ in 0..<frames {
                    let x = samples[position]
                    let y = b0 * x + z1
                    z1 = b1 * x - a1 * y + z2
                    z2 = b2 * x - a2 * y
                    samples[position] = y
                    position += channels
                }
                // Estado não-finito (coeficiente anômalo, denormal) se propagaria
                // para sempre: zera e o filtro se recupera no próximo buffer.
                if !z1.isFinite || !z2.isFinite {
                    z1 = 0
                    z2 = 0
                }
                filterState[stateBase + channel * 2] = z1
                filterState[stateBase + channel * 2 + 1] = z2
            }
        }
    }

    private func applyLimiter(samples: UnsafeMutablePointer<Float32>, count: Int, bufferIndex: Int) {
        let threshold: Float = 0.98
        var envelope = limiterEnvelopes[bufferIndex]
        for sample in 0..<count {
            let magnitude = abs(samples[sample])
            // Ataque instantâneo, release suave (~50 ms).
            envelope = magnitude > envelope ? magnitude : magnitude + (envelope - magnitude) * limiterRelease
            if envelope > threshold {
                samples[sample] *= threshold / envelope
            }
        }
        limiterEnvelopes[bufferIndex] = envelope.isFinite ? envelope : 0
    }
}

/// Coeficientes RBJ (Audio EQ Cookbook), normalizados com a0 = 1.
private struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0

    static func lowShelf(frequency: Float, sampleRate: Float, gainDB: Float) -> Biquad {
        guard abs(gainDB) > 0.01 else { return Biquad() }
        let amp = pow(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / 2 * sqrt(2) // shelf slope S = 1
        let beta = 2 * sqrt(amp) * alpha
        let a0 = (amp + 1) + (amp - 1) * cosw + beta
        return Biquad(
            b0: amp * ((amp + 1) - (amp - 1) * cosw + beta) / a0,
            b1: 2 * amp * ((amp - 1) - (amp + 1) * cosw) / a0,
            b2: amp * ((amp + 1) - (amp - 1) * cosw - beta) / a0,
            a1: -2 * ((amp - 1) + (amp + 1) * cosw) / a0,
            a2: ((amp + 1) + (amp - 1) * cosw - beta) / a0
        )
    }

    static func highShelf(frequency: Float, sampleRate: Float, gainDB: Float) -> Biquad {
        guard abs(gainDB) > 0.01 else { return Biquad() }
        let amp = pow(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / 2 * sqrt(2) // shelf slope S = 1
        let beta = 2 * sqrt(amp) * alpha
        let a0 = (amp + 1) - (amp - 1) * cosw + beta
        return Biquad(
            b0: amp * ((amp + 1) + (amp - 1) * cosw + beta) / a0,
            b1: -2 * amp * ((amp - 1) + (amp + 1) * cosw) / a0,
            b2: amp * ((amp + 1) + (amp - 1) * cosw - beta) / a0,
            a1: 2 * ((amp - 1) - (amp + 1) * cosw) / a0,
            a2: ((amp + 1) - (amp - 1) * cosw - beta) / a0
        )
    }

    static func peaking(frequency: Float, sampleRate: Float, gainDB: Float, q: Float = 0.9) -> Biquad {
        guard abs(gainDB) > 0.01 else { return Biquad() }
        let amp = pow(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha / amp
        return Biquad(
            b0: (1 + alpha * amp) / a0,
            b1: -2 * cosw / a0,
            b2: (1 - alpha * amp) / a0,
            a1: -2 * cosw / a0,
            a2: (1 - alpha / amp) / a0
        )
    }
}
