//
//  CloudKitSyncMonitor.swift
//  AirClip
//
//  Created on 2025/12/22.
//

import Foundation
import SwiftUI
import CoreData

/// CloudKit 同步状态监听器
@MainActor
@Observable
final class CloudKitSyncMonitor {
    // MARK: - 单例
    static let shared = CloudKitSyncMonitor()

    // MARK: - 状态属性

    /// 是否正在同步
    var isSyncing = false

    /// 最后同步时间
    var lastSyncTime: Date? {
        didSet {
            if let time = lastSyncTime {
                UserDefaults.standard.set(time, forKey: "cloudkit.lastSyncTime")
            }
        }
    }

    /// 同步错误信息
    var syncError: String?

    // MARK: - 私有属性

    private var eventObserver: NSObjectProtocol?
    private var syncTimer: Timer?
    private var lastLogTime: Date?
    private var notificationCount = 0
    private var lastNotificationTime: Date?
    private var recentNotificationCount = 0

    // MARK: - 初始化

    private init() {
        // 从 UserDefaults 加载最后同步时间
        if let savedTime = UserDefaults.standard.object(forKey: "cloudkit.lastSyncTime") as? Date {
            lastSyncTime = savedTime
        }

        setupNotifications()
    }

    // MARK: - 通知监听

    private func setupNotifications() {
        let center = NotificationCenter.default

        // 监听 NSPersistentCloudKitContainer 事件
        // 这是 SwiftData CloudKit 同步的官方通知
        eventObserver = center.addObserver(
            forName: NSNotification.Name.NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRemoteChange(notification)
        }
    }

    private func handleRemoteChange(_ notification: Notification) {
        let now = Date()

        // 检查是否是短时间内的连续通知（真正的同步通常会连续触发多个通知）
        if let lastTime = lastNotificationTime, now.timeIntervalSince(lastTime) < 3.0 {
            recentNotificationCount += 1
        } else {
            // 超过3秒，重置计数
            recentNotificationCount = 1
        }
        lastNotificationTime = now

        // 打印调试信息
        let keysDescription = notification.userInfo?.keys.map { "\($0)" }.joined(separator: ", ") ?? "无"
        print("📊 远程变更通知 - 连续计数: \(recentNotificationCount), userInfo keys: \(keysDescription)")

        // 只有连续收到多个通知（>= 2）时才认为是真正的同步
        // 单个通知可能只是状态检查
        if recentNotificationCount < 2 {
            print("📊 单次通知，可能是状态检查，跳过显示同步中")
            return
        }

        // 检查通知中是否包含实际的变更数据
        let hasActualChanges = checkForActualChanges(notification)

        if !hasActualChanges {
            // 如果没有实际变更（可能只是状态检查），不显示同步中
            return
        }

        // 增加通知计数
        notificationCount += 1

        // 只在第一个通知和每10个通知时打印日志，避免刷屏
        if notificationCount == 1 || notificationCount % 10 == 0 {
            print("📥 CloudKit 远程变更通知 (共 \(notificationCount) 个)")
        }

        // 标记为正在同步
        isSyncing = true

        // 取消之前的定时器
        syncTimer?.invalidate()

        // 设置一个短暂的定时器，如果没有新的变更通知，则认为同步完成
        // SwiftData 的同步是批量的，通常会在短时间内完成
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.completeSyncCycle()
            }
        }
    }

    /// 检查通知是否包含实际的数据变更
    private func checkForActualChanges(_ notification: Notification) -> Bool {
        // 检查 userInfo 是否包含实际变更信息
        guard let userInfo = notification.userInfo else {
            print("📊 远程变更通知：无 userInfo，跳过")
            return false
        }

        // 打印 userInfo 的键，帮助调试
        if !userInfo.isEmpty {
            print("📊 远程变更通知 userInfo keys: \(userInfo.keys)")
        }

        // NSPersistentStoreRemoteChange 通知的 userInfo 可能包含：
        // - NSPersistentHistoryTokenKey: 历史记录 token
        // - storeUUID: 存储标识符
        // - 其他键值对指示变更类型

        // 如果 userInfo 为空，可能只是一个状态检查通知
        if userInfo.isEmpty {
            print("📊 远程变更通知：userInfo 为空，跳过")
            return false
        }

        // 如果有 userInfo，认为是实际的变更
        return true
    }

    private func completeSyncCycle() {
        isSyncing = false
        lastSyncTime = Date()
        syncError = nil
        print("✅ CloudKit 同步完成 (处理了 \(notificationCount) 个通知)")
        // 重置计数器
        notificationCount = 0
        recentNotificationCount = 0
    }

    // MARK: - 手动触发

    /// 手动触发同步状态更新（用于 UI 刷新）
    func refreshStatus() {
        // 如果超过 10 秒没有更新，认为同步已完成
        if let lastSync = lastSyncTime,
           Date().timeIntervalSince(lastSync) < 10 {
            isSyncing = true
        } else {
            isSyncing = false
        }
    }

    // MARK: - 清理

    // Note: 由于是单例，deinit 不会被调用，通知观察者会在应用退出时自动清理
}
