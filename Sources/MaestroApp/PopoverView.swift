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
    @State private var showEQ = false

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
                MaestroSlider(value: volumeBinding, range: 0...200, mark: 100)
                Text("\(Int(engine.volumePercent(for: app.id)))%")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.marfim)
                    .frame(width: 40, alignment: .trailing)
                eqToggle
            }

            if showEQ {
                VStack(spacing: 6) {
                    eqBandRow(label: "Grave", band: \.low)
                    eqBandRow(label: "Médio", band: \.mid)
                    eqBandRow(label: "Agudo", band: \.high)
                    if engine.hasEQ(app.id) {
                        HStack {
                            Spacer()
                            Button("Zerar EQ") { engine.setEQ(low: 0, mid: 0, high: 0, for: app.id) }
                                .buttonStyle(.plain)
                                .font(.caption2)
                                .foregroundStyle(Theme.plateia)
                        }
                    }
                }
                .padding(.top, 2)
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

    private var eqToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showEQ.toggle() }
        } label: {
            Text("EQ")
                .font(.caption2.weight(.bold))
                .foregroundStyle(engine.hasEQ(app.id) ? Theme.fosso : Theme.marfim)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(engine.hasEQ(app.id) ? Theme.latao : Theme.painel, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.linha, lineWidth: engine.hasEQ(app.id) ? 0 : 1))
        }
        .buttonStyle(.plain)
        .help("Equalizador (grave, médio, agudo)")
    }

    private func eqBandRow(label: String, band: KeyPath<(low: Double, mid: Double, high: Double), Double>) -> some View {
        let gains = engine.eqGains(for: app.id)
        let binding = Binding<Double>(
            get: { engine.eqGains(for: app.id)[keyPath: band] },
            set: { newValue in
                var updated = engine.eqGains(for: app.id)
                switch band {
                case \.low: updated.low = newValue
                case \.mid: updated.mid = newValue
                default: updated.high = newValue
                }
                engine.setEQ(low: updated.low, mid: updated.mid, high: updated.high, for: app.id)
            }
        )
        return HStack(spacing: 10) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.plateia)
                .frame(width: 42, alignment: .leading)
            MaestroSlider(value: binding, range: -12...12, mark: 0, bipolar: true)
            Text(String(format: "%+.0f dB", gains[keyPath: band]))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.marfim)
                .frame(width: 44, alignment: .trailing)
        }
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
