import AppKit
import SwiftUI

/// Settings window shell: sidebar of tabs, detail pane, Quit anchored to the sidebar
/// footer — the reference app's arrangement, including the sidebar width and the
/// fixed window frame, so the two apps feel like siblings.
struct SettingsView: View {

    @State private var selectedTab: SettingsTab = .device

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(width: 740, height: 500)
    }

    private var sidebar: some View {
        List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
            NavigationLink(value: tab) {
                Label(tab.title, systemImage: tab.icon)
            }
        }
        .frame(width: 215)
        .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
        .overlay(alignment: .bottom) {
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                Text("Quit App")
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
    }

    @ViewBuilder
    private var detail: some View {
        NavigationStack {
            switch selectedTab {
            case .device: SettingsDeviceView()
            case .backups: SettingsBackupsView()
            case .app: SettingsAppView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

enum SettingsTab: String, CaseIterable {
    case device
    case backups
    case app

    var title: String {
        switch self {
        case .device: return "Device"
        case .backups: return "Backups"
        case .app: return "App"
        }
    }

    var icon: String {
        switch self {
        case .device: return "computermouse"
        case .backups: return "clock.arrow.circlepath"
        case .app: return "gearshape"
        }
    }
}
