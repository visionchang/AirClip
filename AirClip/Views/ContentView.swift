//
//  ContentView.swift
//  CopyX
//
//  Created by 张佳航 on 2025/11/18.
//


import SwiftUI
import SwiftData
import AppKit
import Combine

struct GradientMaterialBackground: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            // .glassEffect(.clear)
            .mask(
                LinearGradient(
                    colors: [
                        Color.white.opacity(1),
                        Color.white.opacity(0.45),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferencesKeys.mainPanelEdge) private var mainPanelEdgeStorage: Int = MainPanelEdge.left.rawValue
    @AppStorage(PreferencesKeys.floatingPanelPinned) private var floatingPanelPinned: Bool = PreferencesDefaults.floatingPanelPinned

    private var mainPanelEdgeResolved: MainPanelEdge {
        MainPanelEdge(rawValue: mainPanelEdgeStorage) ?? .left
    }

    // 搜索和过滤状态
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""  // 防抖后的搜索文本
    @State private var showFavoritesOnly: Bool = false
    @State private var selectedContentType: ContentType? = nil
    @State private var showFilterOptions: Bool = false
    @State private var selectedItemID: PersistentIdentifier?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var allowSearchFocus: Bool = false // 控制是否允许搜索框成为焦点，避免初次闪烁
    @State private var copiedItemID: PersistentIdentifier?  // 跟踪刚被复制的项目
    
    // 键盘监听器引用，用于防止重复创建和正确清理
    @State private var keyboardMonitor: Any?

    // 剪贴板数据变更通知监听器
    @State private var clipboardObserver: NSObjectProtocol?
    
    // 面板显示通知监听器
    @State private var panelShowObserver: NSObjectProtocol?
    
    // 辅助功能权限提示
    @State private var showAccessibilityAlert: Bool = false

    // 数据加载状态
    @State private var allItems: [ClipboardItem] = []          // 所有数据（内存中）
    @State private var filteredItems: [ClipboardItem] = []     // 过滤后的结果（直接显示全部）
    
    // 用于检测新项目的状态
    @State private var lastFirstItemID: PersistentIdentifier?  // 上次窗口关闭时的第一个项目ID

    // 防抖 Timer
    @State private var searchDebounceTask: Task<Void, Never>?

    var body: some View {
        Group {
            if mainPanelEdgeResolved == .bottom {
                VStack(spacing: 0) {
                    headerBottomPanel
                    horizontalListView
                }
            } else {
                VStack(spacing: 0) {
                    listView
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击任意位置时使搜索框失焦
            isSearchFieldFocused = false
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .onAppear {
            setupKeyboardMonitor()
            // 确保搜索框不会自动获取焦点，让方向键可以控制选择项目
            isSearchFieldFocused = false
            // 初始加载数据
            loadInitialData()
            // 监听剪贴板数据变更通知
            clipboardObserver = NotificationCenter.default.addObserver(
                forName: .clipboardDataDidChange,
                object: nil,
                queue: .main
            ) { _ in
                loadInitialData(fromClipboardChange: true)
            }
            // 监听面板显示通知，确保每次显示时搜索框不会获取焦点，并检测新项目
            panelShowObserver = NotificationCenter.default.addObserver(
                forName: .mainPanelDidShow,
                object: nil,
                queue: .main
            ) { [self] _ in
                self.isSearchFieldFocused = false
                self.allowSearchFocus = false
                // 额外清除第一响应者，确保系统级别的焦点也被移除
                DispatchQueue.main.async {
                    if let keyWindow = NSApp.keyWindow {
                        keyWindow.makeFirstResponder(nil)
                    }
                }
                // 检测是否有新项目并定位到第一个项目
                self.checkForNewItemsAndSelectFirst()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mainPanelHostWillTeardown)) { _ in
            detachPanelTransientObservers()
        }
        .onDisappear {
            detachPanelTransientObservers()
        }
        .onChange(of: searchText) { _, newValue in
            // 如果清空了搜索框，直接使用内存数据，不需要防抖
            if newValue.isEmpty {
                searchDebounceTask?.cancel()
                debouncedSearchText = newValue
                performSearch(selectFirstFilteredItem: true)
                return
            }

            // 搜索防抖：200ms 后执行搜索
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
                if !Task.isCancelled {
                    await MainActor.run {
                        debouncedSearchText = newValue
                        performSearch(selectFirstFilteredItem: true)
                    }
                }
            }
        }
        .onChange(of: showFavoritesOnly) { _, _ in
            performSearch(selectFirstFilteredItem: true)
        }
        .onChange(of: selectedContentType) { _, _ in
            performSearch(selectFirstFilteredItem: true)
        }
        .alert(
            NSLocalizedString("accessibility_permission_required", comment: "辅助功能权限"),
            isPresented: $showAccessibilityAlert
        ) {
            Button(NSLocalizedString("open_system_settings", comment: "打开系统设置")) {
                requestAccessibilityPermission()
            }
            Button(NSLocalizedString("cancel", comment: "取消"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("accessibility_permission_message", comment: "辅助功能权限说明"))
        }
    }
    
    // MARK: - 键盘监听

    private func mainPanelEdgeFromDefaults() -> MainPanelEdge {
        if UserDefaults.standard.object(forKey: PreferencesKeys.mainPanelEdge) == nil {
            return PreferencesDefaults.mainPanelEdge
        }
        return MainPanelEdge(rawValue: UserDefaults.standard.integer(forKey: PreferencesKeys.mainPanelEdge)) ?? .left
    }
    
    /// 拆掉与主面板窗口生命周期绑定的监听（键盘本地监视器、NotificationCenter、防抖任务）。`onDisappear` 与面板重建前通知各调一次，需可重复调用。
    private func detachPanelTransientObservers() {
        removeKeyboardMonitor()
        if let observer = clipboardObserver {
            NotificationCenter.default.removeObserver(observer)
            clipboardObserver = nil
        }
        if let observer = panelShowObserver {
            NotificationCenter.default.removeObserver(observer)
            panelShowObserver = nil
        }
        searchDebounceTask?.cancel()
    }

    // 移除键盘监听器
    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    // 打开设置窗口
    private func openSettingsWindow() {
        // 先关闭主面板
        AirClipApp.panelManager?.hide()
        
        // 先激活应用程序（这是关键步骤）
        NSApp.activate(ignoringOtherApps: true)
        
        // 打开设置窗口
        openWindow(id: "settings")
        
        // 延迟确保窗口获取焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // 再次激活应用程序（确保激活成功）
            NSApp.activate(ignoringOtherApps: true)
            
            // 找到设置窗口并激活（使用 identifier 而不是 title 更可靠）
            for window in NSApp.windows {
                // 检查是否是设置窗口（通过 identifier 或 title）
                if window.identifier?.rawValue == "settings" || window.title == NSLocalizedString("settings_title", comment: "") {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
        }
    }

    /// 收起主面板后使用系统屏幕取色，完成后写入剪贴板并重新打开面板
    private func startScreenColorPick() {
        isSearchFieldFocused = false
        allowSearchFocus = false
        AirClipApp.panelManager?.hide {
            NSApp.activate(ignoringOtherApps: true)
            NSCursor.hide()
            NSColorSampler().show { color in
                DispatchQueue.main.async {
                    defer { NSCursor.unhide() }
                    if let color {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        if let srgb = color.usingColorSpace(.sRGB) {
                            let r = Int(round(srgb.redComponent * 255))
                            let g = Int(round(srgb.greenComponent * 255))
                            let b = Int(round(srgb.blueComponent * 255))
                            let hex: String
                            if srgb.alphaComponent < 0.999 {
                                let a = Int(round(srgb.alphaComponent * 255))
                                hex = String(format: "#%02X%02X%02X%02X", r, g, b, a)
                            } else {
                                hex = String(format: "#%02X%02X%02X", r, g, b)
                            }
                            pasteboard.setString(hex, forType: .string)
                            pasteboard.writeObjects([srgb])
                        } else {
                            pasteboard.setString(color.description, forType: .string)
                            pasteboard.writeObjects([color])
                        }
                    }
                    AirClipApp.panelManager?.show()
                }
            }
        }
    }

    // 设置键盘监听器
    private func setupKeyboardMonitor() {
        // 防止重复创建监听器
        guard keyboardMonitor == nil else { return }
        
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // 如果事件不是发生在主面板窗口，不拦截，交给系统或其他窗口处理
            // 这样可以确保详情窗口、设置窗口等其他窗口的快捷键（如 Cmd+C 复制选中文本）正常工作
            if let window = event.window, 
               let panelWindow = AirClipApp.panelManager?.panelWindow, 
               window != panelWindow {
                return event
            }

            // 如果搜索框聚焦，不处理方向键（让搜索框处理）
            if self.isSearchFieldFocused {
                // ESC 键退出搜索框聚焦状态
                if event.keyCode == 53 { // Esc
                    self.isSearchFieldFocused = false
                    return nil
                }
                // 只处理快捷键
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
                    return nil
                }
                // Command+, 打开设置（即使搜索框聚焦也应该生效）
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
                    self.openSettingsWindow()
                    return nil
                }
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
                    if self.selectedItemID != nil {
                        self.copySelectedItem()
                        return nil
                    }
                }
                // 检测 Command+V（粘贴到活动应用）
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                    if self.selectedItemID != nil {
                        self.pasteSelectedItem()
                        return nil
                    }
                }
                return event
            }

            // 检测 Command+F（聚焦搜索框）
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
                // 先允许搜索框接受焦点，避免在首次打开时就被聚焦
                self.allowSearchFocus = true
                // 稍后再设置为聚焦，确保 focused modifier 已经生效
                DispatchQueue.main.async {
                    self.isSearchFieldFocused = true
                }
                return nil // 拦截事件
            }

            // 检测 Command+,（打开设置）
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
                self.openSettingsWindow()
                return nil
            }

            // 检测 Command+C（复制）
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
                if self.selectedItemID != nil {
                    self.copySelectedItem()
                    return nil // 拦截事件
                }
            }
            
            // 检测 Command+V（粘贴到活动应用）
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                if self.selectedItemID != nil {
                    self.pasteSelectedItem()
                    return nil // 拦截事件
                }
            }

            // 底部横条：左右方向键；左侧面板：上下方向键
            let edge = self.mainPanelEdgeFromDefaults()
            if edge == .bottom {
                if event.keyCode == 124 { // 右箭头
                    self.selectNextItem()
                    return nil
                }
                if event.keyCode == 123 { // 左箭头
                    self.selectPreviousItem()
                    return nil
                }
            } else {
                if event.keyCode == 125 { // 下箭头
                    self.selectNextItem()
                    return nil
                }
                if event.keyCode == 126 { // 上箭头
                    self.selectPreviousItem()
                    return nil
                }
            }

            // 检测 Esc 键，按下时关闭主面板（独立窗口固定时不响应）
            if event.keyCode == 53 { // Esc
                let currentEdge = self.mainPanelEdgeFromDefaults()
                let isPinned = UserDefaults.standard.bool(forKey: PreferencesKeys.floatingPanelPinned)
                if currentEdge == .floating && isPinned {
                    return event
                }
                AirClipApp.panelManager?.hide()
                return nil
            }

            // 检测 Enter 键（搜索框未聚焦时），执行粘贴操作
            if event.keyCode == 36 || event.keyCode == 76 { // Return 或 Numpad Enter
                if self.selectedItemID != nil {
                    self.pasteSelectedItem()
                    return nil
                }
            }

            return event
        }
    }

    // MARK: - 选择逻辑

    // 选择下一个项目
    private func selectNextItem() {
        guard !filteredItems.isEmpty else { return }

        if let currentID = selectedItemID,
           let currentIndex = filteredItems.firstIndex(where: { $0.persistentModelID == currentID }) {
            // 如果不是最后一个，选择下一个
            if currentIndex < filteredItems.count - 1 {
                selectedItemID = filteredItems[currentIndex + 1].persistentModelID
            }
        } else {
            // 如果没有选中项，选择第一个
            selectedItemID = filteredItems.first?.persistentModelID
        }
    }

    // 选择上一个项目
    private func selectPreviousItem() {
        guard !filteredItems.isEmpty else { return }

        if let currentID = selectedItemID,
           let currentIndex = filteredItems.firstIndex(where: { $0.persistentModelID == currentID }) {
            // 如果不是第一个，选择上一个
            if currentIndex > 0 {
                selectedItemID = filteredItems[currentIndex - 1].persistentModelID
            }
        } else {
            // 如果没有选中项，选择第一个
            selectedItemID = filteredItems.first?.persistentModelID
        }
    }

    // MARK: - 复制逻辑

    // 复制选中项目到剪贴板
    private func copySelectedItem() {
        guard let itemID = selectedItemID,
              let item = filteredItems.first(where: { $0.persistentModelID == itemID }) else {
            print("⚠️ 没有选中项目")
            return
        }

        print("📋 开始复制项目")

        // 应用内复制：将该条记录提到最新（保持原来源应用名称/图标不变）
        AirClipApp.clipboardMonitor?.markInternalCopy(itemID: item.persistentModelID)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var contentType = ""
        
        // 优先处理文件
        if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
            var nsURLObjects: [NSURL] = []
            for filePath in fileURLs {
                let url = URL(fileURLWithPath: filePath)
                if FileManager.default.fileExists(atPath: filePath) {
                    nsURLObjects.append(url as NSURL)
                }
            }
            if !nsURLObjects.isEmpty {
                pasteboard.writeObjects(nsURLObjects)
                if nsURLObjects.count == 1 {
                    let name = nsURLObjects[0].lastPathComponent ?? NSLocalizedString("unknown_file", comment: "")
                    contentType = String(format: NSLocalizedString("content_type_file_with_name", comment: ""), name)
                } else {
                    contentType = String(format: NSLocalizedString("content_type_files_count", comment: ""), nsURLObjects.count)
                }
            }
        } else if let text = item.text, !text.isEmpty {
            // 检查是否启用了"始终以纯文本粘贴"
            let alwaysPlainText = UserDefaults.standard.object(forKey: PreferencesKeys.alwaysPastePlainText) == nil
                ? PreferencesDefaults.alwaysPastePlainText
                : UserDefaults.standard.bool(forKey: PreferencesKeys.alwaysPastePlainText)
            
            // 如果有富文本数据且未启用纯文本模式，同时写入 RTF 和纯文本
            if let rtfData = item.rtfData, !alwaysPlainText {
                pasteboard.setData(rtfData, forType: .rtf)
                pasteboard.setString(text, forType: .string)
                let preview = text.count > 20 ? String(text.prefix(20)) + "..." : text
                contentType = String(format: NSLocalizedString("content_type_richtext_with_preview", comment: ""), preview)
            } else {
                pasteboard.setString(text, forType: .string)
                let preview = text.count > 20 ? String(text.prefix(20)) + "..." : text
                contentType = String(format: NSLocalizedString("content_type_text_with_preview", comment: ""), preview)
            }
        } else if let imageData = item.imageData,
           let image = NSImage(data: imageData) {
            pasteboard.writeObjects([image])
            contentType = NSLocalizedString("content_type_image", comment: "")
        }

        print("✅ 复制成功: \(contentType)")

        // 显示复制成功提示（在对应项目上）
        copiedItemID = itemID

        // 检查是否启用了自动关闭功能
        let autoClose = UserDefaults.standard.object(forKey: PreferencesKeys.autoCloseAfterCopy) == nil
            ? PreferencesDefaults.autoCloseAfterCopy
            : UserDefaults.standard.bool(forKey: PreferencesKeys.autoCloseAfterCopy)

        // 复制成功提示维持时间（仅用于高亮提示）
        let copyFeedbackDuration: TimeInterval = 1.0
        // 自动关闭主面板的延迟（缩短关闭时间，让操作更利落）
        let autoCloseDelay: TimeInterval = 0.5

        // 1秒后自动隐藏提示
        DispatchQueue.main.asyncAfter(deadline: .now() + copyFeedbackDuration) {
            copiedItemID = nil
        }

        // 如果启用了自动关闭，则更快关闭主面板（独立窗口已固定时不关闭，便于连续复制）
        if autoClose, !(mainPanelEdgeResolved == .floating && floatingPanelPinned) {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoCloseDelay) {
                AirClipApp.panelManager?.hide()
            }
        }
    }
    
    /// 粘贴选中项目到活动应用（快捷键 Command+V 使用）
    private func pasteSelectedItem() {
        guard let itemID = selectedItemID,
              let item = filteredItems.first(where: { $0.persistentModelID == itemID }) else {
            print("⚠️ 没有选中项目")
            return
        }
        
        // 检查是否启用了"始终以纯文本粘贴"
        let alwaysPlainText = UserDefaults.standard.object(forKey: PreferencesKeys.alwaysPastePlainText) == nil
            ? PreferencesDefaults.alwaysPastePlainText
            : UserDefaults.standard.bool(forKey: PreferencesKeys.alwaysPastePlainText)
        
        pasteItem(item, plainTextOnly: alwaysPlainText)
    }
    
    /// 以纯文本粘贴选中项目到活动应用（快捷键 Command+Shift+V 使用）
    private func pasteSelectedItemPlainText() {
        guard let itemID = selectedItemID,
              let item = filteredItems.first(where: { $0.persistentModelID == itemID }) else {
            print("⚠️ 没有选中项目")
            return
        }
        
        pasteItem(item, plainTextOnly: true)
    }
    
    /// 处理双击操作（根据设置决定行为）
    private func handleDoubleClick(_ item: ClipboardItem) {
        // 获取双击操作设置
        let actionRawValue = UserDefaults.standard.integer(forKey: PreferencesKeys.doubleClickAction)
        let action = DoubleClickAction(rawValue: actionRawValue) ?? PreferencesDefaults.doubleClickAction
        
        // 检查是否启用了"始终以纯文本粘贴"
        let alwaysPlainText = UserDefaults.standard.object(forKey: PreferencesKeys.alwaysPastePlainText) == nil
            ? PreferencesDefaults.alwaysPastePlainText
            : UserDefaults.standard.bool(forKey: PreferencesKeys.alwaysPastePlainText)
        
        switch action {
        case .copyAndPaste:
            // 复制并粘贴到活动应用
            pasteItem(item, plainTextOnly: alwaysPlainText)
        case .copyOnly:
            // 仅复制到剪贴板
            copySelectedItem()
        }
    }
    
    /// 复制指定项目到剪贴板（右键菜单使用）
    private func copyItem(_ item: ClipboardItem, plainTextOnly: Bool) {
        // 应用内复制：将该条记录提到最新（保持原来源应用名称/图标不变）
        AirClipApp.clipboardMonitor?.markInternalCopy(itemID: item.persistentModelID)
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        var contentType = ""
        
        // 优先处理文件
        if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
            var nsURLObjects: [NSURL] = []
            for filePath in fileURLs {
                let url = URL(fileURLWithPath: filePath)
                if FileManager.default.fileExists(atPath: filePath) {
                    nsURLObjects.append(url as NSURL)
                }
            }
            if !nsURLObjects.isEmpty {
                pasteboard.writeObjects(nsURLObjects)
                contentType = NSLocalizedString("content_type_file_singular", comment: "")
            }
        } else if let text = item.text, !text.isEmpty {
            // 如果有富文本数据且不是纯文本模式
            if let rtfData = item.rtfData, !plainTextOnly {
                pasteboard.setData(rtfData, forType: .rtf)
                pasteboard.setString(text, forType: .string)
                contentType = NSLocalizedString("content_type_richtext", comment: "")
            } else {
                pasteboard.setString(text, forType: .string)
                contentType = NSLocalizedString("content_type_text", comment: "")
            }
        } else if let imageData = item.imageData,
                  let image = NSImage(data: imageData) {
            pasteboard.writeObjects([image])
            contentType = NSLocalizedString("content_type_image", comment: "")
        }
        
        print("✅ 复制成功: \(contentType)")
        
        // 显示复制成功提示
        copiedItemID = item.persistentModelID
        
        // 1秒后自动隐藏提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            copiedItemID = nil
        }
    }
    
    /// 粘贴指定项目到活动应用（复制到剪贴板后模拟 Cmd+V）
    private func pasteItem(_ item: ClipboardItem, plainTextOnly: Bool) {
        // 检查辅助功能权限
        guard checkAccessibilityPermission() else {
            showAccessibilityAlert = true
            return
        }
        
        // 先复制到剪贴板
        copyItem(item, plainTextOnly: plainTextOnly)
        
        // 隐藏面板
        AirClipApp.panelManager?.hide()
        
        // 稍微延迟后模拟 Cmd+V 粘贴
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            simulatePaste()
        }
    }
    
    /// 模拟 Cmd+V 粘贴快捷键
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // 创建 Cmd+V 按下事件
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // 0x09 = V
        keyDown?.flags = .maskCommand
        
        // 创建 Cmd+V 释放事件
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        
        // 发送事件
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    /// 检查辅助功能权限
    private func checkAccessibilityPermission() -> Bool {
        // 检查是否已获得辅助功能权限
        return AXIsProcessTrusted()
    }
    
    /// 请求辅助功能权限（打开系统偏好设置）
    private func requestAccessibilityPermission() {
        // 构建系统偏好设置的 URL
        let prefPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(prefPaneURL)
    }
    
    /// 删除指定项目
    private func deleteItem(_ item: ClipboardItem) {
        // 如果删除的是当前选中项，清除选中状态
        if selectedItemID == item.persistentModelID {
            selectedItemID = nil
        }

        // 从内存数组中移除
        allItems.removeAll { $0.persistentModelID == item.persistentModelID }
        filteredItems.removeAll { $0.persistentModelID == item.persistentModelID }

        // 从数据库中删除
        modelContext.delete(item)

        do {
            try modelContext.save()
            print("🗑️ 删除成功")
        } catch {
            print("❌ 删除失败: \(error)")
        }
    }
    
    // MARK: - 视图组件

    private enum MainPanelSearchChromeStyle {
        case standard
        case bottomBar
    }

    @ViewBuilder
    private func searchFieldChrome(style: MainPanelSearchChromeStyle = .standard) -> some View {
        let hSpacing: CGFloat = (style == .bottomBar) ? 5 : 6
        let fieldPadding: CGFloat = (style == .bottomBar) ? 7 : 8
        let iconSize: CGFloat = (style == .bottomBar) ? 14 : 14
        let clearIconSize: CGFloat = (style == .bottomBar) ? 13 : 14
        let corner: CGFloat = (style == .bottomBar) ? 12 : 16

        HStack(spacing: hSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: iconSize))

            if allowSearchFocus {
                TextField("search_placeholder", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
            } else {
                TextField("search_placeholder", text: $searchText)
                    .textFieldStyle(.plain)
                    .onTapGesture {
                        allowSearchFocus = true
                        DispatchQueue.main.async {
                            isSearchFieldFocused = true
                        }
                    }
            }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: clearIconSize))
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(fieldPadding)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.black.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(isSearchFieldFocused ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }

    private static let filterTypeOrder: [ContentType] = [.text, .image, .color, .link, .file]

    private var filterChips: some View {
        HStack(spacing: 5) {
            Button {
                selectedContentType = nil
            } label: {
                Text(NSLocalizedString("filter_all", comment: ""))
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 22)
                    .background(
                        Capsule()
                            .fill(selectedContentType == nil ? Color.accentColor : Color.primary.opacity(0.06))
                    )
                    .foregroundColor(selectedContentType == nil ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)

            ForEach(Self.filterTypeOrder, id: \.self) { type in
                let isActive = selectedContentType == type
                Button {
                    selectedContentType = isActive ? nil : type
                } label: {
                    Image(systemName: type.icon)
                        .font(.system(size: 11))
                        .frame(width: 28, height: 22)
                        .background(
                            Capsule()
                                .fill(isActive ? type.iconColor : Color.primary.opacity(0.06))
                        )
                        .foregroundColor(isActive ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(type.displayName)
            }
        }
    }

    private var headerToolbarButtons: some View {
        HStack(spacing: 8) {
            Button {
                startScreenColorPick()
            } label: {
                Image(systemName: "eyedropper")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .accessibilityLabel(NSLocalizedString("pick_color_from_screen", comment: ""))

            Button {
                showFavoritesOnly.toggle()
            } label: {
                Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                    .foregroundColor(showFavoritesOnly ? .accentColor : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .focusable(false)

            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .focusable(false)
        }
    }

    private var headerBottomPanel: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 6) {
                filterToggleButton
                searchFieldChrome(style: .bottomBar)
                    .frame(maxWidth: 200)
                headerToolbarButtonsCompact
                if showFilterOptions {
                    filterChips
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            GradientMaterialBackground()
                .ignoresSafeArea()
        )
    }

    /// 底栏用：略减小间距，与紧凑搜索框协调
    private var headerToolbarButtonsCompact: some View {
        HStack(spacing: 8) {
            Button {
                startScreenColorPick()
            } label: {
                Image(systemName: "eyedropper")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .accessibilityLabel(NSLocalizedString("pick_color_from_screen", comment: ""))

            Button {
                showFavoritesOnly.toggle()
            } label: {
                Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                    .foregroundColor(showFavoritesOnly ? .accentColor : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .focusable(false)

            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .focusable(false)
        }
    }
    
    private var filterToggleButton: some View {
        let hasActiveFilter = selectedContentType != nil
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showFilterOptions.toggle()
            }
            if !showFilterOptions {
                selectedContentType = nil
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundColor(showFilterOptions || hasActiveFilter ? .accentColor : .secondary)
                .font(.system(size: 16))
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .help(NSLocalizedString("filter", comment: "筛选"))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mainPanelEdgeResolved == .floating {
                floatingWindowDragBar
            }
            HStack(spacing: 8) {
                filterToggleButton
                searchFieldChrome(style: .standard)
                headerToolbarButtons
            }
            if showFilterOptions {
                HStack(spacing: 5) {
                    filterChips
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(
            GradientMaterialBackground()
                .ignoresSafeArea()
        )
    }

    /// 独立窗口模式顶部：红绿灯按钮 | 拖动区域 | 锁定
    private var floatingWindowDragBar: some View {
        HStack(spacing: 6) {
            TrafficLightButtons(
                onClose: { AirClipApp.panelManager?.hide() },
                onMiniaturize: { AirClipApp.panelManager?.panelWindow?.miniaturize(nil) }
            )

            Spacer()

            Button {
                floatingPanelPinned.toggle()
                AirClipApp.panelManager?.setFloatingPinned(floatingPanelPinned)
            } label: {
                Image(systemName: floatingPanelPinned ? "pin.fill" : "pin")
                    .font(.system(size: 14))
                    .foregroundColor(floatingPanelPinned ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(floatingPanelPinned
                ? NSLocalizedString("unpin_window", comment: "")
                : NSLocalizedString("pin_window", comment: ""))
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func clipboardItemRow(item: ClipboardItem, index: Int, compactCarousel: Bool) -> some View {
        ClipboardItemRow(
            item: item,
            isSelected: selectedItemID == item.persistentModelID,
            isCopied: copiedItemID == item.persistentModelID,
            onSelect: {
                selectedItemID = item.persistentModelID
            },
            onDoubleClick: {
                selectedItemID = item.persistentModelID
                handleDoubleClick(item)
            },
            onCopy: {
                selectedItemID = item.persistentModelID
                copyItem(item, plainTextOnly: false)
            },
            onCopyPlainText: {
                selectedItemID = item.persistentModelID
                copyItem(item, plainTextOnly: true)
            },
            onPaste: {
                selectedItemID = item.persistentModelID
                pasteItem(item, plainTextOnly: false)
            },
            onPastePlainText: {
                selectedItemID = item.persistentModelID
                pasteItem(item, plainTextOnly: true)
            },
            onDelete: {
                deleteItem(item)
            },
            onViewDetails: {
                AirClipApp.panelManager?.hide()
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "item_detail", value: item.persistentModelID)
            },
            compactCarousel: compactCarousel
        )
        .environment(\.modelContext, modelContext)
        .id(item.persistentModelID)
    }
    
    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    Color.clear
                        .frame(height: 0)
                        .id("scrollTop")

                    if filteredItems.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.persistentModelID) { index, item in
                            clipboardItemRow(item: item, index: index, compactCarousel: false)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
            .onChange(of: selectedItemID) { _, newValue in
                if let itemID = newValue {
                    proxy.scrollTo(itemID, anchor: nil)
                }
            }
            .onChange(of: showFilterOptions) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    proxy.scrollTo("scrollTop", anchor: .top)
                }
            }
        }
    }

    private var horizontalListView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(alignment: .top, spacing: 8) {
                    if filteredItems.isEmpty {
                        emptyStateView
                            .frame(minWidth: 480)
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.persistentModelID) { index, item in
                            clipboardItemRow(item: item, index: index, compactCarousel: true)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .onChange(of: selectedItemID) { _, newValue in
                if let itemID = newValue {
                    proxy.scrollTo(itemID, anchor: .center)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    // 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: getEmptyStateIcon())
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(getEmptyStateMessage())
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            if !searchText.isEmpty || showFavoritesOnly || selectedContentType != nil {
                Text(getEmptyStateHint())
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private func getEmptyStateIcon() -> String {
        if !searchText.isEmpty {
            return "magnifyingglass"
        } else if selectedContentType != nil {
            return "line.3.horizontal.decrease.circle"
        } else if showFavoritesOnly {
            return "heart.slash"
        } else {
            return "tray"
        }
    }

    private func getEmptyStateMessage() -> String {
        if !searchText.isEmpty {
            return NSLocalizedString("empty_not_found", comment: "")
        } else if let type = selectedContentType {
            return String(format: NSLocalizedString("empty_no_type_results", comment: ""), type.displayName)
        } else if showFavoritesOnly {
            return NSLocalizedString("empty_no_favorites", comment: "")
        } else {
            return NSLocalizedString("empty_clipboard_empty", comment: "")
        }
    }

    private func getEmptyStateHint() -> String {
        if !searchText.isEmpty {
            return NSLocalizedString("empty_try_other_keywords", comment: "")
        } else if selectedContentType != nil {
            return NSLocalizedString("empty_try_other_filter", comment: "")
        } else if showFavoritesOnly {
            return NSLocalizedString("empty_tap_heart", comment: "")
        } else {
            return ""
        }
    }
    
    // MARK: - 数据加载方法
    
    /// 检测新项目并定位到第一个项目（窗口打开时调用）
    private func checkForNewItemsAndSelectFirst() {
        // 保存当前第一个项目ID（用于比较）
        let previousFirstItemID = lastFirstItemID
        
        // 重新加载数据以确保获取最新内容
        loadInitialData()
        
        // 延迟一点执行，确保数据加载完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            // 检查是否有新项目（第一个项目ID发生变化）
            if let newFirstItemID = filteredItems.first?.persistentModelID {
                // 如果第一个项目ID与上次不同，说明有新项目
                if newFirstItemID != previousFirstItemID {
                    // 定位到第一个项目
                    selectedItemID = newFirstItemID
                }
            }
            
            // 更新保存的第一个项目ID（用于下次比较）
            lastFirstItemID = filteredItems.first?.persistentModelID
        }
    }
    
    /// 初始加载数据（从数据库加载所有数据到内存）
    /// - Parameter fromClipboardChange: 为 true 时表示由剪贴板/同步等通知触发；若过滤列表首条变化则立即选中新首条（不必等面板再打开）
    private func loadInitialData(fromClipboardChange: Bool = false) {
        let previousFilteredFirst = fromClipboardChange ? filteredItems.first?.persistentModelID : nil

        // 从数据库加载所有数据
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // 不设置 fetchLimit，加载所有数据

        do {
            allItems = try modelContext.fetch(descriptor)
            print("✅ 已加载 \(allItems.count) 条数据到内存")
        } catch {
            print("❌ 加载数据失败: \(error)")
            allItems = []
        }

        // 执行首次搜索（实际上是过滤显示）
        performSearch()

        if fromClipboardChange {
            if let newFirst = filteredItems.first?.persistentModelID,
               newFirst != previousFilteredFirst {
                selectedItemID = newFirst
                lastFirstItemID = newFirst
            }
            return
        }

    }

    private func contentType(for item: ClipboardItem) -> ContentType {
        if let fileURLs = item.fileURLs, !fileURLs.isEmpty { return .file }
        if item.imageData != nil { return .image }
        let head = String((item.text ?? "").prefix(4096)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return .text }
        if ColorUtils.isColorString(head) { return .color }
        if URLUtils.isURL(head) { return .link }
        return .text
    }

    /// 执行搜索（在内存中过滤数据）
    /// - Parameter selectFirstFilteredItem: 为 true 时在筛选/搜索条件变化后选中当前列表第一项（列表为空则清除选中）
    private func performSearch(selectFirstFilteredItem: Bool = false) {
        let keyword = debouncedSearchText.lowercased()
        let favoritesOnly = showFavoritesOnly
        let typeFilter = selectedContentType

        var result = allItems

        if let type = typeFilter {
            result = result.filter { contentType(for: $0) == type }
        }

        if favoritesOnly {
            result = result.filter { $0.isFavorite }
        }

        if !keyword.isEmpty {
            result = result.filter { item in
                (item.text?.lowercased().contains(keyword) ?? false) ||
                item.appName.lowercased().contains(keyword)
            }
        }

        filteredItems = result

        if selectFirstFilteredItem {
            selectedItemID = filteredItems.first?.persistentModelID
        }
    }
}

// MARK: - 仿原生红绿灯按钮

/// 模拟 macOS 原生窗口控制按钮：默认纯色圆点，鼠标悬停时显示图标
private struct TrafficLightButtons: View {
    var onClose: () -> Void
    var onMiniaturize: () -> Void

    @State private var isHovering = false
    @State private var closePressed = false
    @State private var miniPressed = false

    private let diameter: CGFloat = 12
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            trafficButton(
                color: Color(red: 1.0, green: 0.38, blue: 0.34),
                pressedColor: Color(red: 0.78, green: 0.24, blue: 0.22),
                icon: "xmark",
                iconSize: 7.5,
                isPressed: $closePressed,
                action: onClose
            )

            trafficButton(
                color: Color(red: 1.0, green: 0.74, blue: 0.18),
                pressedColor: Color(red: 0.80, green: 0.58, blue: 0.10),
                icon: "minus",
                iconSize: 9,
                isPressed: $miniPressed,
                action: onMiniaturize
            )
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private func trafficButton(
        color: Color,
        pressedColor: Color,
        icon: String,
        iconSize: CGFloat,
        isPressed: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        Circle()
            .fill(isPressed.wrappedValue ? pressedColor : color)
            .frame(width: diameter, height: diameter)
            .overlay {
                if isHovering {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .heavy))
                        .foregroundColor(.black.opacity(0.45))
                }
            }
            .onTapGesture {
                action()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed.wrappedValue = true }
                    .onEnded { _ in isPressed.wrappedValue = false }
            )
    }
}
