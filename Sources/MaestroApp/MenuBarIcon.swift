import AppKit

/// Ícone template da menu bar: três faders formando o M.
/// Template = o sistema adapta a cor ao tema claro/escuro.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            // Coordenadas y-up do AppKit: knobs alto/baixo/médio formando o M.
            let tracks: [(x: CGFloat, knobY: CGFloat)] = [(5, 11.4), (9, 6.4), (13, 9.4)]
            NSColor.black.set()

            for track in tracks {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: track.x, y: 3.5))
                line.line(to: NSPoint(x: track.x, y: 14.5))
                line.lineWidth = 1.5
                line.lineCapStyle = .round
                line.stroke()

                let knob = NSBezierPath(
                    roundedRect: NSRect(x: track.x - 1.8, y: track.knobY - 1.3, width: 3.6, height: 2.6),
                    xRadius: 1,
                    yRadius: 1
                )
                knob.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
