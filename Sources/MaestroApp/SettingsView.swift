import MaestroEngine
import ServiceManagement
import Sparkle
import SwiftUI

struct SettingsView: View {
    let updater: SPUUpdater
    @EnvironmentObject private var engine: MaestroEngine
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var newProfileName = ""
    @State private var flatConfirmationID = 0
    @State private var showFlatConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                LogoMark(size: 20)
                Text("Maestro")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.marfim)
                Spacer()
                Text("v0.1.0")
                    .font(.caption)
                    .foregroundStyle(Theme.plateia)
            }

            SettingsSection(title: "Geral") {
                Toggle("Iniciar o Maestro no login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .tint(Theme.latao)
                    .foregroundStyle(Theme.marfim)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            SettingsSection(title: "Perfis") {
                Text("Um perfil guarda os volumes e saídas de todos os apps para restaurar depois — por exemplo, o seu padrão após reiniciar o Mac.")
                    .font(.caption)
                    .foregroundStyle(Theme.plateia)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    TextField("Nome do perfil (ex.: Padrão)", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                    Button("Salvar estado atual") {
                        engine.saveProfile(named: newProfileName)
                        newProfileName = ""
                    }
                    .buttonStyle(PanelButtonStyle())
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty || !engine.hasSavedConfigs)
                }

                if engine.profileNames.isEmpty {
                    Text("Nenhum perfil salvo ainda.")
                        .font(.caption)
                        .foregroundStyle(Theme.plateia.opacity(0.8))
                } else {
                    ForEach(engine.profileNames, id: \.self) { name in
                        HStack {
                            Image(systemName: "rectangle.stack")
                                .font(.caption)
                                .foregroundStyle(Theme.latao)
                            Text(name)
                                .foregroundStyle(Theme.marfim)
                            Spacer()
                            Button("Aplicar") { engine.applyProfile(named: name) }
                                .buttonStyle(PanelButtonStyle())
                            Button {
                                engine.deleteProfile(named: name)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Theme.plateia)
                            }
                            .buttonStyle(.plain)
                            .help("Apagar perfil")
                        }
                    }
                }
            }

            SettingsSection(title: "Manutenção") {
                HStack(spacing: 10) {
                    Button("Flat") {
                        engine.clearSavedConfigs()
                        flatConfirmationID += 1
                        withAnimation { showFlatConfirmation = true }
                    }
                    .buttonStyle(PanelButtonStyle())
                    .disabled(!engine.hasSavedConfigs)
                    .help("Como zerar os faders da mesa")

                    if showFlatConfirmation {
                        Label("Faders zerados — apps devolvidos ao sistema", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.latao)
                            .transition(.opacity)
                            .task(id: flatConfirmationID) {
                                try? await Task.sleep(for: .seconds(3))
                                withAnimation { showFlatConfirmation = false }
                            }
                    }
                }

                Text("Remove a alteração dos volumes e roteamentos; os apps voltam ao fluxo normal de áudio. Os perfis salvos não são afetados.")
                    .font(.caption)
                    .foregroundStyle(Theme.plateia)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsSection(title: "Sobre") {
                Text("Controle de volume e saída de áudio por aplicativo, via Core Audio Process Taps.")
                    .font(.callout)
                    .foregroundStyle(Theme.plateia)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Buscar atualizações…") {
                    updater.checkForUpdates()
                }
                .buttonStyle(PanelButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.fosso)
        .preferredColorScheme(.dark)
    }
}
