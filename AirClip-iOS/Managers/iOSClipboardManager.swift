//
//  iOSClipboardManager.swift
//  AirClip-iOS
//
//  Created on 2025/12/18.
//

import UIKit
import SwiftData
import CryptoKit
import UniformTypeIdentifiers

/// iOS 剪贴板管理器
@MainActor
final class iOSClipboardManager {
    static let shared = iOSClipboardManager()

    private init() {}

    /// 上次检查的剪贴板变更计数
    private var lastChangeCount: Int = 0

    /// 设备信息
    var deviceID: String {
        if let saved = UserDefaults.standard.string(forKey: PreferencesKeys.deviceID) {
            return saved
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: PreferencesKeys.deviceID)
        return newID
    }

    var deviceName: String {
        UIDevice.current.name
    }

    var deviceType: String {
        // 根据设备类型返回 "iPhone" 或 "iPad"
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return "iPhone"
        case .pad:
            return "iPad"
        default:
            return "iOS"
        }
    }

    // MARK: - 复制到剪贴板

    /// 将项目复制到系统剪贴板
    func copyItem(_ item: ClipboardItem) {
        let pasteboard = UIPasteboard.general

        // 优先复制图片
        if let imageData = item.imageData,
           let image = UIImage(data: imageData) {
            pasteboard.image = image
            return
        }

        // 复制富文本
        if let rtfData = item.rtfData {
            pasteboard.setData(rtfData, forPasteboardType: UTType.rtf.identifier)
            // 同时设置纯文本
            if let text = item.text {
                pasteboard.string = text
            }
            return
        }

        // 复制纯文本
        if let text = item.text {
            pasteboard.string = text
            return
        }
    }

    // MARK: - 检查剪贴板

    /// 检查剪贴板是否有新内容，如果有则保存
    func checkAndSaveClipboard(modelContext: ModelContext) async {
        let pasteboard = UIPasteboard.general

        // 检查是否有变化
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount

        // 检查是否有内容
        guard pasteboard.hasStrings || pasteboard.hasImages else {
            return
        }

        // 生成内容哈希用于去重
        let contentHash = generateContentHash(from: pasteboard)

        // 检查是否已存在相同内容
        if let hash = contentHash {
            let descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate<ClipboardItem> { item in
                    item.contentHash == hash
                }
            )
            if let count = try? modelContext.fetchCount(descriptor), count > 0 {
                print("📋 剪贴板内容已存在，跳过")
                return
            }
        }

        // 创建新记录
        await saveClipboardContent(pasteboard: pasteboard, modelContext: modelContext, contentHash: contentHash)
    }

    // MARK: - 保存剪贴板内容

    private func saveClipboardContent(pasteboard: UIPasteboard, modelContext: ModelContext, contentHash: String?) async {
        var text: String?
        var imageData: Data?
        var thumbnailData: Data?
        var imageWidth: Int?
        var imageHeight: Int?
        var rtfData: Data?
        var contentSize = 0

        // 提取文本
        if let string = pasteboard.string, !string.isEmpty {
            text = string
            contentSize += string.utf8.count
        }

        // 提取图片
        if let image = pasteboard.image {
            imageData = image.pngData()
            if let data = imageData {
                contentSize += data.count
            }
            imageWidth = Int(image.size.width * image.scale)
            imageHeight = Int(image.size.height * image.scale)

            // 生成缩略图
            thumbnailData = generateThumbnail(from: image)
        }

        // 提取富文本
        if let rtf = pasteboard.data(forPasteboardType: UTType.rtf.identifier) {
            rtfData = rtf
            contentSize += rtf.count
        }

        // 检查是否有实际内容（用户可能拒绝粘贴或内容为空）
        guard text != nil || imageData != nil || rtfData != nil else {
            print("📋 剪贴板内容为空，跳过保存")
            return
        }

        // 创建剪贴板项
        let item = ClipboardItem(
            text: text,
            rtfData: rtfData,
            imageData: imageData,
            thumbnailData: thumbnailData,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            appName: deviceName,  // 使用设备名称而不是 "iOS"
            createdAt: Date(),
            contentSize: contentSize,
            textCharacterCount: text.map { $0.count } ?? 0,
            displayDescription: nil,
            syncID: UUID().uuidString,
            modifiedAt: Date(),
            sourceDeviceID: deviceID,
            sourceDeviceName: deviceName,
            sourceDeviceType: deviceType,  // 添加设备类型
            syncStatus: .pending,
            contentHash: contentHash
        )

        modelContext.insert(item)

        do {
            try modelContext.save()
            print("📋 已保存剪贴板内容")

            // 通知数据变化
            NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
        } catch {
            print("⚠️ 保存剪贴板内容失败: \(error)")
        }
    }

    // MARK: - 辅助方法

    /// 生成内容哈希
    private func generateContentHash(from pasteboard: UIPasteboard) -> String? {
        var data = Data()

        if let string = pasteboard.string {
            data.append(Data(string.utf8))
        }

        if let image = pasteboard.image,
           let imageData = image.pngData() {
            // 只用前 1KB 计算哈希，避免大图片耗时
            data.append(imageData.prefix(1024))
        }

        guard !data.isEmpty else { return nil }

        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// 生成缩略图
    private func generateThumbnail(from image: UIImage, maxSize: CGFloat = 200) -> Data? {
        let size = image.size
        let scale: CGFloat

        if size.width > size.height {
            scale = maxSize / size.width
        } else {
            scale = maxSize / size.height
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return thumbnail?.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let clipboardDataDidChange = Notification.Name("clipboardDataDidChange")
}
