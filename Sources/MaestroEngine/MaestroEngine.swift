import AppKit
import CoreAudio
import Foundation

/// Fachada do Maestro: observa os apps tocando áudio, mantém um
/// `AppAudioController` por app controlado e persiste as configurações.
@MainActor
public final class MaestroEngine: ObservableObject {
    public struct AppConfig: Codable, Equatable {
        public var volumePercent: Double
        /// `nil` segue a saída padrão do sistema (re-resolvida quando o padrão muda).
        public var outputUID: String?
        public var eqLowDB: Double
        public var eqMidDB: Double
        public var eqHighDB: Double

        var isNeutral: Bool {
            volumePercent == 100 && outputUID == nil
                && eqLowDB == 0 && eqMidDB == 0 && eqHighDB == 0
        }

        var hasEQ: Bool { eqLowDB != 0 || eqMidDB != 0 || eqHighDB != 0 }

        init(volumePercent: Double, outputUID: String?, eqLowDB: Double = 0, eqMidDB: Double = 0, eqHighDB: Double = 0) {
            self.volumePercent = volumePercent
            self.outputUID = outputUID
            self.eqLowDB = eqLowDB
            self.eqMidDB = eqMidDB
            self.eqHighDB = eqHighDB
        }

        // Decodificação tolerante: configs salvas antes do EQ não têm as chaves novas.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            volumePercent = try container.decode(Double.self, forKey: .volumePercent)
            outputUID = try container.decodeIfPresent(String.self, forKey: .outputUID)
            eqLowDB = try container.decodeIfPresent(Double.self, forKey: .eqLowDB) ?? 0
            eqMidDB = try container.decodeIfPresent(Double.self, forKey: .eqMidDB) ?? 0
            eqHighDB = try container.decodeIfPresent(Double.self, forKey: .eqHighDB) ?? 0
        }
    }

    @Published public private(set) var apps: [AudioAppGroup] = []
    @Published public private(set) var outputs: [OutputDevice] = []
    @Published public private(set) var lastError: String?
    @Published private var configs: [String: AppConfig] = [:] {
        didSet { save(configs, key: Self.configsKey) }
    }
    @Published private var profiles: [String: [String: AppConfig]] = [:] {
        didSet { save(profiles, key: Self.profilesKey) }
    }

    private var controllers: [String: AppAudioController] = [:]
    private var refreshScheduled = false
    private let listeners = ListenerRegistry()
    private let defaults = UserDefaults.standard
    private static let configsKey = "appConfigs"
    private static let profilesKey = "profiles"

    public init() {
        if let data = defaults.data(forKey: Self.configsKey),
           let decoded = try? JSONDecoder().decode([String: AppConfig].self, from: data) {
            configs = decoded
        }
        if let data = defaults.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([String: [String: AppConfig]].self, from: data) {
            profiles = decoded
        }

        systemListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        refresh()
        installSystemListeners()
        // Fallback raro: cobre qualquer evento que os listeners não entreguem.
        listeners.timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    // MARK: - Listeners do Core Audio (o refresh é dirigido a eventos, não a polling)

    private func installSystemListeners() {
        listeners.systemBlock = systemListenerBlock
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in engineSystemListenerSelectors {
            var propertyAddress = address(selector)
            AudioObjectAddPropertyListenerBlock(system, &propertyAddress, .main, systemListenerBlock)
        }
    }

    // Stored (não lazy) para o deinit nonisolated conseguir removê-lo.
    private var systemListenerBlock: AudioObjectPropertyListenerBlock!

    /// Coalesce rajadas de eventos (ex.: vários processos mudando de uma vez) num único refresh.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    /// Um app começar/parar de tocar não muda a lista de processos do sistema:
    /// exige listener de `isRunningOutput` em cada processo observado.
    private func syncProcessListeners(currentObjectIDs: Set<AudioObjectID>) {
        var runningAddress = address(kAudioProcessPropertyIsRunningOutput)

        for objectID in currentObjectIDs where listeners.processBlocks[objectID] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            if AudioObjectAddPropertyListenerBlock(objectID, &runningAddress, .main, block) == noErr {
                listeners.processBlocks[objectID] = block
            }
        }

        for (objectID, block) in listeners.processBlocks where !currentObjectIDs.contains(objectID) {
            AudioObjectRemovePropertyListenerBlock(objectID, &runningAddress, .main, block)
            listeners.processBlocks[objectID] = nil
        }
    }

    // MARK: - Estado por app

    public func volumePercent(for groupID: String) -> Double {
        configs[groupID]?.volumePercent ?? 100
    }

    public func outputUID(for groupID: String) -> String? {
        configs[groupID]?.outputUID
    }

    public func isControlled(_ groupID: String) -> Bool {
        controllers[groupID] != nil
    }

    public var hasSavedConfigs: Bool { !configs.isEmpty }

    // MARK: - Ações

    public func setVolume(_ percent: Double, for groupID: String) {
        var config = configs[groupID] ?? AppConfig(volumePercent: 100, outputUID: nil)
        // Acima de 100% o controller aplica limiter para evitar clipping.
        config.volumePercent = max(0, min(200, percent))
        configs[groupID] = config
        apply(groupID: groupID)
    }

    public func setEQ(low: Double, mid: Double, high: Double, for groupID: String) {
        var config = configs[groupID] ?? AppConfig(volumePercent: 100, outputUID: nil)
        config.eqLowDB = max(-12, min(12, low))
        config.eqMidDB = max(-12, min(12, mid))
        config.eqHighDB = max(-12, min(12, high))
        configs[groupID] = config
        apply(groupID: groupID)
    }

    public func eqGains(for groupID: String) -> (low: Double, mid: Double, high: Double) {
        let config = configs[groupID]
        return (config?.eqLowDB ?? 0, config?.eqMidDB ?? 0, config?.eqHighDB ?? 0)
    }

    public func hasEQ(_ groupID: String) -> Bool {
        configs[groupID]?.hasEQ ?? false
    }

    public func setOutput(_ uid: String?, for groupID: String) {
        var config = configs[groupID] ?? AppConfig(volumePercent: 100, outputUID: nil)
        config.outputUID = uid
        configs[groupID] = config
        apply(groupID: groupID)
    }

    public func releaseControl(of groupID: String) {
        configs[groupID] = nil
        controllers[groupID]?.dispose()
        controllers[groupID] = nil
        refresh()
    }

    public func clearSavedConfigs() {
        for id in Array(configs.keys) { releaseControl(of: id) }
    }

    public func disposeAll() {
        for controller in controllers.values { controller.dispose() }
        controllers.removeAll()
    }

    // MARK: - Perfis

    public var profileNames: [String] { profiles.keys.sorted() }

    /// Salva o estado atual (todas as configs por app) como um perfil nomeado.
    public func saveProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        profiles[trimmed] = configs
    }

    /// Substitui as configs atuais pelas do perfil e reaplica nos apps abertos.
    public func applyProfile(named name: String) {
        guard let stored = profiles[name] else { return }
        for controller in controllers.values { controller.dispose() }
        controllers.removeAll()
        configs = stored
        refresh()
    }

    public func deleteProfile(named name: String) {
        profiles[name] = nil
    }

    // MARK: - Ciclo de atualização

    public func refresh() {
        let ownBundleID = Bundle.main.bundleIdentifier
        let groups = (try? listAudioAppGroups(excludingBundleID: ownBundleID)) ?? []
        outputs = (try? listOutputDevices()) ?? []
        syncProcessListeners(currentObjectIDs: Set(groups.flatMap(\.processObjectIDs)))

        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

        // Controladores de apps que sumiram: descarta (config permanece salva).
        for (groupID, controller) in controllers where groupsByID[groupID] == nil {
            controller.dispose()
            controllers[groupID] = nil
        }

        for group in groups {
            if let controller = controllers[group.id] {
                do {
                    try controller.setProcesses(group.processObjectIDs)
                    // Config "seguir padrão": acompanha mudanças da saída padrão do sistema.
                    if configs[group.id]?.outputUID == nil,
                       let systemDefault = outputs.first(where: { $0.isDefault }),
                       controller.outputUID != systemDefault.uid {
                        try controller.setOutput(uid: systemDefault.uid)
                    }
                } catch {
                    lastError = "\(group.name): \(error)"
                    controller.dispose()
                    controllers[group.id] = nil
                }
            } else if configs[group.id] != nil, group.isPlaying {
                apply(groupID: group.id)
            }
        }

        // Visíveis no popover: tocando agora ou sob controle.
        apps = groups.filter { $0.isPlaying || controllers[$0.id] != nil }
    }

    private func apply(groupID: String) {
        guard let config = configs[groupID] else { return }

        if config.isNeutral {
            configs[groupID] = nil
            controllers[groupID]?.dispose()
            controllers[groupID] = nil
            refresh()
            return
        }

        let gain = Float(config.volumePercent / 100)

        if let controller = controllers[groupID] {
            controller.volume = gain
            controller.setEQ(
                lowDB: Float(config.eqLowDB),
                midDB: Float(config.eqMidDB),
                highDB: Float(config.eqHighDB)
            )
            do {
                if let uid = config.outputUID {
                    try controller.setOutput(uid: uid)
                } else if let systemDefault = outputs.first(where: { $0.isDefault }) {
                    try controller.setOutput(uid: systemDefault.uid)
                }
            } catch {
                // setOutput falho deixa o controller sem playback (app mudo):
                // descarta para devolver o áudio; o próximo refresh tenta de novo.
                lastError = "\(groupID): \(error)"
                controller.dispose()
                controllers[groupID] = nil
            }
            return
        }

        guard let group = apps.first(where: { $0.id == groupID })
            ?? (try? listAudioAppGroups(excludingBundleID: Bundle.main.bundleIdentifier))?.first(where: { $0.id == groupID })
        else { return }

        let targetUID = config.outputUID
            ?? outputs.first(where: { $0.isDefault })?.uid
        guard let targetUID else { return }

        do {
            let controller = try AppAudioController(
                groupID: groupID,
                processObjectIDs: group.processObjectIDs,
                outputUID: targetUID,
                volume: gain
            )
            controller.setEQ(
                lowDB: Float(config.eqLowDB),
                midDB: Float(config.eqMidDB),
                highDB: Float(config.eqHighDB)
            )
            controllers[groupID] = controller
            lastError = nil
        } catch {
            lastError = "\(group.name): \(error)"
        }
    }

    private func save(_ value: some Encodable, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}

private let engineSystemListenerSelectors: [AudioObjectPropertySelector] = [
    kAudioHardwarePropertyProcessObjectList,
    kAudioHardwarePropertyDevices,
    kAudioHardwarePropertyDefaultOutputDevice,
]

/// Dono dos registros de listener e do timer de fallback. A limpeza vive no
/// deinit DESTA classe (nonisolated, sem restrições de actor) porque um deinit
/// no próprio engine @MainActor não pode tocar estado não-Sendable no Swift 6.
private final class ListenerRegistry: @unchecked Sendable {
    var systemBlock: AudioObjectPropertyListenerBlock?
    var processBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    var timer: Timer?

    deinit {
        timer?.invalidate()
        if let systemBlock {
            let system = AudioObjectID(kAudioObjectSystemObject)
            for selector in engineSystemListenerSelectors {
                var propertyAddress = address(selector)
                AudioObjectRemovePropertyListenerBlock(system, &propertyAddress, .main, systemBlock)
            }
        }
        var runningAddress = address(kAudioProcessPropertyIsRunningOutput)
        for (objectID, block) in processBlocks {
            AudioObjectRemovePropertyListenerBlock(objectID, &runningAddress, .main, block)
        }
    }
}
