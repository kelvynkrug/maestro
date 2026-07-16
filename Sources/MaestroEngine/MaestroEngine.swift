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

        var isNeutral: Bool { volumePercent == 100 && outputUID == nil }
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
    private var timer: Timer?
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

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
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
        // Boost >100% fica para a fase 5 (com limiter); até lá o teto é 100.
        config.volumePercent = max(0, min(100, percent))
        configs[groupID] = config
        apply(groupID: groupID)
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
