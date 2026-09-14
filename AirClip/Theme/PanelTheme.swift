import SwiftUI

/// 面板相关的统一配色，方便后续整体调整
enum PanelTheme {
    /// 顶部区域背景色（搜索与过滤区域）
    static var headerBackground: Color { Color.white.opacity(0.08) }
    
    /// 每一条剪贴板记录的背景色
    static var itemBackground: Color { Color.white.opacity(0.20) }
}


