//
//  AirClipApp_iOS.swift
//  AirClip-iOS
//
//  Created on 2025/12/18.
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications

@main
struct AirClipApp_iOS: App {
    @UIApplicationDelegateAdaptor(AirClipAppDelegate_iOS.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    /// 共享的 ModelContainer
    static var sharedModelContainer: ModelContainer!

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
            print("⚠️ ModelContainer 创建失败: \(error)")

            // 尝试恢复：删除可能损坏的存储并重新创建
            let url = modelConfiguration.url
            let fileManager = FileManager.default
            let storeFiles = [
                url,
                url.appendingPathExtension("wal"),
                url.appendingPathExtension("shm")
            ]

            for file in storeFiles {
                try? fileManager.removeItem(at: file)
            }

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                // 最后手段：使用内存存储
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try! ModelContainer(for: schema, configurations: [memoryConfig])
            }
        }
    }()

    init() {
        AirClipApp_iOS.sharedModelContainer = modelContainer
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .modelContainer(modelContainer)
        }
    }
}
