//
//  ClipboardItemRow.swift
//  CopyX
//
//  Created by 张佳航 on 2025/11/18.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - 单条记录行视图

struct ClipboardItemRow: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var item: ClipboardItem
    var isSelected: Bool
    var isCopied: Bool  // 是否刚被复制
    var onSelect: () -> Void
    var onDoubleClick: () -> Void
    var onCopy: () -> Void  // 复制回调
    var onCopyPlainText: () -> Void  // 以纯文本复制回调
    var onPaste: () -> Void  // 粘贴到活动应用回调
    var onPastePlainText: () -> Void  // 以纯文本粘贴到活动应用回调
    var onDelete: () -> Void  // 删除回调
    var onViewDetails: () -> Void // 查看详情回调

    // 缩略图和应用图标状态
    @State private var thumbnailImage: NSImage?
    @State private var appIconImage: NSImage?
    @State private var isImageLoaded = false
    @State private var isIconLoaded = false

    /// 底部横条模式：仅固定外框尺寸（`CarouselCardLayout`）并裁剪溢出；字号/间距与竖向列表一致
    var compactCarousel: Bool = false

    private enum CarouselCardLayout {
        static let width: CGFloat = 260
        static let height: CGFloat = 220
        /// 中间预览区固定高度（与顶栏、底栏占位相加为卡片高度），仅裁剪不缩小字体
        static let middleSlotHeight: CGFloat = 152
    }

    /// 列表预览：限制字符与行数，避免 Text 对数千字做完整折行测量
    private let listPreviewMaxCharacters = 1200
    private let previewTextMaxHeight: CGFloat = 160
    private let previewLineLimit = 10
    private let previewImageMaxHeight: CGFloat = 250
    /// 类型/颜色/链接检测仅看开头，避免对超长全文 trim
    private let metadataTextHeadLimit = 4096

    private var mainColumn: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                appIcon

                Text(contentTypeText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary)

                Spacer()

                Text(DateUtils.formatRelativeDate(item.createdAt))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 6)

            itemPreviewBlock

            if compactCarousel {
                Spacer(minLength: 0)
            }

            HStack {
                Text(contentDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    item.isFavorite.toggle()
                } label: {
                    Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(item.isFavorite ? .accentColor : .secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .padding(.top, 5)
        }
    }

    /// 中间预览（横滑模式仅加固定高度并裁剪，规格与竖向列表相同）
    private var itemPreviewBlock: some View {
        let block = VStack(alignment: .leading, spacing: 6) {
            if let fileNames = item.fileNames, !fileNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(fileNames.enumerated()), id: \.offset) { index, fileName in
                        HStack(spacing: 8) {
                            Image(systemName: FileUtils.fileIcon(for: fileName))
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                            Text(fileName)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let text = item.text, !text.isEmpty {
                Text(truncatedListPreview(text))
                    .font(.system(size: 13))
                    .foregroundColor(contentTextColor)
                    .lineLimit(previewLineLimit)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: previewTextMaxHeight)
            } else if let rtfData = item.rtfData,
                      let attributedString = createAttributedString(from: rtfData, maxLength: listPreviewMaxCharacters) {
                Text(attributedString)
                    .lineLimit(previewLineLimit)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: previewTextMaxHeight)
            }

            if item.imageWidth != nil {
                if let nsImage = thumbnailImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(maxHeight: previewImageMaxHeight)
                        .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.1))
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                        .task {
                            loadThumbnail()
                        }
                }
            }
        }
        .padding(.horizontal, isColorContent ? 12 : 0)
        .padding(.vertical, isColorContent ? 8 : 0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(contentBackgroundColor)
        )
        .padding(.horizontal, 14)

        return Group {
            if compactCarousel {
                block
                    .frame(height: CarouselCardLayout.middleSlotHeight, alignment: .top)
                    .clipped()
            } else {
                block
            }
        }
    }

    var body: some View {
        Group {
            if compactCarousel {
                mainColumn
                    .frame(width: CarouselCardLayout.width, height: CarouselCardLayout.height, alignment: .top)
                    .clipped()
            } else {
                mainColumn
                    .frame(maxWidth: .infinity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(PanelTheme.itemBackground)
                .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    Color.accentColor.opacity(isSelected ? 0.8 : 0),
                    lineWidth: isSelected ? 1.5 : 0
                )
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .overlay(
            ClickableView(
                onClick: {
                    onSelect()
                },
                onDoubleClick: {
                    onDoubleClick()
                }
            )
        )
        .contentShape(Rectangle())
        // 右键菜单
        .contextMenu {
            if item.supportsTextDetailView {
                Button {
                    onViewDetails()
                } label: {
                    Label(NSLocalizedString("view_details", comment: "查看详情"), systemImage: "text.magnifyingglass")
                }

                Divider()
            }

            Button {
                onPaste()
            } label: {
                Label(NSLocalizedString("paste_to_active_app", comment: "") + "  ⏎", systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("v", modifiers: .command)
            
            Button {
                onPastePlainText()
            } label: {
                Label("paste_plain", systemImage: "text.alignleft")
            }
            
            Divider()
            
            Button {
                onCopy()
            } label: {
                Label("copy", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)
            
            Button {
                onCopyPlainText()
            } label: {
                Label("copy_as_plain_text", systemImage: "doc.plaintext")
            }
            
            Divider()
            
            Button {
                item.isFavorite.toggle()
            } label: {
                Label(item.isFavorite ? NSLocalizedString("unfavorite", comment: "") : NSLocalizedString("favorite", comment: ""), systemImage: item.isFavorite ? "heart.slash" : "heart")
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("delete", systemImage: "trash")
            }
        }
        .onDrag {
            createDragItemProvider()
        }
        // 复制成功的 overlay 遮罩
        .overlay(
            Group {
                if isCopied {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.black.opacity(0.5))

                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                            Text("copied")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                }
            }
        )
        // 当 item 变化时重置图片状态（防止 LazyVStack 视图复用导致状态混乱）
        .onChange(of: item.persistentModelID) { _, _ in
            thumbnailImage = nil
            appIconImage = nil
            isImageLoaded = false
            isIconLoaded = false
        }
    }

    private var appIcon: some View {
        Group {
            // 如果是 iOS 设备，显示设备图标
            if let deviceType = item.sourceDeviceType {
                if deviceType == "iPhone" {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.15))
                        Image(systemName: "iphone")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.blue)
                            .padding(6)
                    }
                } else if deviceType == "iPad" {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.purple.opacity(0.15))
                        Image(systemName: "ipad")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.purple)
                            .padding(6)
                    }
                } else if let nsImage = appIconImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                } else if item.appBundleIdentifier != nil {
                    Color.clear
                        .task {
                            loadAppIcon()
                        }
                } else {
                    Image(systemName: "app")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.secondary)
                }
            } else if let nsImage = appIconImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else if item.appBundleIdentifier != nil {
                Color.clear
                    .task {
                        loadAppIcon()
                    }
            } else {
                Image(systemName: "app")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .cornerRadius(6)
    }
    
    // MARK: - 拖放支持
    
    /// 创建拖放数据提供者
    private func createDragItemProvider() -> NSItemProvider {
        // 优先处理文件
        if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
            let provider = NSItemProvider()
            for filePath in fileURLs {
                let url = URL(fileURLWithPath: filePath)
                if FileManager.default.fileExists(atPath: filePath) {
                    // 注册文件 URL
                    provider.registerFileRepresentation(
                        forTypeIdentifier: UTType.fileURL.identifier,
                        visibility: .all
                    ) { completion in
                        completion(url, false, nil)
                        return nil
                    }
                }
            }
            return provider
        }
        
        // 处理图片
        if let imageData = item.imageData,
           let nsImage = NSImage(data: imageData) {
            let provider = NSItemProvider(object: nsImage)
            return provider
        }
        
        // 处理文本
        if let text = item.text, !text.isEmpty {
            let provider = NSItemProvider(object: text as NSString)
            return provider
        }
        
        // 默认返回空的 provider
        return NSItemProvider()
    }
    
    // MARK: - 图片加载方法
    
    /// 异步加载缩略图（优先使用预存的缩略图，大幅减少内存占用）
    private func loadThumbnail() {
        guard !isImageLoaded else { return }
        isImageLoaded = true
        
        // 优先使用预存的缩略图数据（内存效率最高）
        if let thumbnailData = item.thumbnailData {
            DispatchQueue.global(qos: .userInitiated).async {
                if let thumbnail = NSImage(data: thumbnailData) {
                    DispatchQueue.main.async {
                        thumbnailImage = thumbnail
                    }
                }
            }
            return
        }
        
        // 兼容旧数据：如果没有预存缩略图，使用 ImageCache 生成
        guard let data = item.imageData else { return }
        
        let itemId = "img_\(item.createdAt.timeIntervalSince1970)"
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let thumbnail = ImageCache.shared.thumbnail(from: data, forKey: itemId, maxSize: 600) {
                DispatchQueue.main.async {
                    thumbnailImage = thumbnail
                }
            }
        }
    }
    
    /// 异步加载应用图标
    private func loadAppIcon() {
        guard !isIconLoaded else { return }
        isIconLoaded = true
        
        // 从 AppIconManager 获取图标
        if let bundleIdentifier = item.appBundleIdentifier {
            if let icon = AppIconManager.shared.getIcon(for: bundleIdentifier) {
                appIconImage = icon
            }
        }
    }
    
    /// 根据内容类型返回不同的描述（优先使用预存值）
    private var contentDescription: String {
        // 始终动态计算，避免 displayDescription（持久化字符串）导致语言切换不生效
        item.localizedDisplayDescription
    }

    // MARK: - 内容类型检测

    /// 取 `text` 前若干字符做 trim，供类型/颜色判断（避免超长字符串整段 trim）
    private var textHeadForMetadata: String {
        guard let t = item.text, !t.isEmpty else { return "" }
        return String(t.prefix(metadataTextHeadLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 列表预览截取：用 index 前进 `maxLen` 标量，避免先 `text.count` 再 `prefix`
    private func truncatedListPreview(_ text: String) -> String {
        guard let end = text.index(text.startIndex, offsetBy: listPreviewMaxCharacters, limitedBy: text.endIndex),
              end < text.endIndex else {
            return text
        }
        return String(text[..<end]) + "…"
    }

    /// 计算属性：返回内容类型的文本
    private var contentTypeText: String {
        if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
            if fileURLs.count == 1 {
                return NSLocalizedString("content_type_file_singular", comment: "")
            } else {
                return String(format: NSLocalizedString("content_type_files_count", comment: ""), fileURLs.count)
            }
        }

        if item.imageData != nil {
            return NSLocalizedString("content_type_image", comment: "")
        }

        let head = textHeadForMetadata
        guard !head.isEmpty else {
            return NSLocalizedString("content_type_text", comment: "")
        }

        if ColorUtils.isColorString(head) {
            return NSLocalizedString("content_type_color", comment: "")
        }

        if URLUtils.isURL(head) {
            return NSLocalizedString("content_type_link", comment: "")
        }

        return NSLocalizedString("content_type_text", comment: "")
    }

    /// 计算属性：根据内容类型返回内容区域背景色
    private var contentBackgroundColor: Color {
        let head = textHeadForMetadata
        guard !head.isEmpty else {
            return Color.clear
        }

        if let color = ColorUtils.parseColor(from: head) {
            return color
        }

        return Color.clear
    }

    /// 计算属性：判断是否是颜色内容
    private var isColorContent: Bool {
        let head = textHeadForMetadata
        guard !head.isEmpty else { return false }
        return ColorUtils.parseColor(from: head) != nil
    }

    /// 计算属性：根据背景颜色返回合适的文本颜色
    private var contentTextColor: Color {
        let head = textHeadForMetadata
        guard !head.isEmpty else {
            return .primary
        }

        if let bgColor = ColorUtils.parseColor(from: head) {
            // 如果是深色背景，使用白色文字；浅色背景使用黑色文字
            return ColorUtils.isDarkColor(bgColor) ? .white : .black
        }

        return .primary
    }
    
    // MARK: - 富文本处理
    
    /// 从 RTF 数据创建 AttributedString（带长度限制）
    private func createAttributedString(from rtfData: Data, maxLength: Int) -> AttributedString? {
        guard let nsAttributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) else {
            return nil
        }
        
        // 限制长度以避免性能问题
        let text = nsAttributedString.string
        if text.count > maxLength {
            let truncatedRange = NSRange(location: 0, length: min(maxLength, nsAttributedString.length))
            let truncatedNSString = nsAttributedString.attributedSubstring(from: truncatedRange).mutableCopy() as! NSMutableAttributedString
            truncatedNSString.append(NSAttributedString(string: "..."))
            
            do {
                return try AttributedString(truncatedNSString, including: \.appKit)
            } catch {
                return nil
            }
        }
        
        do {
            return try AttributedString(nsAttributedString, including: \.appKit)
        } catch {
            return nil
        }
    }
}

