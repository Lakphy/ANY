import SwiftUI

@main
struct ANYApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("ANY", systemImage: "sparkle.magnifyingglass") {
            MenuBarContent(coordinator: appDelegate.coordinator)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}

private struct MenuBarContent: View {
    let coordinator: AppCoordinator

    var body: some View {
        Button("打开 ANY") {
            // Let the menu finish closing before the panel takes key focus.
            Task { coordinator.showLauncher() }
        }
        .keyboardShortcut(coordinator.settings.hotKey.keyboardShortcut)

        Divider()

        Button("设置…") {
            Task { coordinator.openSettings() }
        }
        .keyboardShortcut(",")

        Divider()

        Button("退出 ANY") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
