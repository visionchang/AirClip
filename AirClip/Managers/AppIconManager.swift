//
//  AppIconManager.swift
//  CopyX
//
//  应用图标管理器：在启动时加载所有图标到内存，提供快速访问
//

import Foundation
import SwiftData
import AppKit

/// 应用图标管理器（单例）
/// 在应用启动时加载所有 AppIcon 到内存，提供快速查找
final class AppIconManager {
    static let shared = AppIconManager()
    
    /// 内存中的图标缓存：bundleIdentifier -> NSImage
    private var iconCache: [String: NSImage] = [:]
    
    /// 是否已加载完成
    private var isLoaded = false
    
    private init() {}
    
    /// 加载所有图标到内存（应在应用启动时调用）
    func loadAllIcons(modelContainer: ModelContainer) {
        guard !isLoaded else { return }
        
        let context = modelContainer.mainContext
        let fetchDescriptor = FetchDescriptor<AppIcon>()
        
        guard let allIcons = try? context.fetch(fetchDescriptor) else {
            print("⚠️ 加载应用图标失败")
            return
        }
        
        // 将所有图标加载到内存
        for appIcon in allIcons {
            if let image = NSImage(data: appIcon.iconData) {
                iconCache[appIcon.bundleIdentifier] = image
            }
        }
        
        isLoaded = true
        print("✅ 已加载 \(iconCache.count) 个应用图标到内存")
    }
    
    /// 根据 bundleIdentifier 获取图标
    /// - Parameter bundleIdentifier: 应用 Bundle ID
    /// - Returns: 图标 NSImage，如果不存在则返回 nil
    func getIcon(for bundleIdentifier: String) -> NSImage? {
        return iconCache[bundleIdentifier]
    }
    
    /// 添加或更新图标（用于新数据）
    /// - Parameters:
    ///   - bundleIdentifier: 应用 Bundle ID
    ///   - iconData: 图标数据
    func setIcon(bundleIdentifier: String, iconData: Data) {
        if let image = NSImage(data: iconData) {
            iconCache[bundleIdentifier] = image
        }
    }
    
    /// 清除所有缓存（用于测试或重置）
    func clearCache() {
        iconCache.removeAll()
        isLoaded = false
    }
    
    /// 获取已缓存的图标数量
    var cachedCount: Int {
        return iconCache.count
    }
}

