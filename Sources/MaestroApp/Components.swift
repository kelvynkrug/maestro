import SwiftUI

/// Slider no estilo da identidade: trilha visível, preenchimento latão, knob marfim.
/// `bipolar` preenche a partir do centro (EQ); `mark` desenha um risco de referência (ex.: 100%).
struct MaestroSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var mark: Double?
    var bipolar = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let span = range.upperBound - range.lowerBound
            let fraction = CGFloat((value - range.lowerBound) / span)
            let knobX = min(max(8, width * fraction), width - 8)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.linha)
                    .frame(height: 5)

                if bipolar {
                    let centerX = width / 2
                    Capsule()
                        .fill(Theme.latao)
                        .frame(width: max(2, abs(width * fraction - centerX)), height: 5)
                        .offset(x: min(centerX, width * fraction))
                } else {
                    Capsule()
                        .fill(Theme.latao)
                        .frame(width: max(5, width * fraction), height: 5)
                }

                if let mark {
                    let markX = width * CGFloat((mark - range.lowerBound) / span)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.plateia)
                        .frame(width: 2, height: 11)
                        .position(x: markX, y: geometry.size.height / 2)
                }

                Circle()
                    .fill(Theme.marfim)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .position(x: knobX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let raw = range.lowerBound + Double(gesture.location.x / width) * span
                        value = min(range.upperBound, max(range.lowerBound, raw))
                    }
            )
        }
        .frame(height: 22)
    }
}

/// Pill de destaque usado nos menus do popover (saída, perfis).
struct ChipLabel: View {
    let icon: String
    let text: String
    var emphasized = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.caption)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .opacity(0.7)
        }
        .foregroundStyle(emphasized ? Theme.latao : Theme.marfim)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.painel, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.linha, lineWidth: 1))
    }
}

/// Seção com painel elevado, usada na janela de configurações.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(Theme.plateia)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.painel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.linha, lineWidth: 1))
        }
    }
}

struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.marfim)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Theme.linha.opacity(configuration.isPressed ? 1 : 0.55),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.linha, lineWidth: 1))
    }
}
