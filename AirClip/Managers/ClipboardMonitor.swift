import Foundation
import AppKit
import SwiftData
import ImageIO

/// 剪贴板数据变更通知
extension Notification.Name {
    static let clipboardDataDidChange = Notification.Name("clipboardDataDidChange")
    static let clipboardMonitoringPausedDidChange = Notification.Name("clipboardMonitoringPausedDidChange")
}

/// 负责轮询系统剪贴板并写入 SwiftData 的服务
final class ClipboardMonitor {
    private enum PauseStateUserInfoKey {
        static let paused = "paused"
    }

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private var shouldIgnoreNextChange = false
    private var pendingInternalCopyItemID: PersistentIdentifier?
    private var isMonitoringPaused: Bool = false

    private let modelContainer: ModelContainer
    
    // 应用图标缓存，避免重复生成相同应用的图标数据
    private var appIconCache: [String: Data] = [:]
    // 缓存最大数量，防止内存无限增长
    private let maxIconCacheCount = 50
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.lastChangeCount = pasteboard.changeCount
        startMonitoring()
    }
    
    deinit {
        timer?.invalidate()
    }

    /// 忽略下一次剪贴板变更（用于应用内复制操作）
    func ignoreNextChange() {
        shouldIgnoreNextChange = true
    }

    /// 标记一次“应用内复制”：下一次剪贴板变更到来时，将把对应记录的时间更新为最新
    /// - Note: 仅更新 `createdAt`，不会改变来源应用名称/图标等字段。
    func markInternalCopy(itemID: PersistentIdentifier) {
        pendingInternalCopyItemID = itemID
        shouldIgnoreNextChange = true
    }
    
    /// 检查应用是否在屏蔽列表中
    private func isAppBlocked(bundleId: String) -> Bool {
        // 如果从未设置过，使用默认值
        let blockedApps: [String]
        if UserDefaults.standard.object(forKey: PreferencesKeys.blockedApps) == nil {
            blockedApps = PreferencesDefaults.blockedApps
        } else {
            blockedApps = UserDefaults.standard.stringArray(forKey: PreferencesKeys.blockedApps) ?? []
        }
        return blockedApps.contains(bundleId)
    }
    
    /// 检测内容类型
    private func detectContentType(content: ExtractedContent) -> ContentType {
        // 文件类型
        if let fileURLs = content.fileURLs, !fileURLs.isEmpty {
            return .file
        }
        
        // 图片类型
        if content.imageData != nil {
            return .image
        }
        
        // 文本相关类型
        guard let text = content.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .text
        }
        
        // 颜色类型
        if ColorUtils.isColorString(text) {
            return .color
        }
        
        // 链接类型
        if URLUtils.isURL(text) {
            return .link
        }
        
        return .text
    }
    
    /// 检查内容类型是否应该被忽略
    private func shouldIgnoreContentType(_ contentType: ContentType) -> Bool {
        let ignoredTypes = UserDefaults.standard.stringArray(forKey: PreferencesKeys.ignoredContentTypes) ?? PreferencesDefaults.ignoredContentTypes
        return ignoredTypes.contains(contentType.rawValue)
    }
    
    /// 检查文本是否包含忽略的关键字
    private func containsIgnoredKeyword(_ text: String?) -> String? {
        guard let text = text, !text.isEmpty else { return nil }
        let ignoredKeywords = UserDefaults.standard.stringArray(forKey: PreferencesKeys.ignoredKeywords) ?? PreferencesDefaults.ignoredKeywords
        for keyword in ignoredKeywords {
            if text.localizedCaseInsensitiveContains(keyword) {
                return keyword
            }
        }
        return nil
    }

    /// 开始轮询剪贴板
    private func startMonitoring() {
        // 如果已经存在 timer，则不用重复启动
        if timer != nil { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// 暂停轮询剪贴板（保留当前状态），可以通过 `resumeMonitoring()` 恢复
    func pauseMonitoring() {
        guard !isMonitoringPaused else { return }
        timer?.invalidate()
        timer = nil
        isMonitoringPaused = true
        NotificationCenter.default.post(
            name: .clipboardMonitoringPausedDidChange,
            object: nil,
            userInfo: [PauseStateUserInfoKey.paused: true]
        )
        print("⏸️ 剪贴板监听已暂停")
    }

    /// 恢复轮询剪贴板（如果之前已暂停）
    func resumeMonitoring() {
        guard isMonitoringPaused else { return }
        startMonitoring()
        isMonitoringPaused = false
        NotificationCenter.default.post(
            name: .clipboardMonitoringPausedDidChange,
            object: nil,
            userInfo: [PauseStateUserInfoKey.paused: false]
        )
        print("▶️ 剪贴板监听已恢复")
    }

    /// 当前监听是否已暂停
    var isMonitoringPausedPublic: Bool { isMonitoringPaused }
    
    private func checkPasteboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // 应用内复制：将被复制的那条记录提到最新（不创建新记录，不改应用名/图标）
        if shouldIgnoreNextChange {
            shouldIgnoreNextChange = false

            if let itemID = pendingInternalCopyItemID {
                pendingInternalCopyItemID = nil

                let context = modelContainer.mainContext
                if let item = context.model(for: itemID) as? ClipboardItem {
                    item.createdAt = Date()
                    do {
                        try context.save()
                        print("🔄 应用内复制：已更新时间戳")
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
                        }
                    } catch {
                        print("❌ 应用内复制：更新时间戳失败: \(error)")
                        context.rollback()
                    }
                    return
                }

                // 如果目标记录不存在（被删除/迁移），回退到正常处理
                print("⚠️ 应用内复制：未找到目标记录，回退到正常处理")
            } else {
                // 没有明确的目标记录时，为避免生成“来源为 AirClip”的新条目，保持兼容旧行为
                print("🚫 忽略应用内复制操作（未提供目标记录 ID）")
                return
            }
        }

        handlePasteboardChange()
    }
    
    /// 处理剪贴板变化，写入新的记录
    private func handlePasteboardChange() {
        let context = modelContainer.mainContext

        let extractedContent = extractContent(from: pasteboard)
        guard extractedContent.text != nil || extractedContent.imageData != nil || (extractedContent.fileURLs != nil && !extractedContent.fileURLs!.isEmpty) else {
            return
        }

        // 如果是 Universal Clipboard，使用特殊的 bundleId
        let (appName, bundleId, iconData): (String?, String?, Data?)
        if extractedContent.isFromUniversalClipboard {
            // 为 Universal Clipboard 分配特殊的 bundleId
            (appName, bundleId, iconData) = ("Universal Clipboard", "com.apple.UniversalClipboard", nil)
        } else {
            (appName, bundleId, iconData) = currentFrontmostAppInfo()
        }

        // 检查当前应用是否在屏蔽列表中
        if let bundleId = bundleId, isAppBlocked(bundleId: bundleId) {
            print("🚫 应用 \(appName ?? bundleId) 在屏蔽列表中，跳过记录")
            return
        }
        
        // 检查内容类型是否在忽略列表中
        let contentType = detectContentType(content: extractedContent)
        if shouldIgnoreContentType(contentType) {
            print("🚫 内容类型 \(contentType.displayName) 在忽略列表中，跳过记录")
            return
        }
        
        // 检查文本是否包含忽略的关键字
        if let matchedKeyword = containsIgnoredKeyword(extractedContent.text) {
            print("🚫 内容包含忽略的关键字「\(matchedKeyword)」，跳过记录")
            return
        }

        // 检查是否存在重复项（内容和来源应用完全一致）
        if let existingItem = findDuplicateItem(content: extractedContent, bundleId: bundleId, in: context) {
            // 更新时间为最新，不创建新记录
            existingItem.createdAt = Date()
            do {
                try context.save()
                print("🔄 检测到重复内容，已更新时间戳")
                // 通知 UI 刷新数据
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
                }
            } catch {
                print("❌ 更新重复项时间戳失败: \(error)")
                context.rollback()
            }
            return
        }

        let size = Self.estimateContentSize(text: extractedContent.text, rtfData: extractedContent.rtfData, imageData: extractedContent.imageData, fileURLs: extractedContent.fileURLs)
        
        // 检查最大缓存文件大小限制
        let maxFileSizeBytes: Int
        if UserDefaults.standard.object(forKey: PreferencesKeys.maxFileSizeBytes) == nil {
            // 如果从未设置过，使用默认值
            maxFileSizeBytes = PreferencesDefaults.maxFileSizeBytes
        } else {
            maxFileSizeBytes = UserDefaults.standard.integer(forKey: PreferencesKeys.maxFileSizeBytes)
        }
        
        // -1 表示无限制，> 0 表示有限制
        if maxFileSizeBytes > 0 {
            // 检查文件大小（仅限制文件类型，不限制图片）
            if let fileURLs = extractedContent.fileURLs, !fileURLs.isEmpty {
                let fileManager = FileManager.default
                for filePath in fileURLs {
                    if let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                       let fileSize = attributes[.size] as? Int,
                       fileSize > maxFileSizeBytes {
                        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                        let fileSizeMB = Double(fileSize) / 1024 / 1024
                        let maxSizeMB = Double(maxFileSizeBytes) / 1024 / 1024
                        print("🚫 文件「\(fileName)」大小 \(String(format: "%.1f", fileSizeMB)) MB 超过最大缓存文件大小限制 \(String(format: "%.1f", maxSizeMB)) MB，跳过记录")
                        return
                    }
                }
            }
        }

        // 检查最大缓存字符数限制（仅限制文本）
        let maxTextCharacterCount: Int
        if UserDefaults.standard.object(forKey: PreferencesKeys.maxTextCharacterCount) == nil {
            maxTextCharacterCount = PreferencesDefaults.maxTextCharacterCount
        } else {
            maxTextCharacterCount = UserDefaults.standard.integer(forKey: PreferencesKeys.maxTextCharacterCount)
        }

        if maxTextCharacterCount > 0,
           let text = extractedContent.text,
           text.count > maxTextCharacterCount {
            print("🚫 文本字符数 \(text.count) 超过最大缓存字符数限制 \(maxTextCharacterCount)，跳过记录")
            return
        }
        
        // 处理应用图标：如果有图标和 bundleId，压缩并存储到 AppIcon 模型
        if let bundleId = bundleId, let iconData = iconData {
            // 压缩图标为 32x32
            if let compressedIconData = DataMigrationManager.compressIconTo32x32(from: iconData) {
                // 检查是否已存在该图标
                let iconFetchDescriptor = FetchDescriptor<AppIcon>(
                    predicate: #Predicate<AppIcon> { icon in
                        icon.bundleIdentifier == bundleId
                    }
                )
                
                if let existingIcon = try? context.fetch(iconFetchDescriptor).first {
                    // 更新现有图标
                    existingIcon.iconData = compressedIconData
                } else {
                    // 创建新图标
                    let appIcon = AppIcon(bundleIdentifier: bundleId, iconData: compressedIconData)
                    context.insert(appIcon)
                }
                
                // 更新内存缓存
                AppIconManager.shared.setIcon(bundleIdentifier: bundleId, iconData: compressedIconData)
            }
        }
        
        // 先删除旧内容腾出空间，再存入新内容
        makeRoomForNewItem(estimatedSize: size, in: context)

        // 获取设备信息（用于同步）
        let deviceID = UserDefaults.standard.string(forKey: PreferencesKeys.deviceID) ?? UUID().uuidString
        let deviceName = Host.current().localizedName ?? "Mac"

        // 生成内容哈希（用于跨设备去重）
        let contentHash = generateContentHash(
            text: extractedContent.text,
            imageData: extractedContent.imageData,
            fileURLs: extractedContent.fileURLs
        )

        // 判断同步状态：文件类型不同步
        let syncStatus: SyncStatus = (extractedContent.fileURLs != nil && !(extractedContent.fileURLs?.isEmpty ?? true)) ? .localOnly : .pending

        let textCharCount = extractedContent.text.map { $0.count } ?? 0

        // 创建 ClipboardItem（不包含 appIconData，使用 AppIcon 模型）
        let item = ClipboardItem(
            text: extractedContent.text,
            rtfData: extractedContent.rtfData,
            imageData: extractedContent.imageData,
            thumbnailData: extractedContent.thumbnailData,
            imageWidth: extractedContent.imageWidth,
            imageHeight: extractedContent.imageHeight,
            fileURLs: extractedContent.fileURLs,
            fileNames: extractedContent.fileNames,
            appName: appName ?? "未知应用",
            appBundleIdentifier: bundleId,
            appIconData: nil, // 不存储图标数据，使用 AppIcon 模型
            createdAt: Date(),
            contentSize: size,
            textCharacterCount: textCharCount,
            isFavorite: false,
            displayDescription: nil,
            syncID: UUID().uuidString,
            modifiedAt: Date(),
            sourceDeviceID: deviceID,
            sourceDeviceName: deviceName,
            syncStatus: syncStatus,
            cloudRecordID: nil,
            contentHash: contentHash
        )

        context.insert(item)

        // 保存更改，带错误处理
        do {
            try context.save()
            // 通知 UI 刷新数据
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .clipboardDataDidChange, object: nil)
            }
        } catch {
            print("❌ 保存剪贴板记录失败: \(error)")
            print("错误详情: \(error.localizedDescription)")
            context.rollback()
        }
    }
    
    /// 提取内容的返回结构
    struct ExtractedContent {
        var text: String?
        var rtfData: Data?
        var imageData: Data?
        var thumbnailData: Data?
        var imageWidth: Int?
        var imageHeight: Int?
        var fileURLs: [String]?
        var fileNames: [String]?
        var isFromUniversalClipboard: Bool = false
    }
    
    private func extractContent(from pasteboard: NSPasteboard) -> ExtractedContent {
        var result = ExtractedContent()

        // 检测是否来自 Universal Clipboard（通用剪贴板）
        if pasteboard.types?.contains(NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")) == true {
            result.isFromUniversalClipboard = true
            print("📱 检测到来自 Universal Clipboard 的内容（iPhone/iPad）")
        }

        // 首先使用 readObjects 方法检测文件（最可靠的方法）
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            var validURLs: [String] = []
            var validNames: [String] = []
            for url in urls {
                // 确保是文件URL
                if url.isFileURL {
                    let filePath = url.path
                    if FileManager.default.fileExists(atPath: filePath) {
                        validURLs.append(filePath)
                        validNames.append(url.lastPathComponent)
                    }
                }
            }
            if !validURLs.isEmpty {
                result.fileURLs = validURLs
                result.fileNames = validNames
            }
        }
        
        // 如果 readObjects 没有找到，尝试从 pasteboardItems 中获取
        if (result.fileURLs == nil || result.fileURLs!.isEmpty), let items = pasteboard.pasteboardItems {
            for item in items {
                // 检查文件URL类型
                let fileURLType = NSPasteboard.PasteboardType.fileURL
                if let fileURLString = item.string(forType: fileURLType) {
                    // 尝试解析为URL
                    var url: URL?
                    if fileURLString.hasPrefix("file://") {
                        url = URL(string: fileURLString)
                    } else {
                        // 如果不是完整的URL，尝试作为文件路径
                        url = URL(fileURLWithPath: fileURLString)
                    }
                    
                    if let url = url {
                        let filePath = url.path
                        if FileManager.default.fileExists(atPath: filePath) {
                            if result.fileURLs == nil {
                                result.fileURLs = []
                                result.fileNames = []
                            }
                            if !result.fileURLs!.contains(filePath) {
                                result.fileURLs!.append(filePath)
                                result.fileNames!.append(url.lastPathComponent)
                            }
                        }
                    }
                }
            }
            
            // 如果没有文件，尝试获取文本（优先获取 RTF 富文本）
            if result.fileURLs == nil || result.fileURLs!.isEmpty {
                for item in items {
                    // 尝试获取 RTF 富文本数据
                    if let rtfData = item.data(forType: .rtf) {
                        result.rtfData = rtfData
                        // 从 RTF 提取纯文本用于搜索和去重
                        if let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
                            result.text = attributedString.string
                        }
                        break
                    }
                    // 如果没有 RTF，获取纯文本
                    if let string = item.string(forType: .string), !string.isEmpty {
                        result.text = string
                        break
                    }
                }
            }
            
            // 尝试获取图片（如果还没有文件）
            if result.imageData == nil && (result.fileURLs == nil || result.fileURLs!.isEmpty) {
                for item in items {
                    // 尝试多种图片格式：tiff、png、jpeg
                    let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png, NSPasteboard.PasteboardType("public.jpeg")]
                    var imageData: Data?

                    for imageType in imageTypes {
                        if let data = item.data(forType: imageType) {
                            imageData = data
                            break
                        }
                    }

                    if let imageData = imageData {
                        // 使用 CGImageSource 获取图片尺寸（不需要完整解码）
                        if let imageInfo = Self.getImageInfo(from: imageData) {
                            result.imageWidth = imageInfo.width
                            result.imageHeight = imageInfo.height
                        }

                        // 使用 CGImageSource 生成缩略图（高效，不需要完整解码原图）
                        result.thumbnailData = Self.createThumbnail(from: imageData, maxSize: 600)

                        // 直接存储原始图片数据，不压缩、不改变格式
                        result.imageData = imageData
                        break
                    }
                }
            }
        }
        
        return result
    }
    
    // MARK: - 高效图片处理（使用 ImageIO，避免完整解码）
    
    /// 使用 CGImageSource 获取图片尺寸（不需要解码整张图片）
    private static func getImageInfo(from data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }
    
    /// 生成缩略图（优先使用 CGImageSource，失败时 fallback 到 NSImage）
    private static func createThumbnail(from data: Data, maxSize: CGFloat) -> Data? {
        // 方法1：尝试使用 CGImageSource（高效，不需要完整解码）
        if let thumbnail = createThumbnailWithCGImageSource(from: data, maxSize: maxSize) {
            return thumbnail
        }
        
        // 方法2：Fallback 到 NSImage（兼容更多格式）
        return createThumbnailWithNSImage(from: data, maxSize: maxSize)
    }
    
    /// 使用 CGImageSource 高效生成缩略图
    private static func createThumbnailWithCGImageSource(from data: Data, maxSize: CGFloat) -> Data? {
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
    private static func createThumbnailWithNSImage(from data: Data, maxSize: CGFloat) -> Data? {
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
    
    private func currentFrontmostAppInfo() -> (String?, String?, Data?) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil, nil)
        }
        let name = app.localizedName
        let bundleId = app.bundleIdentifier
        var iconData: Data?
        
        // 使用缓存避免重复生成图标数据
        if let bundleId = bundleId {
            if let cachedIcon = appIconCache[bundleId] {
                iconData = cachedIcon
            } else if let icon = app.icon {
                // 使用小尺寸图标，减少内存占用（32x32 足够显示）
                if let smallIconData = icon.smallIconData(size: 32) {
                    iconData = smallIconData
                    
                    // 缓存图标数据
                    appIconCache[bundleId] = smallIconData
                    
                    // 如果缓存过大，移除最早的条目
                    if appIconCache.count > maxIconCacheCount {
                        if let firstKey = appIconCache.keys.first {
                            appIconCache.removeValue(forKey: firstKey)
                        }
                    }
                }
            }
        } else if let icon = app.icon {
            iconData = icon.smallIconData(size: 32)
        }
        
        return (name, bundleId, iconData)
    }
    
    private static func estimateContentSize(text: String?, rtfData: Data?, imageData: Data?, fileURLs: [String]?) -> Int {
        var size = 0
        if let rtfData {
            // 如果有 RTF 数据，优先计算 RTF 大小
            size += rtfData.count
        } else if let text {
            size += text.lengthOfBytes(using: .utf8)
        }
        if let imageData {
            size += imageData.count
        }
        if let fileURLs {
            let fileManager = FileManager.default
            for filePath in fileURLs {
                if let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                   let fileSize = attributes[.size] as? Int {
                    size += fileSize
                }
            }
        }
        return size
    }

    /// 查找重复的剪贴板项目（内容和来源应用完全一致）
    private func findDuplicateItem(content: ExtractedContent, bundleId: String?, in context: ModelContext) -> ClipboardItem? {
        // 文本内容去重
        if let text = content.text {
            let fetchDescriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate<ClipboardItem> { item in
                    item.text == text && item.appBundleIdentifier == bundleId
                }
            )
            if let existingItem = try? context.fetch(fetchDescriptor).first {
                return existingItem
            }
        }

        // 图片内容去重：先通过尺寸和 bundleId 筛选，再比较数据
        if let imageData = content.imageData,
           let imageWidth = content.imageWidth,
           let imageHeight = content.imageHeight {
            let fetchDescriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate<ClipboardItem> { item in
                    item.imageWidth == imageWidth &&
                    item.imageHeight == imageHeight &&
                    item.appBundleIdentifier == bundleId
                }
            )
            if let candidates = try? context.fetch(fetchDescriptor) {
                for candidate in candidates {
                    if let existingData = candidate.imageData, existingData == imageData {
                        return candidate
                    }
                }
            }
        }

        // 文件去重：比较文件路径列表和 bundleId
        if let fileURLs = content.fileURLs, !fileURLs.isEmpty {
            // 先获取所有有文件的记录，再在内存中比较
            let fetchDescriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate<ClipboardItem> { item in
                    item.fileURLs != nil && item.appBundleIdentifier == bundleId
                }
            )
            if let candidates = try? context.fetch(fetchDescriptor) {
                for candidate in candidates {
                    if let existingURLs = candidate.fileURLs,
                       existingURLs.count == fileURLs.count,
                       Set(existingURLs) == Set(fileURLs) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    /// 在插入新内容之前，先删除旧内容腾出空间
    private func makeRoomForNewItem(estimatedSize: Int, in context: ModelContext) {
        // 读取设置值，如果未设置则使用默认值
        let maxCountRaw = UserDefaults.standard.object(forKey: PreferencesKeys.maxItemCount)
        let maxCount: Int
        if maxCountRaw == nil {
            // 从未设置过，使用默认值
            maxCount = PreferencesDefaults.maxItemCount
        } else {
            let rawValue = UserDefaults.standard.integer(forKey: PreferencesKeys.maxItemCount)
            // -1 表示无限制，0 或负数（异常值）使用默认值
            if rawValue == -1 {
                maxCount = -1
            } else if rawValue <= 0 {
                maxCount = PreferencesDefaults.maxItemCount
            } else {
                maxCount = rawValue
            }
        }
        
        let maxBytesRaw = UserDefaults.standard.object(forKey: PreferencesKeys.maxTotalBytes)
        let maxBytes: Int
        if maxBytesRaw == nil {
            maxBytes = PreferencesDefaults.maxTotalBytes
        } else {
            let rawValue = UserDefaults.standard.integer(forKey: PreferencesKeys.maxTotalBytes)
            if rawValue == -1 {
                maxBytes = -1
            } else if rawValue <= 0 {
                maxBytes = PreferencesDefaults.maxTotalBytes
            } else {
                maxBytes = rawValue
            }
        }
        
        let retentionRaw = UserDefaults.standard.object(forKey: PreferencesKeys.retentionSliderValue)
        let retentionSliderValue: Double
        if retentionRaw == nil {
            retentionSliderValue = PreferencesDefaults.retentionSliderValue
        } else {
            retentionSliderValue = UserDefaults.standard.double(forKey: PreferencesKeys.retentionSliderValue)
        }
        
        // 按时间升序排序，最旧的在前面，方便从头删除
        // 只获取未收藏的项目，收藏的项目不会被自动删除
        let fetchDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { item in
                item.isFavorite == false
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        guard let nonFavoriteItems = try? context.fetch(fetchDescriptor) else {
            print("⚠️ 获取剪贴板记录失败，跳过限制检查")
            return
        }

        // 获取总数（包括收藏的）用于计数限制
        let totalCountDescriptor = FetchDescriptor<ClipboardItem>()
        let totalCount = (try? context.fetchCount(totalCountDescriptor)) ?? 0

        var itemsToDelete: [ClipboardItem] = []
        
        // 时间限制：删除过期的未收藏项目（-1.0 表示永久保留，>= 100 也表示永久）
        if retentionSliderValue > 0 && retentionSliderValue < 100 {
            let retentionValue = mapSliderToRetention(retentionSliderValue)
            if let retentionSeconds = retentionValue.seconds {
                let expirationDate = Date().addingTimeInterval(-retentionSeconds)
                for item in nonFavoriteItems {
                    if item.createdAt < expirationDate {
                        itemsToDelete.append(item)
                    }
                }
            }
        }

        // 条数限制：如果当前数量已达到限制，删除最旧的未收藏项目腾出1个位置
        // maxCount == -1 表示无限制
        if maxCount != -1 && maxCount > 0 && totalCount >= maxCount {
            let deleteCount = totalCount - maxCount + 1
            for i in 0..<min(deleteCount, nonFavoriteItems.count) {
                if !itemsToDelete.contains(where: { $0.id == nonFavoriteItems[i].id }) {
                    itemsToDelete.append(nonFavoriteItems[i])
                }
            }
        }

        // 存储限制：计算当前总大小，如果加上新项目会超过限制，从最旧的未收藏项目开始删除
        // maxBytes == -1 表示无限制
        if maxBytes != -1 && maxBytes > 0 {
            // 计算所有项目的总大小
            let allItemsDescriptor = FetchDescriptor<ClipboardItem>()
            let allItems = (try? context.fetch(allItemsDescriptor)) ?? []
            var currentBytes = allItems.reduce(0) { $0 + $1.contentSize }

            // 减去已标记删除的项目大小
            for item in itemsToDelete {
                currentBytes -= item.contentSize
            }

            // 如果加上新项目会超过限制，继续删除旧的未收藏内容
            for item in nonFavoriteItems {
                if currentBytes + estimatedSize <= maxBytes { break }
                if itemsToDelete.contains(where: { $0.id == item.id }) { continue }
                currentBytes -= item.contentSize
                itemsToDelete.append(item)
            }
        }

        // 删除旧内容（只删除未收藏的）
        if !itemsToDelete.isEmpty {
            for item in itemsToDelete {
                context.delete(item)
            }
            print("🗑️ 为新内容腾出空间，删除了 \(itemsToDelete.count) 条未收藏的旧记录")
        }
    }
    
    /// 将 sliderValue (1~100 或 -1 表示永久，兼容旧数据 0~1) 转换为 RetentionValue
    private func mapSliderToRetention(_ value: Double) -> RetentionValue {
        // 兼容旧数据（0-1 范围）
        if value > 0 && value < 1.0 {
            // 旧数据范围 0.05-1.0
            if value >= 0.95 { return .init(unit: .forever) }
            if value >= 0.83 { return .init(unit: .year) }
            if value >= 0.5 {
                let month = max(1, Int(round((value - 0.5) / 0.03)))
                return .init(unit: .month(min(month, 11)))
            }
            if value >= 0.3 {
                let week = max(1, Int(round((value - 0.3) / 0.05)))
                return .init(unit: .week(min(week, 4)))
            }
            let day = max(1, Int(round(max(value, 0.05) / 0.05)))
            return .init(unit: .day(min(day, 6)))
        }
        
        // 新数据范围 1-100
        if value < 0 || value >= 100 {
            return .init(unit: .forever)
        }
        
        // 使用 Double 值进行精确判断
        let doubleValue = value
        
        if doubleValue >= 1 && doubleValue <= 30 {
            // 1d ~ 7d
            // 1 对应 1 天，30 对应 7 天
            let day = Int(round(((doubleValue - 1.0) * 6.0 / 29.0) + 1.0))
            return .init(unit: .day(min(max(day, 1), 7)))
            
        } else if doubleValue >= 30 && doubleValue <= 60 {
            // 1w ~ 4w
            // 30 对应 1 周，60 对应 4 周
            let week = Int(round(((doubleValue - 30.0) * 3.0 / 30.0) + 1.0))
            return .init(unit: .week(min(max(week, 1), 4)))
            
        } else if doubleValue >= 60 && doubleValue <= 90 {
            // 1m ~ 12m
            // 60 对应 1 个月，90 对应 12 个月
            let month = Int(round(((doubleValue - 60.0) * 11.0 / 30.0) + 1.0))
            return .init(unit: .month(min(max(month, 1), 12)))
            
        } else if doubleValue >= 90 && doubleValue < 100 {
            // 1 年
            return .init(unit: .year)
            
        } else if doubleValue >= 100 {
            // 永久
            return .init(unit: .forever)

        } else {
            return .init(unit: .forever)
        }
    }

    // MARK: - 同步相关

    /// 生成内容哈希（用于跨设备去重）
    private func generateContentHash(text: String?, imageData: Data?, fileURLs: [String]?) -> String {
        var hashInput = ""

        if let text = text {
            hashInput += text
        }

        if let imageData = imageData {
            // 只取前 1KB 数据用于哈希，避免大图片计算太慢
            let sampleData = imageData.prefix(1024)
            hashInput += sampleData.base64EncodedString()
        }

        if let fileURLs = fileURLs {
            hashInput += fileURLs.joined(separator: ",")
        }

        // 使用简单的哈希算法
        var hash: UInt64 = 5381
        for byte in hashInput.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }

        return String(hash, radix: 16)
    }
}

// MARK: - NSImage 图片处理扩展

extension NSImage {
    var pngData: Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return data
    }
    
    /// 获取压缩后的 JPEG 数据（用于存储大图片）
    /// - Parameters:
    ///   - maxDimension: 最大边长（像素）
    ///   - quality: JPEG 质量 (0.0-1.0)
    /// - Returns: 压缩后的图片数据
    func compressedJPEGData(maxDimension: CGFloat = 1200, quality: CGFloat = 0.7) -> Data? {
        let originalSize = self.size
        var newSize = originalSize
        
        // 计算缩放后的尺寸
        if originalSize.width > maxDimension || originalSize.height > maxDimension {
            let widthRatio = maxDimension / originalSize.width
            let heightRatio = maxDimension / originalSize.height
            let ratio = min(widthRatio, heightRatio)
            newSize = NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
        }
        
        // 创建缩放后的图片
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: originalSize),
                  operation: .copy,
                  fraction: 1.0)
        resizedImage.unlockFocus()
        
        // 转换为 JPEG 数据
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            return self.pngData
        }
        
        return jpegData
    }
    
    /// 获取小尺寸应用图标数据
    /// - Parameter size: 目标尺寸
    /// - Returns: 压缩后的 PNG 数据
    func smallIconData(size: CGFloat = 32) -> Data? {
        let newSize = NSSize(width: size, height: size)
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        resizedImage.unlockFocus()
        
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return pngData
    }
}


