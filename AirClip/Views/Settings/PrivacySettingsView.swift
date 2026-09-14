import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PrivacySettingsView: View {
    @State private var blockedApps: [BlockedApp] = []
    @State private var ignoredContentTypes: Set<String> = []
    @State private var ignoredKeywords: [IgnoredKeyword] = []
    @State private var selectedKeyword: IgnoredKeyword.ID? = nil
    @State private var newKeyword: String = ""
    
    var body: some View {
        Form {
            // MARK: - 忽略以下应用
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ignored_apps_info")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    
                    if blockedApps.isEmpty {
                        HStack {
                            Spacer()
                            Text("no_ignored_apps")
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 20)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(blockedApps) { app in
                                    BlockedAppRow(app: app) {
                                        removeApp(app)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 250)
                    }
                    
                    HStack {
                        Spacer()
                        Button {
                            showAppPicker()
                        } label: {
                            Label("add_app", systemImage: "plus")
                        }
                    }
                }
            } header: {
                Text("ignore_apps_header")
            }
            
            // MARK: - 忽略内容类型
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ignore_types_description")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ContentType.allCases, id: \.rawValue) { type in
                            Toggle(isOn: Binding(
                                get: { ignoredContentTypes.contains(type.rawValue) },
                                set: { isOn in
                                    if isOn {
                                        ignoredContentTypes.insert(type.rawValue)
                                    } else {
                                        ignoredContentTypes.remove(type.rawValue)
                                    }
                                    saveIgnoredContentTypes()
                                }
                            )) {
                                HStack(spacing: 8) {
                                    Image(systemName: type.icon)
                                        .foregroundStyle(type.iconColor)
                                        .frame(width: 20)
                                    Text(type.displayName)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            } header: {
                Text("ignore_types_header")
            }
            
            // MARK: - 忽略关键字
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    Text("ignore_keywords_description")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(.bottom, 12)
                    
                    // 使用系统 Table 组件，集成底部工具栏
                    VStack(spacing: 0) {
                        Table(ignoredKeywords, selection: $selectedKeyword) {
                            TableColumn("keyword_column") { keyword in
                                Text(keyword.value)
                            }
                        }
                        .tableStyle(.bordered)
                        .frame(height: 100)
                        .onDeleteCommand {
                            removeSelectedKeyword()
                        }
                        
                        // 底部工具栏，与表格集成
                        Divider()
                        
                        HStack(spacing: 0) {
                            Button {
                                showAddKeywordPopover()
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .frame(height: 16)
                            
                            Button {
                                removeSelectedKeyword()
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedKeyword == nil)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                }
            } header: {
                Text("ignore_keywords_header")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("privacy")
        .onAppear {
            loadBlockedApps()
            loadIgnoredContentTypes()
            loadIgnoredKeywords()
        }
    }
    
    private func showAddKeywordPopover() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("add_keyword_title", comment: "")
        alert.informativeText = NSLocalizedString("add_keyword_info", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("add_button", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: ""))
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = NSLocalizedString("keyword_column", comment: "")
        alert.accessoryView = textField
        
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    let keyword = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !keyword.isEmpty && !ignoredKeywords.contains(where: { $0.value == keyword }) {
                        ignoredKeywords.append(IgnoredKeyword(value: keyword))
                        saveIgnoredKeywords()
                    }
                }
            }
            // 让文本框获得焦点
            DispatchQueue.main.async {
                textField.becomeFirstResponder()
            }
        }
    }
    
    private func removeSelectedKeyword() {
        guard let selectedId = selectedKeyword,
              let index = ignoredKeywords.firstIndex(where: { $0.id == selectedId }) else { return }
        ignoredKeywords.remove(at: index)
        selectedKeyword = nil
        saveIgnoredKeywords()
    }
    
    // MARK: - 内容类型过滤
    
    private func loadIgnoredContentTypes() {
        let types = UserDefaults.standard.stringArray(forKey: PreferencesKeys.ignoredContentTypes) ?? PreferencesDefaults.ignoredContentTypes
        ignoredContentTypes = Set(types)
    }
    
    private func saveIgnoredContentTypes() {
        UserDefaults.standard.set(Array(ignoredContentTypes), forKey: PreferencesKeys.ignoredContentTypes)
    }
    
    // MARK: - 关键字过滤
    
    private func loadIgnoredKeywords() {
        let keywords = UserDefaults.standard.stringArray(forKey: PreferencesKeys.ignoredKeywords) ?? PreferencesDefaults.ignoredKeywords
        ignoredKeywords = keywords.map { IgnoredKeyword(value: $0) }
    }
    
    private func saveIgnoredKeywords() {
        let keywords = ignoredKeywords.map { $0.value }
        UserDefaults.standard.set(keywords, forKey: PreferencesKeys.ignoredKeywords)
    }
    
    private func showAppPicker() {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("select_apps_title", comment: "")
        panel.message = NSLocalizedString("select_apps_message", comment: "")
        panel.prompt = NSLocalizedString("select_button", comment: "")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.treatsFilePackagesAsDirectories = false
        
        // 获取当前窗口，作为 sheet 打开
        guard let window = NSApp.keyWindow else {
            // 如果获取不到窗口，fallback 到模态窗口
            if panel.runModal() == .OK {
                handleSelectedApps(urls: panel.urls)
            }
            return
        }
        
        panel.beginSheetModal(for: window) { response in
            if response == .OK {
                handleSelectedApps(urls: panel.urls)
            }
        }
    }
    
    private func handleSelectedApps(urls: [URL]) {
        for url in urls {
            if let bundle = Bundle(url: url),
               let bundleId = bundle.bundleIdentifier {
                let name = FileManager.default.displayName(atPath: url.path)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let app = BlockedApp(bundleIdentifier: bundleId, name: name, icon: icon)
                addApp(app)
            }
        }
    }
    
    private func loadBlockedApps() {
        // 如果从未设置过，使用默认值
        let bundleIds: [String]
        if UserDefaults.standard.object(forKey: PreferencesKeys.blockedApps) == nil {
            bundleIds = PreferencesDefaults.blockedApps
            // 保存默认值到 UserDefaults
            UserDefaults.standard.set(bundleIds, forKey: PreferencesKeys.blockedApps)
        } else {
            bundleIds = UserDefaults.standard.stringArray(forKey: PreferencesKeys.blockedApps) ?? []
        }
        
        blockedApps = bundleIds.compactMap { bundleId in
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let appName = FileManager.default.displayName(atPath: appURL.path)
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                return BlockedApp(bundleIdentifier: bundleId, name: appName, icon: icon)
            }
            // 如果找不到应用，仍然保留 bundleId
            return BlockedApp(bundleIdentifier: bundleId, name: bundleId, icon: nil)
        }
    }
    
    private func saveBlockedApps() {
        let bundleIds = blockedApps.map { $0.bundleIdentifier }
        UserDefaults.standard.set(bundleIds, forKey: PreferencesKeys.blockedApps)
    }
    
    private func addApp(_ app: BlockedApp) {
        // 避免重复添加
        guard !blockedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else {
            return
        }
        blockedApps.append(app)
        saveBlockedApps()
    }
    
    private func removeApp(_ app: BlockedApp) {
        blockedApps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
        saveBlockedApps()
    }
}

// MARK: - 屏蔽的应用模型

struct BlockedApp: Identifiable {
    let id = UUID()
    let bundleIdentifier: String
    let name: String
    let icon: NSImage?
}

// MARK: - 忽略的关键字模型

struct IgnoredKeyword: Identifiable {
    let id = UUID()
    let value: String
}

// MARK: - 屏蔽应用行视图

struct BlockedAppRow: View {
    let app: BlockedApp
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}



