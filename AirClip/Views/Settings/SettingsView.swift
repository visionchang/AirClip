import SwiftUI

struct SettingsView: View {
    @Environment(SettingsRouter.self) private var settingsRouter
    @FocusState private var isSidebarFocused: Bool

    var body: some View {
        @Bindable var settingsRouter = settingsRouter

        NavigationSplitView {
            List(SettingsTab.allCases, selection: $settingsRouter.selectedTab) { tab in
                Label(LocalizedStringKey(tab.title), systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
            .focused($isSidebarFocused)
        } detail: {
            switch settingsRouter.selectedTab {
            case .general:
                GeneralSettingsView()
            case .shortcuts:
                ShortcutsSettingsView()
            case .storage:
                StorageSettingsView()
            case .sync:
                SyncSettingsView()
            case .privacy:
                PrivacySettingsView()
            case .about:
                AboutSettingsView()
            }
        }
        .frame(width: 650, height: 450)
        .onAppear {
            isSidebarFocused = true
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case storage
    case sync
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "general"
        case .shortcuts: return "shortcuts"
        case .storage: return "storage"
        case .sync: return "sync"
        case .privacy: return "privacy"
        case .about: return "about"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "command"
        case .storage: return "internaldrive"
        case .sync: return "icloud"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}
