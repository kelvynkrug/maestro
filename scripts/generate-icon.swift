// Gera o AppIcon (V1 · Latão clássico) em todos os tamanhos de um .iconset.
// Uso: swift scripts/generate-icon.swift <diretório-de-saída.iconset>
import AppKit
import Foundation

let navy = NSColor(srgbRed: 0x1B / 255, green: 0x21 / 255, blue: 0x38 / 255, alpha: 1)
let border = NSColor(srgbRed: 0x39 / 255, green: 0x42 / 255, blue: 0x6A / 255, alpha: 1)
let trackColor = NSColor(srgbRed: 0x3A / 255, green: 0x43 / 255, blue: 0x68 / 255, alpha: 1)
let brass = NSColor(srgbRed: 0xC9 / 255, green: 0xA4 / 255, blue: 0x55 / 255, alpha: 1)
let ivory = NSColor(srgbRed: 0xF2 / 255, green: 0xED / 255, blue: 0xE3 / 255, alpha: 1)

// Geometria no espaço 64×64 (y-up). Knobs alto/baixo/médio formando o M;
// trilha acesa em latão do knob para baixo.
struct Fader {
    let x: CGFloat
    let litTopY: CGFloat  // topo do trecho aceso
    let capBottomY: CGFloat  // base do knob
}

let faders: [Fader] = [
    Fader(x: 20, litTopY: 40, capBottomY: 36.5),
    Fader(x: 32, litTopY: 24, capBottomY: 20.5),
    Fader(x: 44, litTopY: 34, capBottomY: 30.5),
]

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = CGFloat(pixels)
    // Grade oficial de ícone macOS: squircle de 824pt num canvas de 1024pt.
    let margin = canvas * 100 / 1024
    let box = canvas * 824 / 1024
    let radius = canvas * 185 / 1024
    let scale = box / 64

    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: margin + x * scale, y: margin + y * scale)
    }

    let squircle = NSBezierPath(
        roundedRect: NSRect(x: margin, y: margin, width: box, height: box),
        xRadius: radius, yRadius: radius
    )
    navy.setFill()
    squircle.fill()
    border.setStroke()
    squircle.lineWidth = max(1, scale)
    squircle.stroke()

    for fader in faders {
        let track = NSBezierPath()
        track.move(to: point(fader.x, 16))
        track.line(to: point(fader.x, 48))
        track.lineWidth = 3.4 * scale
        track.lineCapStyle = .round
        trackColor.setStroke()
        track.stroke()

        let lit = NSBezierPath()
        lit.move(to: point(fader.x, 16))
        lit.line(to: point(fader.x, fader.litTopY))
        lit.lineWidth = 3.4 * scale
        lit.lineCapStyle = .round
        brass.setStroke()
        lit.stroke()

        let capRect = NSRect(
            x: margin + (fader.x - 5.5) * scale,
            y: margin + fader.capBottomY * scale,
            width: 11 * scale,
            height: 6.5 * scale
        )
        let cap = NSBezierPath(roundedRect: capRect, xRadius: 2.4 * scale, yRadius: 2.4 * scale)
        ivory.setFill()
        cap.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("uso: swift generate-icon.swift <saida.iconset>\n".utf8))
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let entries: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for entry in entries {
    let pixels = entry.points * entry.scale
    let rep = drawIcon(pixels: pixels)
    let suffix = entry.scale == 2 ? "@2x" : ""
    let fileURL = outputDir.appendingPathComponent("icon_\(entry.points)x\(entry.points)\(suffix).png")
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("falha ao gerar PNG \(pixels)px\n".utf8))
        exit(1)
    }
    try png.write(to: fileURL)
}

print("iconset gerado em \(outputDir.path)")
