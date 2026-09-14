//
//  iCloudSyncManager.swift
//  AirClip
//
//  Created by Claude on 2025/12/17.
//

import Foundation
import SwiftData
import CloudKit
import Network
import Observation

#if os(iOS)
import UIKit
#endif

/// 全局同步状态
enum GlobalSyncStatus: Equatable {
    case idle           // 空闲
    case syncing        // 同步中
    case synced         // 已同步
    case failed(String) // 同步失败
    case disabled       // 已禁用

    var displayName: String {
        switch self {
        case .idle: return "空闲"
        case .syncing: return "同步中"
        case .synced: return "已同步"
        case .failed(let msg): return "失败: \(msg)"
        case .disabled: return "已禁用"
        }
    }
}

/// 同步冲突通知名称
extension Notification.Name {
    static let syncConflictDetected = Notification.Name("airclip.syncConflictDetected")
    static let syncStatusChanged = Notification.Name("airclip.syncStatusChanged")
}

// MARK: - 同步数据 Actor（线程安全的数据库操作）

@ModelActor
actor SyncModelActor {

    /// 获取待上传的项目
    func fetchPendingItems() throws -> [PendingItemData] {
        let pendingRawValue = SyncStatus.pending.rawValue
        let failedRawValue = SyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { item in
                item.syncStatusRaw == pendingRawValue || item.syncStatusRaw == failedRawValue
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        let items = try modelContext.fetch(descriptor)
        return items.map { item in
            // 如果 appIconData 为空，从 AppIcon 模型获取
            var iconData = item.appIconData
            if iconData == nil, let bundleId = item.appBundleIdentifier {
                let iconDescriptor = FetchDescriptor<AppIcon>(
                    predicate: #Predicate<AppIcon> { icon in
                        icon.bundleIdentifier == bundleId
                    }
                )
                iconData = try? modelContext.fetch(iconDescriptor).first?.iconData
            }

            return PendingItemData(
                persistentModelID: item.persistentModelID,
                syncID: item.syncID,
                text: item.text,
                rtfData: item.rtfData,
                imageData: item.imageData,
                thumbnailData: item.thumbnailData,
                imageWidth: item.imageWidth,
                imageHeight: item.imageHeight,
                fileURLs: item.fileURLs,
                appName: item.appName,
                appBundleIdentifier: item.appBundleIdentifier,
                appIconData: iconData,
                createdAt: item.createdAt,
                modifiedAt: item.modifiedAt,
                contentSize: item.contentSize,
                textCharacterCount: item.textCharacterCount,
                isFavorite: item.isFavorite,
                displayDescription: item.displayDescription,
                sourceDeviceID: item.sourceDeviceID,
                sourceDeviceName: item.sourceDeviceName,
                sourceDeviceType: item.sourceDeviceType,
                contentHash: item.contentHash
            )
        }
    }

    /// 更新项目同步状态为 localOnly
    func markItemAsLocalOnly(id: PersistentIdentifier) throws {
        guard let item = modelContext.model(for: id) as? ClipboardItem else { return }
        item.syncStatus = .localOnly
        try modelContext.save()
    }

    /// 更新项目同步状态为 synced
    func markItemAsSynced(id: PersistentIdentifier, cloudRecordID: String) throws {
        guard let item = modelContext.model(for: id) as? ClipboardItem else { return }
        item.syncStatus = .synced
        item.cloudRecordID = cloudRecordID
        try modelContext.save()
    }

    /// 更新项目同步状态为 failed
    func markItemAsFailed(id: PersistentIdentifier) throws {
        guard let item = modelContext.model(for: id) as? ClipboardItem else { return }
        item.syncStatus = .failed
        try modelContext.save()
    }

    /// 设置 syncID
    func setSyncID(id: PersistentIdentifier) throws -> String {
        guard let item = modelContext.model(for: id) as? ClipboardItem else {
            return UUID().uuidString
        }
        let newSyncID = UUID().uuidString
        item.syncID = newSyncID
        try modelContext.save()
        return newSyncID
    }

    /// 查找本地是否存在指定 syncID 的项目
    func findItemBySyncID(_ syncID: String) throws -> PersistentIdentifier? {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { item in
                item.syncID == syncID
            }
        )
        let items = try modelContext.fetch(descriptor)
        return items.first?.persistentModelID
    }

    /// 获取项目的修改时间
    func getItemModifiedAt(id: PersistentIdentifier) -> Date? {
        guard let item = modelContext.model(for: id) as? ClipboardItem else { return nil }
        return item.modifiedAt
    }

    /// 更新本地项目
    func updateLocalItem(id: PersistentIdentifier, from recordData: RemoteRecordData) throws {
        guard let item = modelContext.model(for: id) as? ClipboardItem else { return }

        item.text = recordData.text
        item.appName = recordData.appName
        item.appBundleIdentifier = recordData.appBundleIdentifier
        item.isFavorite = recordData.isFavorite
        item.displayDescription = recordData.displayDescription
        item.modifiedAt = recordData.modifiedAt
        item.imageWidth = recordData.imageWidth
        item.imageHeight = recordData.imageHeight
        item.contentHash = recordData.contentHash
        item.textCharacterCount = recordData.textCharacterCount
        if item.textCharacterCount == 0, let t = item.text, !t.isEmpty {
            item.textCharacterCount = t.count
        }
        item.syncStatus = .synced

        // 更新资产数据
        if let thumbnailData = recordData.thumbnailData {
            item.thumbnailData = thumbnailData
        }
        if let imageData = recordData.imageData {
            item.imageData = imageData
        }
        if let rtfData = recordData.rtfData {
            item.rtfData = rtfData
        }
        if let appIconData = recordData.appIconData {
            item.appIconData = appIconData
        }

        // 如果有 appIconData 且存在 bundle id，upsert 到 AppIcon 模型
        if let appIconData = recordData.appIconData,
           let bundleId = recordData.appBundleIdentifier {
            let iconDescriptor = FetchDescriptor<AppIcon>(
                predicate: #Predicate<AppIcon> { icon in
                    icon.bundleIdentifier == bundleId
                }
            )
            if let existing = try? modelContext.fetch(iconDescriptor).first {
                existing.iconData = appIconData
            } else {
                let appIcon = AppIcon(bundleIdentifier: bundleId, iconData: appIconData)
                modelContext.insert(appIcon)
            }
        }

        try modelContext.save()

        // 更新内存缓存（仅在 macOS 上使用 AppIconManager）
