//
//  DataMigrationManager.swift
//  CopyX
//
//  历史数据迁移：
//  1. 为所有记录生成高清缩略图（600px）
//  2. 生成图片尺寸信息和显示描述
//  3. 将图片数据迁移到外部存储（@Attribute(.externalStorage)）
//     - 保存时 SwiftData 会自动将 imageData/thumbnailData 移到外部文件
//     - 这样 @Query 加载时不会立即读取大型二进制数据
//

import Foundation
import SwiftData
import AppKit
import ImageIO
import Combine

/// 迁移状态
enum MigrationStatus: Equatable {
    case idle
    case running(progress: Int, total: Int)
    case completed(success: Int, failed: Int)
    case error(String)
}

/// 数据迁移管理器
/// 
/// 迁移完成后的效果：
/// - 列表加载时：只读取轻量级字段（text, displayDescription 等）
/// - 显示缩略图时：按需加载 thumbnailData（外部存储）
/// - 复制原图时：按需加载 imageData（外部存储）
final class DataMigrationManager: ObservableObject {
    
    private let modelContainer: ModelContainer
    
    /// 缩略图最大尺寸（像素）
    private let thumbnailMaxSize: CGFloat = 600
    
    @Published var status: MigrationStatus = .idle
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    /// 获取所有记录数量（用于完整迁移）
    func getTotalItemCount() -> Int {
        let context = modelContainer.mainContext
        let fetchDescriptor = FetchDescriptor<ClipboardItem>()
        return (try? context.fetchCount(fetchDescriptor)) ?? 0
    }
    
    /// 获取需要迁移的记录数量（没有 displayDescription 的记录）
    func getPendingMigrationCount() -> Int {
        let context = modelContainer.mainContext
        
        // 查找没有 displayDescription 的记录
        let fetchDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { item in
                item.displayDescription == nil
            }
        )
        
        return (try? context.fetchCount(fetchDescriptor)) ?? 0
    }
    
    /// 执行完整迁移：
    /// 1. 重新生成高清缩略图（600px）
    /// 2. 生成图片尺寸和显示描述
    /// 3. 保存时自动迁移到外部存储格式
    func performFullMigration() {
        let context = modelContainer.mainContext
        
        // 获取所有记录
        let fetchDescriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        guard let allItems = try? context.fetch(fetchDescriptor) else {
            DispatchQueue.main.async {
                self.status = .error("获取记录失败")
            }
            return
        }
        
        if allItems.isEmpty {
            DispatchQueue.main.async {
                self.status = .completed(success: 0, failed: 0)
            }
            return
        }
        
        let total = allItems.count
        print("📦 开始完整迁移，共 \(total) 条记录")
        print("   - 生成高清缩略图 (600px)")
        print("   - 迁移到外部存储格式")
        
        DispatchQueue.main.async {
            self.status = .running(progress: 0, total: total)
        }
        
        // 在后台线程执行迁移
        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            let failCount = 0
            
            for (index, item) in allItems.enumerated() {
                // 判断是否是图片数据
                let isImageItem = item.imageData != nil
                
                if isImageItem {
                    // ===== 图片数据处理 =====
                    if let imageData = item.imageData {
                        // 获取图片尺寸
                        if let imageInfo = self.getImageInfo(from: imageData) {
                            item.imageWidth = imageInfo.width
                            item.imageHeight = imageInfo.height
                        }
                        
                        // 生成高清缩略图（600px）
                        if let thumbnailData = self.createThumbnail(from: imageData, maxSize: self.thumbnailMaxSize) {
                            item.thumbnailData = thumbnailData
                        }
                    }
                } else {
                    // ===== 非图片数据（文本/文件）处理 =====
                    // 确保非图片数据没有缩略图和图片尺寸信息
                    item.thumbnailData = nil
                    item.imageWidth = nil
                    item.imageHeight = nil
                }

                if item.textCharacterCount == 0, let t = item.text, !t.isEmpty {
                    item.textCharacterCount = t.count
                }
                
                // 生成显示描述（所有类型都需要）
                let displayDesc = ClipboardItem.generateDisplayDescription(
                    text: item.text,
                    textCharacterCount: item.textCharacterCount,
                    imageWidth: item.imageWidth,
                    imageHeight: item.imageHeight,
                    fileURLs: item.fileURLs,
                    contentSize: item.contentSize
                )
                item.displayDescription = displayDesc
                
                successCount += 1
                
                // 更新进度（每5条或最后一条时更新UI）
                if index % 5 == 0 || index == total - 1 {
                    let currentIndex = index
                    DispatchQueue.main.async {
                        self.status = .running(progress: currentIndex + 1, total: total)
                    }
                }
            }
            
            // 保存更改（在主线程）
            DispatchQueue.main.async {
                do {
                    try context.save()
                    print("✅ 迁移完成: 成功 \(successCount) 条, 失败 \(failCount) 条")
                    self.status = .completed(success: successCount, failed: failCount)
                } catch {
                    print("❌ 保存迁移数据失败: \(error)")
                    context.rollback()
                    self.status = .error("保存失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 重置状态
    func reset() {
        status = .idle
    }
    
    // MARK: - 图片处理方法
    
    /// 使用 CGImageSource 获取图片尺寸（不需要解码整张图片）
    private func getImageInfo(from data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }
    
    /// 生成缩略图（优先使用 CGImageSource，失败时 fallback 到 NSImage）
    private func createThumbnail(from data: Data, maxSize: CGFloat) -> Data? {
        // 方法1：尝试使用 CGImageSource（高效，不需要完整解码）
        if let thumbnail = createThumbnailWithCGImageSource(from: data, maxSize: maxSize) {
            return thumbnail
        }
        
        // 方法2：Fallback 到 NSImage（兼容更多格式）
        return createThumbnailWithNSImage(from: data, maxSize: maxSize)
    }
    
    /// 使用 CGImageSource 高效生成缩略图
    private func createThumbnailWithCGImageSource(from data: Data, maxSize: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        // 将 CGImage 转换为 JPEG Data
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return nil
        }
        
        return jpegData
    }
    
    /// 使用 NSImage 生成缩略图（兼容性更好，但需要完整解码）
    private func createThumbnailWithNSImage(from data: Data, maxSize: CGFloat) -> Data? {
        guard let image = NSImage(data: data) else {
            return nil
        }
        
        let originalSize = image.size
        guard originalSize.width > 0 && originalSize.height > 0 else {
            return nil
        }
        
        // 计算缩放尺寸
        var newSize = originalSize
        if originalSize.width > maxSize || originalSize.height > maxSize {
            let widthRatio = maxSize / originalSize.width
            let heightRatio = maxSize / originalSize.height
            let ratio = min(widthRatio, heightRatio)
            newSize = NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
        }
        
        // 创建缩略图
        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)
        thumbnail.unlockFocus()
        
        // 转换为 JPEG
        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return nil
        }
        
        return jpegData
    }
    
    /// 压缩图标为 32x32 像素
    /// - Parameter data: 原始图标数据
    /// - Returns: 压缩后的图标数据（32x32 像素，PNG 格式）
    static func compressIconTo32x32(from data: Data) -> Data? {
        guard let image = NSImage(data: data) else {
            return nil
        }
        
        let targetSize = NSSize(width: 32, height: 32)
        
        // 创建 32x32 的图标
        let icon = NSImage(size: targetSize)
        icon.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        icon.unlockFocus()
        
        // 转换为 PNG Data
        guard let tiffData = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return pngData
    }
}
