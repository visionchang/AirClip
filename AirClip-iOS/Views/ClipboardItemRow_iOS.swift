//
//  ClipboardItemRow_iOS.swift
//  AirClip-iOS
//
//  Created on 2025/12/18.
//

import SwiftUI
import SwiftData

struct ClipboardItemRow_iOS: View {
    let item: ClipboardItem
    let isCopied: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    @State private var thumbnailImage: UIImage?
    @Environment(\.modelContext) private var modelContext
    @State private var cachedAppIcon: UIImage?

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // 顶部：应用图标 + 类型 + 时间
                HStack(alignment: .center, spacing: 8) {
                    appIcon

                    Text(contentTypeText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)

                    Spacer()

                    // 复制成功提示
                    if isCopied {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                            Text("copied")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.green)
                        .transition(.opacity)
                    } else {
                        Text(formatRelativeDate(item.createdAt))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // 内容区域
                VStack(alignment: .leading, spacing: 6) {
                    // 显示文本内容
                    if let text = item.text, !text.isEmpty {
                        let displayText = text.count > 500 ? String(text.prefix(500)) + "..." : text
                        Text(displayText)
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(6)
                    }

                    // 显示图片
                    if item.imageWidth != nil {
                        if let image = thumbnailImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .frame(maxHeight: 200)
                                .cornerRadius(8)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
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
                .padding(.horizontal, 14)

                // 底部：描述 + 收藏按钮
                HStack {
                    Text(contentDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    // 来源设备
                    if let deviceName = item.sourceDeviceName {
                        HStack(spacing: 4) {
                            Image(systemName: deviceIcon)
                                .font(.system(size: 10))
                            Text(deviceName)
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary)
                    }

                    // 收藏按钮
                    Button {
                        onToggleFavorite()
                    } label: {
                        Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(item.isFavorite ? .red : .secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .padding(.top, 8)
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTap()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.accentColor, Color.secondary)
                    Text("copy")
                        .foregroundColor(.primary)
                }
            }

            Button {
                onToggleFavorite()
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
    }

    // MARK: - 应用图标

    @ViewBuilder
    private var appIcon: some View {
        // 如果是其他 iOS 设备（iPhone/iPad），显示设备图标
        if let deviceType = item.sourceDeviceType {
            if deviceType == "iPhone" {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.15))
                    Image(systemName: "iphone")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                .frame(width: 24, height: 24)
            } else if deviceType == "iPad" {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.purple.opacity(0.15))
                    Image(systemName: "ipad")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                }
                .frame(width: 24, height: 24)
            } else if let iconData = item.appIconData,
                      let uiImage = UIImage(data: iconData) {
                // Mac 设备或其他设备，显示应用图标
                Image(uiImage: uiImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .cornerRadius(6)
            } else if let cached = cachedAppIcon {
                Image(uiImage: cached)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .cornerRadius(6)
            } else {
                // 默认图标
                Image(systemName: defaultAppIcon)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .task(id: item.persistentModelID) {
                        // 异步尝试从 AppIcon 模型加载图标数据（如果存在）
                        if item.appIconData == nil, let bundleId = item.appBundleIdentifier {
                            let descriptor = FetchDescriptor<AppIcon>(
                                predicate: #Predicate<AppIcon> { icon in
                                    icon.bundleIdentifier == bundleId
                                }
                            )
                            if let found = try? modelContext.fetch(descriptor).first {
                                if let img = UIImage(data: found.iconData) {
                                    await MainActor.run {
                                        cachedAppIcon = img
                                    }
                                }
                            }
                        }
                    }
            }
        } else if let iconData = item.appIconData,
                  let uiImage = UIImage(data: iconData) {
            // 没有设备类型信息，使用应用图标
            Image(uiImage: uiImage)
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(6)
        } else if let cached = cachedAppIcon {
            Image(uiImage: cached)
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(6)
        } else {
            // 默认图标
            Image(systemName: defaultAppIcon)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .task(id: item.persistentModelID) {
                    // 异步尝试从 AppIcon 模型加载图标数据（如果存在）
                    if item.appIconData == nil, let bundleId = item.appBundleIdentifier {
                        let descriptor = FetchDescriptor<AppIcon>(
                            predicate: #Predicate<AppIcon> { icon in
                                icon.bundleIdentifier == bundleId
                            }
                        )
                        if let found = try? modelContext.fetch(descriptor).first {
                            if let img = UIImage(data: found.iconData) {
                                await MainActor.run {
                                    cachedAppIcon = img
                                }
                            }
                        }
                    }
                }
        }
    }

    // MARK: - 计算属性

    private var contentTypeText: String {
        if item.imageWidth != nil {
            return NSLocalizedString("content_type_image", comment: "")
        } else if item.fileURLs != nil && !(item.fileURLs?.isEmpty ?? true) {
            return NSLocalizedString("content_type_file_singular", comment: "")
        } else if item.text != nil && !item.text!.isEmpty {
            return NSLocalizedString("content_type_text", comment: "")
        } else {
            return item.appName
        }
    }

    private var contentDescription: String {
        item.localizedDisplayDescription
    }

    private var defaultAppIcon: String {
        if item.imageWidth != nil {
            return "photo"
        } else if item.fileURLs != nil && !(item.fileURLs?.isEmpty ?? true) {
            return "doc"
        } else {
            return "doc.text"
        }
    }

    private var deviceIcon: String {
        let name = item.sourceDeviceName?.lowercased() ?? ""
        if name.contains("mac") || name.contains("macbook") || name.contains("imac") {
            return "desktopcomputer"
        } else if name.contains("ipad") {
            return "ipad"
        } else {
            return "iphone"
        }
    }

    // MARK: - 辅助方法

    private func loadThumbnail() {
        if let thumbnailData = item.thumbnailData,
           let image = UIImage(data: thumbnailData) {
            thumbnailImage = image
        } else if let imageData = item.imageData,
                  let image = UIImage(data: imageData) {
            thumbnailImage = image
        }
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return NSLocalizedString("just_now", comment: "")
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return String(format: NSLocalizedString("minutes_ago", comment: ""), minutes)
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return String(format: NSLocalizedString("hours_ago", comment: ""), hours)
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return String(format: NSLocalizedString("days_ago", comment: ""), days)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd"
            return formatter.string(from: date)
        }
    }

    private func formatSize(bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ClipboardItemRow_iOS(
            item: ClipboardItem(
                text: "这是一段测试文本，用来展示剪贴板项目的显示效果。这是一段较长的文本，可能会被截断显示。",
                appName: "Safari",
                createdAt: Date(),
                contentSize: 100,
                displayDescription: "50 字符",
                sourceDeviceName: "MacBook Pro"
            ),
            isCopied: false,
            onTap: {},
            onToggleFavorite: {},
            onDelete: {}
        )

        ClipboardItemRow_iOS(
            item: ClipboardItem(
                text: "已复制的项目",
                appName: "Notes",
                createdAt: Date().addingTimeInterval(-3600),
                contentSize: 20,
                isFavorite: true,
                sourceDeviceName: "iPhone"
            ),
            isCopied: true,
            onTap: {},
            onToggleFavorite: {},
            onDelete: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
