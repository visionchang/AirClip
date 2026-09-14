//
//  Item.swift
//  CopyX
//
//  Created by 张佳航 on 2025/11/18.
//

import Foundation
import SwiftData

/// 同步状态枚举
enum SyncStatus: String, Codable {
    case pending      // 等待同步
    case syncing      // 同步中
    case synced       // 已同步
    case failed       // 同步失败
    case localOnly    // 仅本地（用户选择不同步或文件类型）
}

/// 剪贴板记录模型
@Model
final class ClipboardItem {
    /// 文本内容（若为纯文本或富文本时提取的纯文本）
    var text: String?

    /// 富文本数据（RTF 格式，使用外部存储）
    @Attribute(.externalStorage)
    var rtfData: Data?

    /// 图片数据（使用外部存储，按需加载，避免启动时占用大量内存）
    @Attribute(.externalStorage)
    var imageData: Data?

    /// 预生成的缩略图数据（使用外部存储，列表显示时加载）
    @Attribute(.externalStorage)
    var thumbnailData: Data?

    /// 原始图片宽度（像素）
    var imageWidth: Int?

    /// 原始图片高度（像素）
    var imageHeight: Int?

    /// 文件URL列表（存储文件路径）
    var fileURLs: [String]?

    /// 文件名列表（用于显示）
    var fileNames: [String]?

    /// 来源应用名称（CloudKit 要求可选或有默认值）
    var appName: String = "未知应用"

    /// 来源应用 Bundle ID（可选）
    var appBundleIdentifier: String?

    /// 来源应用图标数据（小尺寸，PNG，使用外部存储按需加载）
    @Attribute(.externalStorage)
    var appIconData: Data?

    /// 复制时间（CloudKit 要求可选或有默认值）
    var createdAt: Date = Date()

    /// 内容大小（仅统计文本和图片内容的字节数，CloudKit 要求可选或有默认值）
    var contentSize: Int = 0

    /// 文本字符数（与 `text` 同步写入；列表展示「n 字符」时用此字段避免每次对全文调用 `text.count`）
    var textCharacterCount: Int = 0

    /// 是否收藏（CloudKit 要求可选或有默认值）
    var isFavorite: Bool = false

    /// 预计算的显示描述（如 "128 字符"、"1920 × 1080 像素"、"2.5 MB"）
    /// 避免渲染时重复计算
    var displayDescription: String?

    /// 动态显示描述（始终按当前系统语言生成）
    /// 注意：不要持久化本地化后的字符串，否则切换系统语言后不会更新。
    var localizedDisplayDescription: String {
        ClipboardItem.generateDisplayDescription(
            text: text,
            textCharacterCount: textCharacterCount,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            fileURLs: fileURLs,
            contentSize: contentSize
        )
    }

    // MARK: - 同步相关字段

    /// 全局唯一标识符（用于跨设备识别同一记录）
    var syncID: String?

    /// 最后修改时间（用于冲突检测）
    var modifiedAt: Date?

    /// 创建设备标识
    var sourceDeviceID: String?

    /// 创建设备名称（便于用户识别）
    var sourceDeviceName: String?

    /// 创建设备类型（mac/iPhone/iPad）
    var sourceDeviceType: String?

    /// 同步状态（存储为 String，CloudKit 兼容）
    var syncStatusRaw: String?

    /// 同步状态（计算属性）
    @Transient
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw ?? "pending") ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    /// CloudKit 记录 ID（用于关联 CKRecord）
    var cloudRecordID: String?

    /// 内容哈希值（用于快速比对和去重）
    var contentHash: String?
    
    init(
        text: String? = nil,
        rtfData: Data? = nil,
        imageData: Data? = nil,
        thumbnailData: Data? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        fileURLs: [String]? = nil,
        fileNames: [String]? = nil,
        appName: String,
        appBundleIdentifier: String? = nil,
        appIconData: Data? = nil,
        createdAt: Date = .init(),
        contentSize: Int,
        textCharacterCount: Int = 0,
        isFavorite: Bool = false,
        displayDescription: String? = nil,
        syncID: String? = nil,
        modifiedAt: Date? = nil,
        sourceDeviceID: String? = nil,
        sourceDeviceName: String? = nil,
        sourceDeviceType: String? = nil,
        syncStatus: SyncStatus = .pending,
        cloudRecordID: String? = nil,
        contentHash: String? = nil
    ) {
        self.text = text
        self.rtfData = rtfData
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.fileURLs = fileURLs
        self.fileNames = fileNames
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.appIconData = appIconData
        self.createdAt = createdAt
        self.contentSize = contentSize
        self.textCharacterCount = textCharacterCount
        self.isFavorite = isFavorite
        self.displayDescription = displayDescription
        self.syncID = syncID ?? UUID().uuidString
        self.modifiedAt = modifiedAt ?? Date()
        self.sourceDeviceID = sourceDeviceID
        self.sourceDeviceName = sourceDeviceName
        self.sourceDeviceType = sourceDeviceType
        self.syncStatusRaw = syncStatus.rawValue
        self.cloudRecordID = cloudRecordID
        self.contentHash = contentHash
    }
    
    // MARK: - 静态辅助方法
    
    /// 格式化文件大小
    static func formatSize(bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / 1024.0 / 1024.0)
        }
    }
    
    /// 生成显示描述
    static func generateDisplayDescription(
        text: String?,
        textCharacterCount: Int = 0,
        imageWidth: Int?,
        imageHeight: Int?,
        fileURLs: [String]?,
        contentSize: Int
    ) -> String {
        // 优先检查文件
        if let fileURLs = fileURLs, !fileURLs.isEmpty {
            return formatSize(bytes: contentSize)
        }
        
        // 检查图片
        if let width = imageWidth, let height = imageHeight {
            return String(format: NSLocalizedString("pixels_format", comment: "width x height pixels"), width, height)
        }

        // 文本内容
        if let text = text, !text.isEmpty {
            let count = textCharacterCount > 0 ? textCharacterCount : text.count
            return String(format: NSLocalizedString("characters_format", comment: "n characters"), count)
        }
        
        // 默认显示文件大小
        return formatSize(bytes: contentSize)
    }
}

extension ClipboardItem {
    /// 是否适合「查看详情」窗口（详情仅展示文本；文件、图片等非文字主内容隐藏入口）
    var supportsTextDetailView: Bool {
        if let fileURLs, !fileURLs.isEmpty { return false }
        if imageWidth != nil || imageHeight != nil || imageData != nil { return false }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return true }
        if rtfData != nil { return true }
        return false
    }
}

/// 应用图标存储模型（单独存储，压缩为 32x32 像素）
@Model
final class AppIcon {
    /// 应用 Bundle ID（作为标识，CloudKit 要求有默认值）
    var bundleIdentifier: String = ""

    /// 压缩后的图标数据（32x32 像素，CloudKit 要求有默认值）
    var iconData: Data = Data()

    init(bundleIdentifier: String, iconData: Data) {
        self.bundleIdentifier = bundleIdentifier
        self.iconData = iconData
    }
}
