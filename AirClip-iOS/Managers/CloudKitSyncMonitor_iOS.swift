//
//  CloudKitSyncMonitor_iOS.swift
//  AirClip-iOS
//
//  Lightweight CloudKitSyncMonitor for iOS target to mirror mac behavior
//

import Foundation
import CoreData

@MainActor
final class CloudKitSyncMonitor {
    static let shared = CloudKitSyncMonitor()

    /// 是否正在同步
    var isSyncing: Bool = false

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

    // MARK: - 私有
    private var eventObserver: NSObjectProtocol?
    private var syncTimer: Timer?
    private var lastNotificationTime: Date?
    private var recentNotificationCount = 0

    private init() {
        if let saved = UserDefaults.standard.object(forKey: "cloudkit.lastSyncTime") as? Date {
            lastSyncTime = saved
        }

        setupNotifications()
    }

    private func setupNotifications() {
        let center = NotificationCenter.default
        eventObserver = center.addObserver(forName: NSNotification.Name.NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] notification in
            self?.handleRemoteChange(notification)
        }
    }

    private func handleRemoteChange(_ notification: Notification) {
        let now = Date()

        if let last = lastNotificationTime, now.timeIntervalSince(last) < 3.0 {
            recentNotificationCount += 1
        } else {
            recentNotificationCount = 1
        }
        lastNotificationTime = now

        // 如果 userInfo 为空，可能只是状态检查，忽略
        let hasUserInfo = !(notification.userInfo?.isEmpty ?? true)
        if !hasUserInfo {
            return
        }

        // 只有连续多个通知时才认为是真正的同步
        if recentNotificationCount < 2 {
            return
        }

        isSyncing = true

        // 取消之前的定时器
        syncTimer?.invalidate()

        // 在短时间内没有新通知则认为同步完成
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.completeSyncCycle()
            }
        }
    }

    private func completeSyncCycle() {
        isSyncing = false
        lastSyncTime = Date()
        syncError = nil
        recentNotificationCount = 0
    }

    /// 刷新状态（UI 用）
    func refreshStatus() {
        if let last = lastSyncTime,
           Date().timeIntervalSince(last) < 10 {
            isSyncing = true
        } else {
            isSyncing = false
        }
    }

    deinit {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        syncTimer?.invalidate()
    }
}