#if os(macOS)
        if let appIconData = recordData.appIconData,
           let bundleId = recordData.appBundleIdentifier {
            AppIconManager.shared.setIcon(bundleIdentifier: bundleId, iconData: appIconData)
        }
#endif
    }

    /// 创建本地项目
    func createLocalItem(from recordData: RemoteRecordData) throws {
        let item = ClipboardItem(
            text: recordData.text,
            appName: recordData.appName,
            appBundleIdentifier: recordData.appBundleIdentifier,
            createdAt: recordData.createdAt,
            contentSize: recordData.contentSize,
            textCharacterCount: recordData.textCharacterCount,
            isFavorite: recordData.isFavorite,
            displayDescription: recordData.displayDescription,
            syncID: recordData.syncID,
            modifiedAt: recordData.modifiedAt,
            sourceDeviceID: recordData.sourceDeviceID,
            sourceDeviceName: recordData.sourceDeviceName,
            sourceDeviceType: recordData.sourceDeviceType,
            syncStatus: .synced,
            cloudRecordID: recordData.syncID,
            contentHash: recordData.contentHash
        )

        item.imageWidth = recordData.imageWidth
        item.imageHeight = recordData.imageHeight
        item.thumbnailData = recordData.thumbnailData
        item.imageData = recordData.imageData
        item.rtfData = recordData.rtfData
        item.appIconData = recordData.appIconData

        if item.textCharacterCount == 0, let t = item.text, !t.isEmpty {
            item.textCharacterCount = t.count
        }

        // 如果有 appIconData 且存在 bundle id，upsert 到 AppIcon 模型
        if let appIconData = recordData.appIconData,
           let bundleId = recordData.appBundleIdentifier {
            let iconDescriptor = FetchDescriptor<AppIcon>(
                predicate: #Predicate<AppIcon> { icon in
                    icon.bundleIdentifier == bundleId
                }
            )
            if let existing = try? modelContext.fetch(iconDescriptor).first {
                existing.iconData = appIconData
            } else {
                let appIcon = AppIcon(bundleIdentifier: bundleId, iconData: appIconData)
                modelContext.insert(appIcon)
            }
        }

        modelContext.insert(item)
        try modelContext.save()

        // 更新内存缓存（仅在 macOS 上使用 AppIconManager）
#if os(macOS)
        if let appIconData = recordData.appIconData,
           let bundleId = recordData.appBundleIdentifier {
            AppIconManager.shared.setIcon(bundleIdentifier: bundleId, iconData: appIconData)
        }
#endif
    }

    /// 获取待同步项目计数
    func getPendingCount() throws -> Int {
        let pendingRawValue = SyncStatus.pending.rawValue
        let failedRawValue = SyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { item in
                item.syncStatusRaw == pendingRawValue || item.syncStatusRaw == failedRawValue
            }
        )
        return try modelContext.fetchCount(descriptor)
    }

    /// 重置所有已同步项目为待同步状态（用于强制重新上传）
    func resetSyncedItemsToPending() throws -> Int {
        let syncedRawValue = SyncStatus.synced.rawValue
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { item in
                item.syncStatusRaw == syncedRawValue
            }
        )

        let items = try modelContext.fetch(descriptor)
        let now = Date()
        for item in items {
            item.syncStatus = .pending
            item.modifiedAt = now  // 更新修改时间，确保其他设备会重新下载
        }
        try modelContext.save()
        return items.count
    }

    /// 更新或插入 App 图标
    func upsertAppIcon(bundleId: String, iconData: Data) throws {
        let descriptor = FetchDescriptor<AppIcon>(
            predicate: #Predicate<AppIcon> { icon in
                icon.bundleIdentifier == bundleId
            }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.iconData = iconData
        } else {
            let appIcon = AppIcon(bundleIdentifier: bundleId, iconData: iconData)
            modelContext.insert(appIcon)
        }

        try modelContext.save()
    }

    /// 根据 syncID 删除本地项目
    func deleteItem(bySyncID syncID: String) throws {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { item in
                item.syncID == syncID
            }
        )

        if let item = try modelContext.fetch(descriptor).first {
            modelContext.delete(item)
            try modelContext.save()
            print("🗑️ 已删除本地项目: \(syncID)")
        } else {
            print("⚠️ 未找到要删除的本地项目: \(syncID)")
        }
    }
}

