import Foundation
import SwiftUI

enum PreferencesKeys {
    /// 是否开机启动
    static let launchAtLogin = "copyx.launchAtLogin"

    /// 最大缓存条数
    static let maxItemCount = "copyx.maxItemCount"

    /// 最大缓存空间（字节）
    static let maxTotalBytes = "copyx.maxTotalBytes"
    
    /// 最大缓存文件（字节）
    static let maxFileSizeBytes = "copyx.maxFileSizeBytes"

    /// 最大缓存字符数（文本超过此长度则不进入缓存，-1 表示无限制）
    static let maxTextCharacterCount = "copyx.maxTextCharacterCount"

    /// 唤出主面板的快捷键表示（例如 \"⌘⇧V\"）
    static let hotkeyDisplay = "copyx.hotkey.display"
    
    /// 唤出主面板的快捷键 keyCode（Carbon kVK_ 值）
    static let hotkeyKeyCode = "copyx.hotkey.keyCode"
    
    /// 唤出主面板的快捷键修饰键（Carbon modifier flags）
    static let hotkeyModifiers = "copyx.hotkey.modifiers"

    /// 复制成功后自动关闭主面板
    static let autoCloseAfterCopy = "copyx.autoCloseAfterCopy"
    
    /// 鼠标双击操作（0: 复制并粘贴, 1: 仅复制）
    static let doubleClickAction = "copyx.doubleClickAction"
    
    /// 始终以纯文本粘贴（忽略富文本格式）
    static let alwaysPastePlainText = "copyx.alwaysPastePlainText"
    
    /// 缓存时间限制（滑块值 1~100，-1 表示永久，兼容旧数据 0~1）
    static let retentionSliderValue = "copyx.retentionSliderValue"
    
    /// 屏蔽的应用列表（存储 bundle identifier 数组）
    static let blockedApps = "copyx.blockedApps"
    
    /// 忽略的内容类型（存储类型字符串数组：file, image, link, text, color）
    static let ignoredContentTypes = "copyx.ignoredContentTypes"
    
    /// 忽略的关键字列表（存储关键字字符串数组）
    static let ignoredKeywords = "copyx.ignoredKeywords"

    /// 主面板从屏幕哪一侧弹出（`MainPanelEdge` 原始值）
    static let mainPanelEdge = "copyx.mainPanelEdge"

    /// 独立窗口模式下保存的 frame（NSStringFromRect 格式）
    static let floatingPanelFrame = "copyx.floatingPanelFrame"

    /// 独立窗口是否固定在最前
    static let floatingPanelPinned = "copyx.floatingPanelPinned"

    // MARK: - iCloud 同步相关

    /// 是否启用 iCloud 同步
    static let iCloudSyncEnabled = "airclip.sync.enabled"

    /// 仅同步收藏项
    static let syncFavoritesOnly = "airclip.sync.favoritesOnly"

    /// 是否同步图片
    static let syncImages = "airclip.sync.images"

    /// 是否同步富文本
    static let syncRTF = "airclip.sync.rtf"

    /// 设备 ID（首次生成后持久化）
    static let deviceID = "airclip.deviceID"

    /// 上次同步时间
    static let lastSyncTime = "airclip.sync.lastSyncTime"

    /// CloudKit 变更 token（用于增量同步）
    static let serverChangeToken = "airclip.serverChangeToken"

    /// 是否已完成首次同步（用于判断是否需要全量下载）
    static let hasCompletedInitialSync = "airclip.sync.hasCompletedInitialSync"
}

/// 主面板弹出方向（影响窗口几何与 `ContentView` 布局）
enum MainPanelEdge: Int, CaseIterable {
    case left = 0
    case bottom = 1
    case floating = 2

    var displayName: String {
        switch self {
        case .left: return NSLocalizedString("main_panel_edge_left", comment: "")
        case .bottom: return NSLocalizedString("main_panel_edge_bottom", comment: "")
        case .floating: return NSLocalizedString("main_panel_edge_floating", comment: "")
        }
    }
}

/// 鼠标双击操作类型
enum DoubleClickAction: Int, CaseIterable {
    case copyAndPaste = 0  // 复制并粘贴
    case copyOnly = 1      // 仅复制
    
    var displayName: String {
        switch self {
        case .copyAndPaste: return NSLocalizedString("double_click_copy_and_paste", comment: "")
        case .copyOnly: return NSLocalizedString("double_click_copy_only", comment: "")
        }
    }
}

/// 内容类型枚举（用于类型过滤）
enum ContentType: String, CaseIterable {
    case file = "file"
    case image = "image"
    case link = "link"
    case text = "text"
    case color = "color"
    
    var displayName: String {
        switch self {
        case .file: return NSLocalizedString("content_type_file_singular", comment: "")
        case .image: return NSLocalizedString("content_type_image", comment: "")
        case .link: return NSLocalizedString("content_type_link", comment: "")
        case .text: return NSLocalizedString("content_type_text", comment: "")
        case .color: return NSLocalizedString("content_type_color", comment: "")
        }
    }
    
    var icon: String {
        switch self {
        case .file: return "doc.fill"
        case .image: return "photo.fill"
        case .link: return "link"
        case .text: return "doc.text.fill"
        case .color: return "paintpalette.fill"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .file: return .blue
        case .image: return .green
        case .link: return .purple
        case .text: return .orange
        case .color: return .pink
        }
    }
}

enum PreferencesDefaults {
    static let maxItemCount: Int = 500
    /// 默认最大 200MB
    static let maxTotalBytes: Int = 200 * 1024 * 1024
    /// 默认最大文件大小 50MB
    static let maxFileSizeBytes: Int = 50 * 1024 * 1024
    /// 默认最大缓存字符数（-1 表示无限制）
    static let maxTextCharacterCount: Int = -1
    static let hotkeyDisplay: String = "⌘⇧V"
    static let autoCloseAfterCopy: Bool = true
    /// 鼠标双击操作，默认为复制并粘贴
    static let doubleClickAction: DoubleClickAction = .copyAndPaste
    /// 始终以纯文本粘贴，默认关闭
    static let alwaysPastePlainText: Bool = false
    /// 默认永久保留（-1 表示永久）
    static let retentionSliderValue: Double = -1.0
    /// 默认屏蔽的应用列表
    static let blockedApps: [String] = ["com.apple.Passwords"]
    /// 默认忽略的内容类型（空数组，不忽略任何类型）
    static let ignoredContentTypes: [String] = []
    /// 默认忽略的关键字列表（空数组）
    static let ignoredKeywords: [String] = []

    /// 默认从左侧滑出主面板
    static let mainPanelEdge: MainPanelEdge = .left

    /// 独立窗口默认不固定在最前
    static let floatingPanelPinned: Bool = false

    // MARK: - iCloud 同步默认值

    /// iCloud 同步默认关闭
    static let iCloudSyncEnabled: Bool = false
    /// 默认同步所有项目（非仅收藏）
    static let syncFavoritesOnly: Bool = false
    /// 默认同步图片
    static let syncImages: Bool = true
    /// 默认同步富文本
    static let syncRTF: Bool = true
}


