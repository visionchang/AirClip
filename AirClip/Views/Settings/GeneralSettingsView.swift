import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @State private var launchAtLogin: Bool = UserDefaults.standard.bool(forKey: PreferencesKeys.launchAtLogin)
    @State private var autoCloseAfterCopy: Bool = {
        if UserDefaults.standard.object(forKey: PreferencesKeys.autoCloseAfterCopy) == nil {
            return PreferencesDefaults.autoCloseAfterCopy
        }
        return UserDefaults.standard.bool(forKey: PreferencesKeys.autoCloseAfterCopy)
    }()
    @State private var doubleClickAction: DoubleClickAction = {
        let rawValue = UserDefaults.standard.integer(forKey: PreferencesKeys.doubleClickAction)
        return DoubleClickAction(rawValue: rawValue) ?? PreferencesDefaults.doubleClickAction
    }()
    @State private var alwaysPastePlainText: Bool = {
        if UserDefaults.standard.object(forKey: PreferencesKeys.alwaysPastePlainText) == nil {
            return PreferencesDefaults.alwaysPastePlainText
        }
        return UserDefaults.standard.bool(forKey: PreferencesKeys.alwaysPastePlainText)
    }()
    @State private var mainPanelEdge: MainPanelEdge = {
        if UserDefaults.standard.object(forKey: PreferencesKeys.mainPanelEdge) == nil {
            return PreferencesDefaults.mainPanelEdge
        }
        let raw = UserDefaults.standard.integer(forKey: PreferencesKeys.mainPanelEdge)
        return MainPanelEdge(rawValue: raw) ?? PreferencesDefaults.mainPanelEdge
    }()

    var body: some View {
        Form {
            Section {
                Toggle("open_at_login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(enabled: newValue)
                        UserDefaults.standard.set(newValue, forKey: PreferencesKeys.launchAtLogin)
                    }

                Toggle("auto_close_after_copy", isOn: $autoCloseAfterCopy)
                    .onChange(of: autoCloseAfterCopy) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: PreferencesKeys.autoCloseAfterCopy)
                    }

                Picker("main_panel_edge", selection: $mainPanelEdge) {
                    ForEach(MainPanelEdge.allCases, id: \.self) { edge in
                        Text(edge.displayName).tag(edge)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: mainPanelEdge) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.mainPanelEdge)
                    AirClipApp.panelManager?.rebuildPanelForEdgeChange()
                }
            }
            
            Section("paste_options") {
                Picker("double_click_action", selection: $doubleClickAction) {
                    ForEach(DoubleClickAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .onChange(of: doubleClickAction) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.doubleClickAction)
                }
                
                Toggle("always_paste_plain_text", isOn: $alwaysPastePlainText)
                    .onChange(of: alwaysPastePlainText) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: PreferencesKeys.alwaysPastePlainText)
                    }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("general")
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("设置开机启动失败: \(error)")
            }
        }
    }
}