// MARK: - 数据传输对象

/// 待上传项目数据（用于跨 actor 边界传递）
struct PendingItemData: Sendable {
    let persistentModelID: PersistentIdentifier
    let syncID: String?
    let text: String?
    let rtfData: Data?
    let imageData: Data?
    let thumbnailData: Data?
    let imageWidth: Int?
    let imageHeight: Int?
    let fileURLs: [String]?
    let appName: String
    let appBundleIdentifier: String?
    let appIconData: Data?
    let createdAt: Date
    let modifiedAt: Date?
    let contentSize: Int
    let textCharacterCount: Int
    let isFavorite: Bool
    let displayDescription: String?
    let sourceDeviceID: String?
    let sourceDeviceName: String?
    let sourceDeviceType: String?
    let contentHash: String?

    var hasFiles: Bool {
        fileURLs != nil && !(fileURLs?.isEmpty ?? true)
    }
}

/// 远程记录数据（用于跨 actor 边界传递）
struct RemoteRecordData: Sendable {
    let syncID: String
    let text: String?
    let appName: String
    let appBundleIdentifier: String?
    let createdAt: Date
    let modifiedAt: Date
    let contentSize: Int
    let textCharacterCount: Int
    let isFavorite: Bool
    let displayDescription: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let sourceDeviceID: String?
    let sourceDeviceName: String?
    let sourceDeviceType: String?
    let contentHash: String?
    var thumbnailData: Data?
    var imageData: Data?
    var rtfData: Data?
    var appIconData: Data?
}

// MARK: - iCloud 同步管理器

/// iCloud 同步管理器
@MainActor
@Observable
final class iCloudSyncManager {

    // MARK: - 可观察属性

    var syncStatus: GlobalSyncStatus = .idle
    var lastSyncTime: Date?
    var pendingItemsCount: Int = 0
    var iCloudAvailable: Bool = false
    var accountStatus: CKAccountStatus = .couldNotDetermine

    // MARK: - 私有属性

    private let modelContainer: ModelContainer
    private let cloudContainer: CKContainer
    private let privateDatabase: CKDatabase
    private var syncActor: SyncModelActor?

    private var networkMonitor: NWPathMonitor?
    private var isNetworkAvailable: Bool = true
    private var isSyncing: Bool = false
    private var accountObserver: NSObjectProtocol?
    private var ubiquityObserver: NSObjectProtocol?

    /// CloudKit 记录类型
    private let recordType = "ClipboardItem"
    private let appIconRecordType = "AppIcon"

    /// 已同步的 App 图标 bundleId 缓存
    private var syncedAppIconBundleIds: Set<String> = []

    /// 当前设备信息
    var deviceID: String {
        if let saved = UserDefaults.standard.string(forKey: PreferencesKeys.deviceID) {
            return saved
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: PreferencesKeys.deviceID)
        return newID
    }

