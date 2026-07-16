import SwiftUI

/// Identidade Console × Batuta (V1 · Latão clássico).
enum Theme {
    static let fosso = Color(red: 0x1B / 255, green: 0x21 / 255, blue: 0x38 / 255)
    static let painel = Color(red: 0x22 / 255, green: 0x29 / 255, blue: 0x45 / 255)
    static let linha = Color(red: 0x31 / 255, green: 0x3A / 255, blue: 0x5C / 255)
    static let latao = Color(red: 0xC9 / 255, green: 0xA4 / 255, blue: 0x55 / 255)
    static let marfim = Color(red: 0xF2 / 255, green: 0xED / 255, blue: 0xE3 / 255)
    static let plateia = Color(red: 0x9A / 255, green: 0xA3 / 255, blue: 0xBF / 255)
}

/// A marca: três faders formando o M, em latão e marfim.
struct LogoMark: View {
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvasSize in
            let unit = canvasSize.width / 18
            let tracks: [(x: CGFloat, knobY: CGFloat)] = [(5, 6.4), (9, 11.4), (13, 8.4)]

            for track in tracks {
                var line = Path()
                line.move(to: CGPoint(x: track.x * unit, y: 3.5 * unit))
                line.addLine(to: CGPoint(x: track.x * unit, y: 14.5 * unit))
                context.stroke(line, with: .color(Theme.latao), style: StrokeStyle(lineWidth: 1.5 * unit, lineCap: .round))

                let knob = CGRect(
                    x: (track.x - 1.8) * unit,
                    y: (track.knobY - 1.3) * unit,
                    width: 3.6 * unit,
                    height: 2.6 * unit
                )
                context.fill(Path(roundedRect: knob, cornerRadius: unit), with: .color(Theme.marfim))
            }
        }
        .frame(width: size, height: size)
    }
}
