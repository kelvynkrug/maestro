import MaestroEngine
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var engine: MaestroEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.linha)

            if engine.apps.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(engine.apps) { app in
                        AppRow(app: app)
                        if app.id != engine.apps.last?.id {
                            Divider().overlay(Theme.linha.opacity(0.6))
                        }
                    }
                }
            }

            if let error = engine.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.latao)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }

            Divider().overlay(Theme.linha)
            footer
        }
        .frame(width: 340)
        .background(Theme.fosso)
        .preferredColorScheme(.dark)
        .onAppear { engine.refresh() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            LogoMark(size: 16)
            Text("Maestro")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.marfim)
            Spacer()
            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.marfim.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help("Configurações")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "speaker.slash")
                .font(.title2)
                .foregroundStyle(Theme.plateia)
            Text("Nenhum app tocando áudio")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.marfim)
            Text("Dê play em algo e ele aparece aqui.")
                .font(.caption)
                .foregroundStyle(Theme.plateia)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack {
            profilesMenu
            Spacer()
            Button("Sair") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.marfim.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var profilesMenu: some View {
        Menu {
            ForEach(engine.profileNames, id: \.self) { name in
                Button(name) { engine.applyProfile(named: name) }
            }
            if !engine.profileNames.isEmpty {
                Divider()
            }
            Button("Gerenciar perfis…") { openSettingsWindow() }
        } label: {
            ChipLabel(icon: "rectangle.stack", text: "Perfis")
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func openSettingsWindow() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AppRow: View {
    @EnvironmentObject private var engine: MaestroEngine
    let app: AudioAppGroup

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.marfim)
                    .lineLimit(1)
                if !app.isPlaying {
                    Text("pausado")
                        .font(.caption2)
                        .foregroundStyle(Theme.fosso)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Theme.plateia, in: Capsule())
                }
                Spacer()
                outputMenu
            }

            HStack(spacing: 10) {
                MaestroSlider(value: volumeBinding)
                Text("\(Int(engine.volumePercent(for: app.id)))%")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.marfim)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { engine.volumePercent(for: app.id) },
            set: { engine.setVolume($0, for: app.id) }
        )
    }

    private var currentOutputName: String {
        guard let uid = engine.outputUID(for: app.id) else { return "Padrão do sistema" }
        return engine.outputs.first { $0.uid == uid }?.name ?? "Saída desconectada"
    }

    private var outputMenu: some View {
        Menu {
            Button("Padrão do sistema") { engine.setOutput(nil, for: app.id) }
            Divider()
            ForEach(engine.outputs) { device in
                Button(device.isDefault ? "\(device.name) (padrão)" : device.name) {
                    engine.setOutput(device.uid, for: app.id)
                }
            }
            if engine.isControlled(app.id) {
                Divider()
                Button("Devolver controle ao sistema") { engine.releaseControl(of: app.id) }
            }
        } label: {
            ChipLabel(
                icon: "arrow.right",
                text: currentOutputName,
                emphasized: engine.isControlled(app.id)
            )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