    var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        UIDevice.current.name
        #endif
    }

    /// 是否启用同步
    var isSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferencesKeys.iCloudSyncEnabled)
    }

    // MARK: - 单例

    static var shared: iCloudSyncManager?

    // MARK: - 初始化

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.cloudContainer = CKContainer(identifier: "iCloud.com.example.AirClip")
        self.privateDatabase = cloudContainer.privateCloudDatabase

        // 创建 SyncModelActor
        self.syncActor = SyncModelActor(modelContainer: modelContainer)

        setupNetworkMonitoring()
        checkiCloudStatus()

        // 监听 CloudKit / iCloud 账户变化，实时更新状态（替代外部轮询）
        let center = NotificationCenter.default
        accountObserver = center.addObserver(forName: Notification.Name.CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            print("📡 CKAccountChanged received, rechecking iCloud status")
            self?.checkiCloudStatus()
        }
        ubiquityObserver = center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            print("📡 NSUbiquityIdentityDidChange received, rechecking iCloud status")
            self?.checkiCloudStatus()
        }

        print("ℹ️ 初始化 iCloudSyncManager, container: iCloud.com.example.AirClip")

        // 加载上次同步时间
        if let lastSync = UserDefaults.standard.object(forKey: PreferencesKeys.lastSyncTime) as? Date {
            self.lastSyncTime = lastSync
        }
    }

    // MARK: - iCloud 状态检查

    func checkiCloudStatus() {
        cloudContainer.accountStatus { [weak self] status, error in
            Task { @MainActor in
                self?.accountStatus = status
                self?.iCloudAvailable = (status == .available)

                if let error = error {
                    print("⚠️ iCloud 状态检查失败: \(error)")
                    if let ck = error as? CKError {
                        print("    CKError code: \(ck.code) userInfo: \(ck.userInfo)")
                    }
                }

                print("🔎 iCloud account status: \(status) (rawValue=\(status.rawValue))")
                // 如果 iCloud 可用且启用了同步，自动开始
                if status == .available && self?.isSyncEnabled == true {
                    self?.startAutoSync()
                }
            }
        }
    }

    // MARK: - 同步控制

    /// 启动同步（订阅远程变更）
    func startAutoSync() {
        guard iCloudAvailable else {
            print("⚠️ iCloud 不可用，无法启动同步")
            return
        }

        // 立即执行一次同步
        Task {
            await performSync()
            // 调试：列出 private 数据库中 ClipboardItem 记录
            await self.debugListPrivateClipboardRecords()
        }

        // 订阅远程变更通知
        subscribeToRemoteChanges()

        print("✅ iCloud 同步已启动")
    }

    /// 调试方法：列出 private 数据库中 ClipboardItem 记录（打印计数与前 20 个 recordName）
    func debugListPrivateClipboardRecords() async {
        print("ℹ️ 开始调试查询 private ClipboardItem 记录")

        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var ids: [String] = []

            let op = CKQueryOperation(query: query)
            op.recordFetchedBlock = { record in
                ids.append(record.recordID.recordName)
            }

            op.queryCompletionBlock = { cursor, error in
                if let error = error {
                    print("⚠️ Debug query error: \(error)")
                    if let ck = error as? CKError {
                        print("    CKError code: \(ck.code) userInfo: \(ck.userInfo)")
                    }
                }

                print("ℹ️ Debug found \(ids.count) ClipboardItem records. IDs (first 20): \(Array(ids.prefix(20)))")
                continuation.resume()
            }

            privateDatabase.add(op)
        }
    }

    /// 停止同步
    func stopAutoSync() {
        syncStatus = .disabled
        print("🛑 iCloud 同步已停止")
    }

    /// 执行同步
    func performSync() async {
        guard iCloudAvailable && isNetworkAvailable else {
            print("⚠️ 网络不可用或 iCloud 未登录，跳过同步")
            return
        }

        guard !isSyncing else {
            print("⏳ 同步正在进行中，跳过")
            return
        }

        isSyncing = true
        syncStatus = .syncing

        do {
            // 1. 上传本地变更
            try await uploadLocalChanges()

            // 2. 下载远程变更
            try await downloadRemoteChanges()

            syncStatus = .synced
            lastSyncTime = Date()
            UserDefaults.standard.set(lastSyncTime, forKey: PreferencesKeys.lastSyncTime)

            // 更新待同步计数
            await updatePendingCount()

            print("✅ 同步完成")
        } catch {
            syncStatus = .failed(error.localizedDescription)
            print("❌ 同步失败: \(error)")
            if let ck = error as? CKError {
                print("    CKError code: \(ck.code) userInfo: \(ck.userInfo)")
            }
        }

        isSyncing = false
    }

    // MARK: - 上传逻辑

    private func uploadLocalChanges() async throws {
        guard let syncActor = syncActor else { return }

        // 在 actor 中获取待上传项目
        let pendingItems = try await syncActor.fetchPendingItems()
        print("📤 待上传项目数: \(pendingItems.count)")

        for itemData in pendingItems {
            // 跳过文件类型（路径在不同设备不通用）
            if itemData.hasFiles {
                try? await syncActor.markItemAsLocalOnly(id: itemData.persistentModelID)
                continue
            }

            do {
                try await uploadItem(itemData)
            } catch {
                print("⚠️ 上传项目失败: \(error)")
                try? await syncActor.markItemAsFailed(id: itemData.persistentModelID)
            }
        }
    }

    private func uploadItem(_ itemData: PendingItemData) async throws {
        guard let syncActor = syncActor else { return }

        // 确保有 syncID
        var syncID = itemData.syncID
        if syncID == nil {
            syncID = try await syncActor.setSyncID(id: itemData.persistentModelID)
            return
        }

        guard let finalSyncID = syncID else { return }

        // 创建 CloudKit 记录
        let recordID = CKRecord.ID(recordName: finalSyncID)

        // 先检查是否已存在（更新而非创建）
        var record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            // 记录不存在或获取失败，打印错误以便诊断
            print("ℹ️ record fetch for \(recordID.recordName) failed: \(error)")
            if let ck = error as? CKError {
                print("    CKError code: \(ck.code) userInfo: \(ck.userInfo)")
            }
            // 记录不存在，创建新记录
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        // 设置元数据字段
        record["text"] = itemData.text as CKRecordValue?
        record["appName"] = itemData.appName as CKRecordValue
        record["appBundleIdentifier"] = itemData.appBundleIdentifier as CKRecordValue?
        record["createdAt"] = itemData.createdAt as CKRecordValue
        record["modifiedAt"] = (itemData.modifiedAt ?? Date()) as CKRecordValue
        record["contentSize"] = itemData.contentSize as CKRecordValue
        record["textCharacterCount"] = itemData.textCharacterCount as CKRecordValue
        record["isFavorite"] = itemData.isFavorite as CKRecordValue
        record["displayDescription"] = itemData.displayDescription as CKRecordValue?
        record["imageWidth"] = itemData.imageWidth as CKRecordValue?
        record["imageHeight"] = itemData.imageHeight as CKRecordValue?
        record["sourceDeviceID"] = itemData.sourceDeviceID as CKRecordValue?
        record["sourceDeviceName"] = itemData.sourceDeviceName as CKRecordValue?
        record["sourceDeviceType"] = itemData.sourceDeviceType as CKRecordValue?
        record["contentHash"] = itemData.contentHash as CKRecordValue?

        // 处理大文件（图片/RTF/缩略图）- 使用 CKAsset
        if let imageData = itemData.imageData, shouldSyncImages() {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("data")
            try imageData.write(to: tempURL)
            record["imageAsset"] = CKAsset(fileURL: tempURL)
        }

        if let rtfData = itemData.rtfData, shouldSyncRTF() {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("rtf")
            try rtfData.write(to: tempURL)
            record["rtfAsset"] = CKAsset(fileURL: tempURL)
        }

        if let thumbnailData = itemData.thumbnailData {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            try thumbnailData.write(to: tempURL)
            record["thumbnailAsset"] = CKAsset(fileURL: tempURL)
        }

        // 保存到 CloudKit
        let _ = try await privateDatabase.save(record)

        // 单独上传 App 图标（如果有且未同步过）
        if let appIconData = itemData.appIconData,
           let bundleId = itemData.appBundleIdentifier,
           !syncedAppIconBundleIds.contains(bundleId) {
            try await uploadAppIcon(bundleId: bundleId, iconData: appIconData)
        }

        // 更新本地状态
        try await syncActor.markItemAsSynced(id: itemData.persistentModelID, cloudRecordID: record.recordID.recordName)

        print("📤 已上传: \(finalSyncID)")
    }

    /// 上传 App 图标
    private func uploadAppIcon(bundleId: String, iconData: Data) async throws {
        let recordID = CKRecord.ID(recordName: "appicon-\(bundleId)")

        // 检查是否已存在
        var record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
            print("📤 App 图标已存在: \(bundleId)")
            syncedAppIconBundleIds.insert(bundleId)
            return
        } catch {
            record = CKRecord(recordType: appIconRecordType, recordID: recordID)
        }

        record["bundleIdentifier"] = bundleId as CKRecordValue

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try iconData.write(to: tempURL)
        record["iconAsset"] = CKAsset(fileURL: tempURL)

        let _ = try await privateDatabase.save(record)
        syncedAppIconBundleIds.insert(bundleId)
        print("📤 已上传 App 图标: \(bundleId), \(iconData.count) bytes")
    }

    // MARK: - 下载逻辑

    private func downloadRemoteChanges() async throws {
        // 检查是否已完成首次同步
        let hasCompletedInitialSync = UserDefaults.standard.bool(forKey: PreferencesKeys.hasCompletedInitialSync)
        let savedToken = getSavedServerChangeToken()

        print("ℹ️ hasCompletedInitialSync: \(hasCompletedInitialSync), hasToken: \(savedToken != nil)")

        // 如果已完成首次同步但没有 change token，说明是旧版本升级，需要重新初始化
        if hasCompletedInitialSync && savedToken == nil {
            print("⚠️ 检测到旧版本数据，重置同步状态")
            resetSyncState()
        }

        // 重新检查状态
        let needsFullSync = !UserDefaults.standard.bool(forKey: PreferencesKeys.hasCompletedInitialSync)

        if needsFullSync {
            // 首次同步：获取所有记录
            print("📥 首次同步，获取所有记录")
            try await downloadAllRecordsViaQuery()
        } else {
            // 增量同步：使用 change token 获取变更
            print("📥 增量同步，获取变更记录")
            try await downloadIncrementalChanges()
        }
    }

    /// 增量同步：获取自上次同步以来的新记录和删除记录
    private func downloadIncrementalChanges() async throws {
        let zoneID = CKRecordZone.default().zoneID

        // 获取上次保存的 change token
        let previousToken = getSavedServerChangeToken()
        print("📥 增量同步，使用 change token: \(previousToken != nil ? "有" : "无")")

        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = previousToken

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: configuration]
        )

        var records: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false

            // 处理新增/修改的记录
            operation.recordWasChangedBlock = { _, result in
                switch result {
                case .success(let record):
                    records.append(record)
                    print("  📦 记录变更: \(record.recordID.recordName)")
                case .failure(let error):
                    print("  ⚠️ 记录变更失败: \(error)")
                }
            }

            // 处理删除的记录
            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                deletedRecordIDs.append(recordID)
                print("  🗑️ 记录已删除: \(recordID.recordName)")
            }

            // 保存新的 change token
            operation.recordZoneChangeTokensUpdatedBlock = { [weak self] _, token, _ in
                if let token = token {
                    Task { @MainActor in
                        self?.saveServerChangeToken(token)
                        print("  💾 已更新 change token")
                    }
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                guard !hasResumed else { return }
                hasResumed = true

                switch result {
                case .success:
                    print("📥 增量同步完成：\(records.count) 条新增/修改，\(deletedRecordIDs.count) 条删除")
                    continuation.resume()
                case .failure(let error):
                    print("⚠️ 增量同步失败: \(error)")
                    continuation.resume(throwing: error)
                }
            }

            privateDatabase.add(operation)
        }

        // 处理新增/修改的记录
        for record in records {
            let recordData = extractRecordData(from: record)
            try await processExtractedRecord(recordData)
        }

        // 处理删除的记录
        for recordID in deletedRecordIDs {
            let syncID = recordID.recordName
            try await deleteLocalItem(bySyncID: syncID)
        }

        print("✅ 增量同步处理完成")
    }

    /// 根据 syncID 删除本地项目
    private func deleteLocalItem(bySyncID syncID: String) async throws {
        let actor = await SyncModelActor(modelContainer: modelContainer)
        try await actor.deleteItem(bySyncID: syncID)
    }

    /// 同步提取记录数据（包括 asset 数据）- 必须在回调中同步调用
    private func extractRecordData(from record: CKRecord) -> RemoteRecordData {
        let syncID = record.recordID.recordName
        print("📦 同步提取记录数据: \(syncID)")

        var recordData = RemoteRecordData(
            syncID: syncID,
            text: record["text"] as? String,
            appName: record["appName"] as? String ?? "Unknown",
            appBundleIdentifier: record["appBundleIdentifier"] as? String,
            createdAt: record["createdAt"] as? Date ?? Date(),
            modifiedAt: record["modifiedAt"] as? Date ?? Date(),
            contentSize: record["contentSize"] as? Int ?? 0,
            textCharacterCount: record["textCharacterCount"] as? Int ?? 0,
            isFavorite: record["isFavorite"] as? Bool ?? false,
            displayDescription: record["displayDescription"] as? String,
            imageWidth: record["imageWidth"] as? Int,
            imageHeight: record["imageHeight"] as? Int,
            sourceDeviceID: record["sourceDeviceID"] as? String,
            sourceDeviceName: record["sourceDeviceName"] as? String,
            sourceDeviceType: record["sourceDeviceType"] as? String,
            contentHash: record["contentHash"] as? String
        )

        // 同步读取缩略图
        if let thumbnailAsset = record["thumbnailAsset"] as? CKAsset,
           let fileURL = thumbnailAsset.fileURL {
            do {
                recordData.thumbnailData = try Data(contentsOf: fileURL)
                print("  ✅ 缩略图: \(recordData.thumbnailData?.count ?? 0) bytes")
            } catch {
                print("  ⚠️ 缩略图读取失败: \(error)")
            }
        }

        // 同步读取图片
        if shouldSyncImages(),
           let imageAsset = record["imageAsset"] as? CKAsset,
           let fileURL = imageAsset.fileURL {
            do {
                recordData.imageData = try Data(contentsOf: fileURL)
                print("  ✅ 图片: \(recordData.imageData?.count ?? 0) bytes")
            } catch {
                print("  ⚠️ 图片读取失败: \(error)")
            }
        }

        // 同步读取 RTF
        if shouldSyncRTF(),
           let rtfAsset = record["rtfAsset"] as? CKAsset,
           let fileURL = rtfAsset.fileURL {
            do {
                recordData.rtfData = try Data(contentsOf: fileURL)
                print("  ✅ RTF: \(recordData.rtfData?.count ?? 0) bytes")
            } catch {
                print("  ⚠️ RTF读取失败: \(error)")
            }
        }

        // 同步读取应用图标（兼容旧记录，新记录图标在 AppIcon 表中单独存储）
        if let appIconAsset = record["appIconAsset"] as? CKAsset,
           let fileURL = appIconAsset.fileURL {
            do {
                recordData.appIconData = try Data(contentsOf: fileURL)
                print("  ✅ 应用图标(旧格式): \(recordData.appIconData?.count ?? 0) bytes")
            } catch {
                print("  ⚠️ 应用图标读取失败: \(error)")
            }
        }

        print("📦 提取完成 - appIconData: \(recordData.appIconData != nil ? "\(recordData.appIconData!.count) bytes" : "nil")")
        return recordData
    }

    /// 处理已提取的记录数据
    private func processExtractedRecord(_ recordData: RemoteRecordData) async throws {
        guard let syncActor = syncActor else { return }

        let syncID = recordData.syncID
        print("🔄 处理远程记录: \(syncID)")

        // 检查是否是当前设备创建的记录
        if let sourceDeviceID = recordData.sourceDeviceID,
           sourceDeviceID == deviceID {
            print("  ⏭️ 跳过自己创建的记录")
            return
        }

        // 查找本地是否存在
        let existingItemID = try await syncActor.findItemBySyncID(syncID)

        if let itemID = existingItemID {
            // 已存在，检查是否需要更新
            let localModifiedAt = await syncActor.getItemModifiedAt(id: itemID)
            print("  📍 本地已存在，localModifiedAt: \(String(describing: localModifiedAt)), remoteModifiedAt: \(recordData.modifiedAt)")
            if recordData.modifiedAt > (localModifiedAt ?? Date.distantPast) {
                print("  📥 执行更新，appIconData: \(recordData.appIconData != nil ? "\(recordData.appIconData!.count) bytes" : "nil")")
                try await syncActor.updateLocalItem(id: itemID, from: recordData)
                print("📥 已更新: \(syncID)")
            } else {
                print("  ⏭️ 本地更新，跳过远程更新")
            }
        } else {
            print("  📥 执行创建，appIconData: \(recordData.appIconData != nil ? "\(recordData.appIconData!.count) bytes" : "nil")")
            try await syncActor.createLocalItem(from: recordData)

            await MainActor.run {
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
            print("📥 已创建: \(syncID)")
        }
    }

    /// 处理下载的 App 图标记录
    private func processAppIconRecord(bundleId: String, iconData: Data) async {
        guard let syncActor = syncActor else { return }

        print("📥 处理 App 图标: \(bundleId), \(iconData.count) bytes")

        do {
            try await syncActor.upsertAppIcon(bundleId: bundleId, iconData: iconData)
            syncedAppIconBundleIds.insert(bundleId)

            // 更新内存缓存（仅在 macOS 上）
            #if os(macOS)
            AppIconManager.shared.setIcon(bundleIdentifier: bundleId, iconData: iconData)
            #endif

            print("📥 已保存 App 图标: \(bundleId)")
        } catch {
            print("⚠️ 保存 App 图标失败: \(error)")
        }
    }

    // MARK: - 首次同步（CKQueryOperation）

    /// 使用 CKQueryOperation 下载所有记录（用于首次同步）
    private func downloadAllRecordsViaQuery() async throws {
        print("📥 开始查询所有 ClipboardItem 记录...")

        // 查询所有 ClipboardItem 记录
        let clipboardQuery = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        clipboardQuery.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        var allRecords: [CKRecord] = []

        // 使用 continuation 来等待查询完成
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false

            let operation = CKQueryOperation(query: clipboardQuery)
            operation.resultsLimit = CKQueryOperation.maximumResults

            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    allRecords.append(record)
                case .failure(let error):
                    print("⚠️ 记录匹配失败: \(error)")
                }
            }

            operation.queryResultBlock = { result in
                guard !hasResumed else { return }
                hasResumed = true

                switch result {
                case .success:
                    print("📥 查询完成，共获取 \(allRecords.count) 条 ClipboardItem 记录")
                    continuation.resume()
                case .failure(let error):
                    print("⚠️ 查询失败: \(error)")
                    if let ck = error as? CKError {
                        print("    CKError code: \(ck.code) userInfo: \(ck.userInfo)")
                    }
                    continuation.resume(throwing: error)
                }
            }

            privateDatabase.add(operation)
        }

        // 处理所有获取到的记录
        for record in allRecords {
            let recordData = extractRecordData(from: record)
            try await processExtractedRecord(recordData)
        }

        // 查询所有 AppIcon 记录
        print("📥 开始查询所有 AppIcon 记录...")

        let appIconQuery = CKQuery(recordType: appIconRecordType, predicate: NSPredicate(value: true))
        var appIconRecords: [CKRecord] = []

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false

            let operation = CKQueryOperation(query: appIconQuery)
            operation.resultsLimit = CKQueryOperation.maximumResults

            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    appIconRecords.append(record)
                case .failure(let error):
                    print("⚠️ AppIcon 记录匹配失败: \(error)")
                }
            }

            operation.queryResultBlock = { result in
                guard !hasResumed else { return }
                hasResumed = true

                switch result {
                case .success:
                    print("📥 AppIcon 查询完成，共获取 \(appIconRecords.count) 条记录")
                    continuation.resume()
                case .failure(let error):
                    print("⚠️ AppIcon 查询失败: \(error)")
                    // 不抛出错误，AppIcon 查询失败不应阻止同步
                    continuation.resume()
                }
            }

            privateDatabase.add(operation)
        }

        // 处理 AppIcon 记录
        for record in appIconRecords {
            if let bundleId = record["bundleIdentifier"] as? String,
               let iconAsset = record["iconAsset"] as? CKAsset,
               let fileURL = iconAsset.fileURL,
               let iconData = try? Data(contentsOf: fileURL) {
                await processAppIconRecord(bundleId: bundleId, iconData: iconData)
            }
        }

        // 标记首次同步已完成
        UserDefaults.standard.set(true, forKey: PreferencesKeys.hasCompletedInitialSync)
        print("✅ 首次同步全部完成，已标记 hasCompletedInitialSync = true")
    }

    /// 获取初始 change token（不处理记录，仅保存 token）
    private func fetchInitialChangeToken() async throws {
        let zoneID = CKRecordZone.default().zoneID

        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = nil

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: configuration]
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false

            // 忽略记录变更，我们只需要获取 token
            operation.recordWasChangedBlock = { _, _ in }

            operation.recordZoneChangeTokensUpdatedBlock = { [weak self] _, token, _ in
                Task { @MainActor in
                    self?.saveServerChangeToken(token)
                    print("📥 已保存初始 change token")
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                guard !hasResumed else { return }
                hasResumed = true

                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    // token 获取失败不应阻止同步完成
                    print("⚠️ 获取初始 change token 失败: \(error)")
                    continuation.resume()
                }
            }

            privateDatabase.add(operation)
        }
    }

    // MARK: - 远程变更订阅

    private func subscribeToRemoteChanges() {
        let subscriptionID = "all-changes-subscription"

        // 先检查是否已订阅
        privateDatabase.fetch(withSubscriptionID: subscriptionID) { [weak self] subscription, error in
            if let error = error {
                print("⚠️ 检查订阅状态失败: \(error)")
                if let ck = error as? CKError {
                    print("    CKError code: \(ck.code.rawValue) - \(ck.localizedDescription)")
                }
            }

            if subscription != nil {
                print("📡 已存在远程变更订阅: \(subscriptionID)")
                return
            }

            print("📡 创建新的远程变更订阅...")

            // 创建新订阅
            let newSubscription = CKDatabaseSubscription(subscriptionID: subscriptionID)

            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            newSubscription.notificationInfo = notificationInfo

            self?.privateDatabase.save(newSubscription) { savedSubscription, error in
                if let error = error {
                    print("⚠️ 订阅失败: \(error)")
                    if let ck = error as? CKError {
                        print("    CKError code: \(ck.code.rawValue) - \(ck.localizedDescription)")
                    }
                } else {
                    print("📡 已创建远程变更订阅: \(savedSubscription?.subscriptionID ?? "unknown")")
                }
            }
        }
    }

    /// 处理远程通知（从 AppDelegate 调用）
    func handleRemoteNotification() {
        guard isSyncEnabled && iCloudAvailable else { return }

        Task {
            await performSync()
        }
    }

    // MARK: - 删除同步

    /// 删除本地项目时同步删除云端记录
    func deleteCloudRecord(syncID: String) async {
        guard iCloudAvailable else { return }

        let recordID = CKRecord.ID(recordName: syncID)

        do {
            try await privateDatabase.deleteRecord(withID: recordID)
            print("🗑️ 已删除云端记录: \(syncID)")
        } catch {
            print("⚠️ 删除云端记录失败: \(error)")
        }
    }

    // MARK: - 辅助方法

    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isNetworkAvailable = (path.status == .satisfied)
            }
        }
        networkMonitor?.start(queue: DispatchQueue.global(qos: .utility))
    }

    private func getSavedServerChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: PreferencesKeys.serverChangeToken) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveServerChangeToken(_ token: CKServerChangeToken?) {
        guard let token = token else {
            UserDefaults.standard.removeObject(forKey: PreferencesKeys.serverChangeToken)
            return
        }

        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: PreferencesKeys.serverChangeToken)
        }
    }

    private func updatePendingCount() async {
        guard let syncActor = syncActor else { return }

        if let count = try? await syncActor.getPendingCount() {
            pendingItemsCount = count
        }
    }

    private func shouldSyncImages() -> Bool {
        UserDefaults.standard.object(forKey: PreferencesKeys.syncImages) as? Bool
            ?? PreferencesDefaults.syncImages
    }

    private func shouldSyncRTF() -> Bool {
        UserDefaults.standard.object(forKey: PreferencesKeys.syncRTF) as? Bool
            ?? PreferencesDefaults.syncRTF
    }

    /// 清除所有 iCloud 同步数据
    func clearAllCloudData() async {
        guard let syncActor = syncActor else { return }

        do {
            // 1. 重置所有本地项目的同步状态为 pending
            let count = try await syncActor.resetSyncedItemsToPending()
            print("📤 已重置 \(count) 个项目为待同步状态")

            // 2. 清除本地存储的 change token 和首次同步标记
            saveServerChangeToken(nil)
            UserDefaults.standard.set(false, forKey: PreferencesKeys.hasCompletedInitialSync)

            // 3. 清除已同步的图标缓存
            syncedAppIconBundleIds.removeAll()

            // 4. 更新待同步计数
            await updatePendingCount()

            print("✅ iCloud 同步数据已清除，下次同步将重新上传所有数据")
        } catch {
            print("⚠️ 清除同步数据失败: \(error)")
        }
    }

    /// 强制重新下载所有数据（清除 change token 和首次同步标记）
    func forceRedownload() {
        saveServerChangeToken(nil)
        UserDefaults.standard.set(false, forKey: PreferencesKeys.hasCompletedInitialSync)
        syncedAppIconBundleIds.removeAll()
        print("✅ 已清除同步标记，下次同步将重新下载所有数据")
    }

    // MARK: - 重置和清理

    /// 重置同步状态（重新触发完整同步）
    func resetSyncState() {
        UserDefaults.standard.removeObject(forKey: PreferencesKeys.hasCompletedInitialSync)
        UserDefaults.standard.removeObject(forKey: PreferencesKeys.serverChangeToken)
        UserDefaults.standard.removeObject(forKey: PreferencesKeys.lastSyncTime)
        lastSyncTime = nil
        print("🔄 已重置同步状态，下次同步将执行完整同步")
    }

    // MARK: - 清理

    /// 清理资源（在应用退出前调用）
    func cleanup() {
        networkMonitor?.cancel()
        networkMonitor = nil
        if let obs = accountObserver {
            NotificationCenter.default.removeObserver(obs)
            accountObserver = nil
        }
        if let obs = ubiquityObserver {
            NotificationCenter.default.removeObserver(obs)
            ubiquityObserver = nil
        }
    }
}
