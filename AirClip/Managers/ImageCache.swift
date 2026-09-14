//
//  ImageCache.swift
//  CopyX
//
//  用于管理图片缓存，减少内存占用
//

import Foundation
import AppKit

/// 全局图片缓存管理器
final class ImageCache {
    static let shared = ImageCache()
    
    // 使用 NSCache 自动处理内存压力
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        // 设置缓存限制
        cache.countLimit = 50  // 最多缓存 50 张图片
        cache.totalCostLimit = 50 * 1024 * 1024  // 最大 50MB
        
        // NSCache 会自动在系统内存压力下清理缓存
        // macOS 没有 didReceiveMemoryWarningNotification，
        // 但 NSCache 内置了内存管理功能
    }
    
    /// 获取缓存的图片
    func image(forKey key: String) -> NSImage? {
        return cache.object(forKey: key as NSString)
    }
    
    /// 存储图片到缓存
    func setImage(_ image: NSImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * 4)  // 估算内存占用
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    /// 从数据创建缩略图并缓存
    func thumbnail(from data: Data, forKey key: String, maxSize: CGFloat = 600) -> NSImage? {
        let thumbnailKey = "\(key)_thumb_\(Int(maxSize))"
        
        // 先检查缓存
        if let cached = cache.object(forKey: thumbnailKey as NSString) {
            return cached
        }
        
        // 创建缩略图
        guard let image = NSImage(data: data) else { return nil }
        
        let originalSize = image.size
        var newSize = originalSize
        
        // 计算缩略图尺寸
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
        
        // 缓存缩略图
        let cost = Int(newSize.width * newSize.height * 4)
        cache.setObject(thumbnail, forKey: thumbnailKey as NSString, cost: cost)
        
        return thumbnail
    }
    
    /// 清除所有缓存
    @objc func clearCache() {
        cache.removeAllObjects()
        print("🧹 图片缓存已清除")
    }
    
    /// 移除指定 key 的缓存
    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}

