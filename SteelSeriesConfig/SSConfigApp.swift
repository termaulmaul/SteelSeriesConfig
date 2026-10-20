import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Assigned by the scene during body evaluation; see `SSConfigApp.configureRuntimeCallbacks()`.
    var onReopenRequested: (() -> Void)?

    private var statusController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory: no Dock icon. The menu bar item is the app's presence; Settings
        // temporarily promotes it to a regular app so its window behaves normally.
        NSApp.setActivationPolicy(.accessory)

        let controller = StatusBarController(store: ConfigurationStore.shared)
        statusController = controller
        controller.insert()

        Task { await ConfigurationStore.shared.bootstrap() }
        UpdateChecker.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DeviceNotificationCenter.shared.dismissAll()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        if let statusController, statusController.isInserted {
            statusController.showPopover()
        } else {
            onReopenRequested?()
        }
        return false
    }
}

@main
struct SSConfigApp: App {

    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var isSettingsWindowOpen = false

    var body: some Scene {
        let _ = configureRuntimeCallbacks()

        Window("SteelSeries Config", id: "settings") {
            SettingsView()
                .environment(ConfigurationStore.shared)
                .onAppear {
                    isSettingsWindowOpen = true
                    updateDockVisibility()
                }
                .onDisappear {
                    isSettingsWindowOpen = false
                    updateDockVisibility()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 740, height: 500)
    }

    private func configureRuntimeCallbacks() -> Bool {
        let openWindow = self.openWindow

        if SettingsWindowOpener.requested == nil {
            SettingsWindowOpener.requested = {
                Self.openSettingsWindow(using: openWindow)
            }
        }

        if appDelegate.onReopenRequested == nil {
            appDelegate.onReopenRequested = {
                SettingsWindowOpener.requested?()
            }
        }

        return true
    }

    private static func openSettingsWindow(using openWindow: OpenWindowAction) {
        openWindow(id: "settings")

        DispatchQueue.main.async {
            // Match on the scene's stable id, not its (possibly localized) title.
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) else {
                return
            }
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateDockVisibility() {
        NSApp.setActivationPolicy(isSettingsWindowOpen ? .regular : .accessory)
    }
}
