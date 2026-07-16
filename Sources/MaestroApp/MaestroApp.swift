import AppKit
import MaestroEngine
import Sparkle
import SwiftUI

/// O Maestro é inteiro na paleta escura da identidade; forçar darkAqua
/// garante menus, dropdowns e barras de título coerentes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

@main
struct MaestroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = MaestroEngine()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(engine)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)

        Window("Configurações do Maestro", id: "settings") {
            SettingsView(updater: updaterController.updater)
                .environmentObject(engine)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
