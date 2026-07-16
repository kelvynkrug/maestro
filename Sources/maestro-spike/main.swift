import Foundation

let usage = """
maestro-spike — validação da fase 0 (Core Audio Process Taps)

Uso:
  maestro-spike list
      Lista os apps registrados no Core Audio (▶ = tocando agora) e as saídas disponíveis.

  maestro-spike tap <app> [--out <índice|nome>] [--volume <0-200>]
      Intercepta o áudio do app (por nome ou bundle ID), silencia o original e reproduz
      com volume controlado na saída escolhida (padrão: saída atual do sistema).

      Interativo depois de iniciar:
        0-200   define o volume em %
        o       lista as saídas
        o N     troca a saída para o device de índice N
        q       encerra e devolve o áudio ao normal
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("erro: " + message + "\n").utf8))
    exit(1)
}

func printStatus() throws {
    let processes = try listAudioProcesses()
    print("Apps registrados no Core Audio (▶ = tocando agora):")
    for process in processes {
        let marker = process.isPlayingOutput ? "▶" : " "
        let bundle = process.bundleID.isEmpty ? "-" : process.bundleID
        print("  \(marker) \(process.name)  (\(bundle), pid \(process.pid))")
    }

    let devices = try listOutputDevices()
    print("\nSaídas disponíveis:")
    for (index, device) in devices.enumerated() {
        let marker = device.isDefault ? "★ padrão" : ""
        print("  [\(index)] \(device.name)  \(marker)")
    }
}

func resolveOutput(_ devices: [OutputDevice], selector: String?) -> OutputDevice? {
    guard let selector else { return devices.first { $0.isDefault } ?? devices.first }
    if let index = Int(selector), devices.indices.contains(index) {
        return devices[index]
    }
    let query = selector.lowercased()
    return devices.first { $0.name.lowercased().contains(query) }
}

func runTap(arguments: [String]) throws {
    guard let query = arguments.first, !query.hasPrefix("--") else {
        print(usage)
        exit(1)
    }

    var outSelector: String?
    var initialPercent = 50
    var index = 1
    while index < arguments.count {
        switch arguments[index] {
        case "--out" where index + 1 < arguments.count:
            outSelector = arguments[index + 1]
            index += 2
        case "--volume" where index + 1 < arguments.count:
            initialPercent = Int(arguments[index + 1]) ?? initialPercent
            index += 2
        default:
            fail("argumento desconhecido: \(arguments[index])\n\n\(usage)")
        }
    }

    let processes = try listAudioProcesses()
    let matches = matchProcesses(processes, query: query)
    guard !matches.isEmpty else {
        fail("nenhum processo de áudio corresponde a \"\(query)\". Rode `maestro-spike list` para ver os apps disponíveis.")
    }

    let devices = try listOutputDevices()
    guard let output = resolveOutput(devices, selector: outSelector) else {
        fail("nenhuma saída corresponde a \"\(outSelector ?? "")\". Rode `maestro-spike list`.")
    }

    let names = matches.map(\.name).joined(separator: ", ")
    print("Interceptando: \(names) (\(matches.count) processo(s))")
    print("Saída: \(output.name)  ·  volume inicial: \(initialPercent)%")

    let engine = TapEngine()
    engine.volume = Float(initialPercent) / 100
    try engine.createTap(processObjectIDs: matches.map(\.objectID))
    try engine.startPlayback(outputUID: output.uid)

    print("\nRodando. Comandos: 0-200 = volume %, `o` = listar saídas, `o N` = trocar saída, `q` = sair.")
    var currentDevices = devices
    while let line = readLine() {
        let input = line.trimmingCharacters(in: .whitespaces)
        if input == "q" { break }

        if input == "o" {
            currentDevices = try listOutputDevices()
            for (deviceIndex, device) in currentDevices.enumerated() {
                print("  [\(deviceIndex)] \(device.name)\(device.isDefault ? "  ★ padrão" : "")")
            }
            continue
        }

        if input.hasPrefix("o ") {
            let selector = String(input.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            currentDevices = try listOutputDevices()
            guard let device = resolveOutput(currentDevices, selector: selector) else {
                print("saída não encontrada: \(selector)")
                continue
            }
            try engine.switchOutput(to: device.uid)
            print("→ saída trocada para \(device.name)")
            continue
        }

        if let percent = Int(input), (0...200).contains(percent) {
            engine.volume = Float(percent) / 100
            print("→ volume \(percent)%\(percent > 100 ? " (boost, sem limiter no spike — cuidado com clipping)" : "")")
            continue
        }

        print("comando não reconhecido. Use 0-200, `o`, `o N` ou `q`.")
    }

    engine.dispose()
    print("Encerrado — áudio do app devolvido ao fluxo normal.")
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch arguments.first {
    case nil, "list":
        try printStatus()
    case "tap":
        try runTap(arguments: Array(arguments.dropFirst()))
    case "-h", "--help", "help":
        print(usage)
    default:
        print(usage)
        exit(1)
    }
} catch {
    fail("\(error)")
}
