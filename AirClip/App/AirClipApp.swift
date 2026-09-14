//
//  AirClipApp.swift
//  AirClip
//
//  Created by 张佳航 on 2025/11/18.
//

import SwiftUI
import SwiftData
import AppKit
import Observation

@Observable
final class SettingsRouter {
    var selectedTab: SettingsTab = .general
}

@main
struct AirClipApp: App {
    /// 共享的 ModelContainer（设为 static 以便在其他地方访问）
    static var sharedModelContainer: ModelContainer!

    static let settingsRouter = SettingsRouter()

    @StateObject private var monitoringState: ClipboardMonitoringState

    var modelContainer: ModelContainer = {
        let schema = Schema([
            ClipboardItem.self,
            AppIcon.self,
        ])
        // 启用 SwiftData 自动 CloudKit 同步
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.example.AirClip")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // 记录详细错误信息
            print("⚠️ ModelContainer 创建失败: \(error)")
            print("错误详情: \(error.localizedDescription)")

            // 尝试恢复：删除可能损坏的存储并重新创建
            let url = modelConfiguration.url
            print("🔄 尝试重置数据存储: \(url.path)")

            // 删除所有相关的存储文件
            let fileManager = FileManager.default
            let storeFiles = [
                url,
                url.appendingPathExtension("wal"),
                url.appendingPathExtension("shm")
            ]

            for file in storeFiles {
                try? fileManager.removeItem(at: file)
                print("   删除文件: \(file.lastPathComponent)")
            }

            // 尝试使用新的存储重新创建
            do {
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("✅ 数据存储已重置并成功创建")
                return container
            } catch {
                print("❌ 重置后仍然失败: \(error)")
                // 最后手段：使用内存存储
                print("⚠️ 降级到内存存储（数据不会持久化）")
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try! ModelContainer(for: schema, configurations: [memoryConfig])
            }
        }
    }()

    /// 全局剪贴板监听器（设为 static 以便在 ContentView 中访问）
    static var clipboardMonitor: ClipboardMonitor!

    /// 左侧主面板管理（设为 static 以便在 ContentView 中访问）
    static var panelManager: MainPanelManager!

    /// 全局快捷键管理
    private let hotKeyManager = GlobalHotKeyManager.shared

    init() {
        AirClipApp.clearInAppLanguageOverrideIfNeeded()

        // 设置静态共享引用
        AirClipApp.sharedModelContainer = modelContainer

        AirClipApp.clipboardMonitor = ClipboardMonitor(modelContainer: modelContainer)
        AirClipApp.panelManager = MainPanelManager(modelContainer: modelContainer)

        _monitoringState = StateObject(
            wrappedValue: ClipboardMonitoringState(
                initialPaused: AirClipApp.clipboardMonitor?.isMonitoringPausedPublic ?? false
            )
        )

        // 预加载主面板窗口（避免首次显示时延迟）
        AirClipApp.panelManager.preloadPanel()

        // 在后台线程加载所有应用图标到内存
        let container = modelContainer
        DispatchQueue.global(qos: .userInitiated).async {
            AppIconManager.shared.loadAllIcons(modelContainer: container)
        }

        // 注册全局快捷键：唤出 / 收起左侧抽屉主面板
        hotKeyManager.onTrigger = {
            DispatchQueue.main.async {
                AirClipApp.panelManager.togglePanel()
            }
        }
    }

    private static func clearInAppLanguageOverrideIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "app_language_override") != nil || defaults.object(forKey: "AppleLanguages") != nil {
            defaults.removeObject(forKey: "AppleLanguages")
            defaults.removeObject(forKey: "app_language_override")
            defaults.synchronize()
        }
    }

    var body: some Scene {
        // 状态栏图标与菜单
        MenuBarExtra {
            StatusBarMenuView(panelManager: AirClipApp.panelManager, monitoringState: monitoringState)
        } label: {
            if monitoringState.isPaused {
                Label("AirClip", systemImage: "pause.circle.fill")
            } else {
                Label("AirClip", image: "StatusBarIcon")
            }
        }
        .modelContainer(modelContainer)
        .environment(AirClipApp.settingsRouter)

        // 设置窗口（单例，只允许打开一个）
        Window(LocalizedStringKey("settings_title"), id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 320)
        .modelContainer(modelContainer)
        .environment(AirClipApp.settingsRouter)

        // 数据管理窗口
        Window(LocalizedStringKey("data_management"), id: "data-management") {
            DataManagementView()
        }
        .defaultSize(width: 900, height: 600)
        .modelContainer(modelContainer)
        .environment(AirClipApp.settingsRouter)

        // 查看详情窗口
        WindowGroup(id: "item_detail", for: PersistentIdentifier.self) { $itemID in
            if let itemID = itemID {
                ItemDetailView(itemID: itemID)
                    .modelContainer(modelContainer)
            }
        }
        .defaultSize(width: 600, height: 500)
    }
}
