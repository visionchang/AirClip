import Foundation
import SwiftUI
import AppKit
import SwiftData

/// 面板显示通知
extension Notification.Name {
    static let mainPanelDidShow = Notification.Name("mainPanelDidShow")
    /// 主面板宿主即将被关闭/重建（`NSWindow.close` 不一定会触发 SwiftUI `onDisappear`，需据此主动拆掉 `NSEvent` 等监听）
    static let mainPanelHostWillTeardown = Notification.Name("mainPanelHostWillTeardown")
}

/// 管理主面板窗口（左侧/底部滑出 + 独立窗口模式），并提供动画
final class MainPanelManager {
    private let modelContainer: ModelContainer
    private(set) var panelWindow: NSWindow?
    private var isVisible: Bool = false
    /// 点击**其他应用**窗口外区域时收起（同应用内点击不会经过此监听器）
    private var outsideClickGlobalMonitor: Any?
    /// 点击**本应用**其他窗口（如设置）时在主面板外则收起
    private var outsideClickLocalMonitor: Any?

    /// 独立窗口模式下，监听窗口移动/缩放以持久化 frame
    private var windowDidMoveObserver: NSObjectProtocol?
    private var windowDidResizeObserver: NSObjectProtocol?

    /// 记录当前窗口对应的模式，切换时需要重建
    private var currentWindowEdge: MainPanelEdge?
    
    /// 主视图距离屏幕边缘的外间距（模拟 margin）
    private let marginLeft: CGFloat = 10
    private let marginRight: CGFloat = 10
    private let marginTop: CGFloat = 10
    private let marginBottom: CGFloat = 10
    
    /// 左侧面板宽度（可根据需要调整）
    private let panelWidth: CGFloat = 360

    /// 底部横条模式下的窗口高度（需容纳 `ContentView` 顶栏 + 220pt 高卡片行）
    private let bottomPanelHeight: CGFloat = 300

    /// 独立窗口默认尺寸（宽度与左侧面板一致）
    private let floatingDefaultHeight: CGFloat = 900
    private let floatingMinHeight: CGFloat = 400
    
    private func resolvedMainPanelEdge() -> MainPanelEdge {
        if UserDefaults.standard.object(forKey: PreferencesKeys.mainPanelEdge) == nil {
            return PreferencesDefaults.mainPanelEdge
        }
        let raw = UserDefaults.standard.integer(forKey: PreferencesKeys.mainPanelEdge)
        return MainPanelEdge(rawValue: raw) ?? PreferencesDefaults.mainPanelEdge
    }

    private func resolvedFloatingPinned() -> Bool {
        if UserDefaults.standard.object(forKey: PreferencesKeys.floatingPanelPinned) == nil {
            return PreferencesDefaults.floatingPanelPinned
        }
        return UserDefaults.standard.bool(forKey: PreferencesKeys.floatingPanelPinned)
    }
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// 预加载面板窗口（在应用启动时调用，避免首次显示时延迟）
    func preloadPanel() {
        let edge = resolvedMainPanelEdge()
        let startFrame: NSRect
        if edge == .floating {
            startFrame = floatingPanelFrame()
        } else {
            guard let screen = NSScreen.main else { return }
            startFrame = hiddenFrame(for: edge, screen: screen)
        }

        let window = createPanelWindow(initialFrame: startFrame, edge: edge)
        panelWindow = window
        currentWindowEdge = edge
    }

    func togglePanel() {
        if isVisible {
            hidePanel(completion: nil)
        } else {
            showPanel()
        }
    }

    /// 显示面板（已显示时不再重复执行）
    func show() {
        guard !isVisible else { return }
        showPanel()
    }

    func hide(completion: (() -> Void)? = nil) {
        hidePanel(completion: completion)
    }

    /// 切换独立窗口的固定状态
    func setFloatingPinned(_ pinned: Bool) {
        UserDefaults.standard.set(pinned, forKey: PreferencesKeys.floatingPanelPinned)
        guard let window = panelWindow, resolvedMainPanelEdge() == .floating else { return }
        window.level = pinned ? .floating : .normal
    }

    /// 模式变更时重建窗口（由设置界面调用）
    func rebuildPanelForEdgeChange() {
        let newEdge = resolvedMainPanelEdge()
        guard newEdge != currentWindowEdge else { return }

        // 无论当前是否显示，先卸掉滑出模式下的点击监听，避免残留或重复注册
        removeOutsideClickMonitors()

        // 在关闭窗口前拆掉 ContentView 里的本地键盘/通知监听，否则会残留多个 keyDown monitor，导致按键失效
        NotificationCenter.default.post(name: .mainPanelHostWillTeardown, object: nil)

        let wasVisible = isVisible
        if wasVisible {
            panelWindow?.orderOut(nil)
            isVisible = false
        }
        removeFrameObservers()
        panelWindow?.close()
        panelWindow = nil

        let frame: NSRect
        if newEdge == .floating {
            frame = floatingPanelFrame()
        } else if let screen = NSScreen.main {
            frame = hiddenFrame(for: newEdge, screen: screen)
        } else {
            return
        }

        let window = createPanelWindow(initialFrame: frame, edge: newEdge)
        panelWindow = window
        currentWindowEdge = newEdge

        if wasVisible {
            showPanel()
        }
    }
    
    private func showPanel() {
        ensureWindowMatchesEdge()
        guard let window = panelWindow else { return }

        let edge = resolvedMainPanelEdge()

        if edge == .floating {
            showFloatingPanel(window: window)
        } else {
            guard let screen = NSScreen.main else { return }
            showSlidingPanel(window: window, edge: edge, screen: screen)
        }
    }

    private func showSlidingPanel(window: NSWindow, edge: MainPanelEdge, screen: NSScreen) {
        let startFrame = hiddenFrame(for: edge, screen: screen)
        let showFrame = shownFrame(for: edge, screen: screen)

        window.setFrame(startFrame, display: false)
        window.orderFront(nil)
        window.orderFrontRegardless()

        installOutsideClickMonitors()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(showFrame, display: true)
        } completionHandler: {
            self.isVisible = true
            window.makeKey()
            NotificationCenter.default.post(name: .mainPanelDidShow, object: nil)
        }
    }

    private func showFloatingPanel(window: NSWindow) {
        let frame = floatingPanelFrame()
        window.setFrame(frame, display: true)

        window.alphaValue = 0
        window.orderFront(nil)
        window.orderFrontRegardless()

        installFrameObservers(for: window)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 1
        } completionHandler: {
            self.isVisible = true
            window.makeKey()
            NotificationCenter.default.post(name: .mainPanelDidShow, object: nil)
        }
    }

    // MARK: - 窗口几何（左侧 / 底部）

    private func hiddenFrame(for edge: MainPanelEdge, screen: NSScreen) -> NSRect {
        switch edge {
        case .left:
            return leftPanelHiddenFrame(screen: screen)
        case .bottom:
            return bottomPanelHiddenFrame(screen: screen)
        case .floating:
            return floatingPanelFrame()
        }
    }

    private func shownFrame(for edge: MainPanelEdge, screen: NSScreen) -> NSRect {
        switch edge {
        case .left:
            return leftPanelShownFrame(screen: screen)
        case .bottom:
            return bottomPanelShownFrame(screen: screen)
        case .floating:
            return floatingPanelFrame()
        }
    }

    private func leftPanelVerticalMetrics(screen: NSScreen) -> (y: CGFloat, height: CGFloat) {
        let visible = screen.visibleFrame
        let full = screen.frame
        let top = visible.maxY - marginTop
        let bottomAlignedY = full.minY + marginBottom
        let height = top - bottomAlignedY
        return (bottomAlignedY, height)
    }

    private func leftPanelHiddenFrame(screen: NSScreen) -> NSRect {
        let full = screen.frame
        let (y, height) = leftPanelVerticalMetrics(screen: screen)
        let startX = full.minX
        return NSRect(x: startX, y: y, width: panelWidth, height: height)
    }

    private func leftPanelShownFrame(screen: NSScreen) -> NSRect {
        let full = screen.frame
        let (y, height) = leftPanelVerticalMetrics(screen: screen)
        let showX = full.minX + marginLeft
        return NSRect(x: showX, y: y, width: panelWidth, height: height)
    }

    private func bottomPanelHiddenFrame(screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        let full = screen.frame
        let width = vf.width - marginLeft - marginRight
        let x = vf.minX + marginLeft
        let hideY = full.minY - bottomPanelHeight
        return NSRect(x: x, y: hideY, width: width, height: bottomPanelHeight)
    }

    private func bottomPanelShownFrame(screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        let full = screen.frame
        let width = vf.width - marginLeft - marginRight
        let x = vf.minX + marginLeft
        let showY = full.minY + marginBottom
        return NSRect(x: x, y: showY, width: width, height: bottomPanelHeight)
    }

    // MARK: - 独立窗口几何

    private func floatingPanelFrame() -> NSRect {
        if let frameString = UserDefaults.standard.string(forKey: PreferencesKeys.floatingPanelFrame),
           !frameString.isEmpty {
            let rect = NSRectFromString(frameString)
            if rect.height >= floatingMinHeight {
                return NSRect(x: rect.origin.x, y: rect.origin.y,
                              width: panelWidth, height: rect.height)
            }
        }
        guard let screen = NSScreen.main else {
            return NSRect(x: 200, y: 200, width: panelWidth, height: floatingDefaultHeight)
        }
        let x = screen.visibleFrame.midX - panelWidth / 2
        let y = screen.visibleFrame.midY - floatingDefaultHeight / 2
        return NSRect(x: x, y: y, width: panelWidth, height: floatingDefaultHeight)
    }

    private func saveFloatingPanelFrame() {
        guard resolvedMainPanelEdge() == .floating, let window = panelWindow else { return }
        let frameString = NSStringFromRect(window.frame)
        UserDefaults.standard.set(frameString, forKey: PreferencesKeys.floatingPanelFrame)
    }

    // MARK: - 隐藏面板
    
    private func hidePanel(completion: (() -> Void)?) {
        guard let window = panelWindow else {
            completion?()
            return
        }
        if !isVisible {
            completion?()
            return
        }

        let edge = resolvedMainPanelEdge()

        if edge == .floating {
            hideFloatingPanel(window: window, completion: completion)
        } else {
            guard let screen = window.screen ?? NSScreen.main else {
                completion?()
                return
            }
            hideSlidingPanel(window: window, edge: edge, screen: screen, completion: completion)
        }
    }

    private func hideSlidingPanel(window: NSWindow, edge: MainPanelEdge, screen: NSScreen, completion: (() -> Void)?) {
        let startFrame = shownFrame(for: edge, screen: screen)
        let hideFrame = hiddenFrame(for: edge, screen: screen)

        window.setFrame(startFrame, display: false)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(hideFrame, display: true)
        } completionHandler: {
            window.orderOut(nil)
            self.isVisible = false
            self.removeOutsideClickMonitors()
            completion?()
        }
    }

    private func hideFloatingPanel(window: NSWindow, completion: (() -> Void)?) {
        saveFloatingPanelFrame()
        removeFrameObservers()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
            self.isVisible = false
            completion?()
        }
    }
    
    // MARK: - 窗口创建

    private func createPanelWindow(initialFrame: NSRect, edge: MainPanelEdge) -> NSWindow {
        let contentView = ContentView()
            .modelContainer(modelContainer)
            .environment(AirClipApp.settingsRouter)

        let hostingController = NSHostingController(rootView: contentView)

        if edge == .floating {
            return createFloatingWindow(initialFrame: initialFrame, hostingController: hostingController)
        } else {
            return createSlideWindow(initialFrame: initialFrame, hostingController: hostingController)
        }
    }

    private func createSlideWindow(initialFrame: NSRect, hostingController: NSHostingController<some View>) -> NSWindow {
        let window = PanelWindow(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.hidesOnDeactivate = false

        window.becomesKeyOnlyIfNeeded = false

        applyCornerRadius(to: window, radius: 18)
        return window
    }

    private func createFloatingWindow(initialFrame: NSRect, hostingController: NSHostingController<some View>) -> NSWindow {
        let window = PanelWindow(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable, .miniaturizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: panelWidth, height: floatingMinHeight)
        window.maxSize = NSSize(width: panelWidth, height: CGFloat.greatestFiniteMagnitude)

        window.becomesKeyOnlyIfNeeded = false

        let pinned = resolvedFloatingPinned()
        window.level = pinned ? .floating : .normal

        applyCornerRadius(to: window, radius: 18)
        return window
    }

    private func applyCornerRadius(to window: NSWindow, radius: CGFloat) {
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = radius
            contentView.layer?.masksToBounds = true
        }
        if let superview = window.contentView?.superview {
            superview.wantsLayer = true
            superview.layer?.cornerRadius = radius
            superview.layer?.masksToBounds = true
        }
    }

    // MARK: - 模式一致性检查

    /// 确保当前窗口与偏好中的模式匹配，不匹配则重建
    private func ensureWindowMatchesEdge() {
        let edge = resolvedMainPanelEdge()
        if currentWindowEdge != edge {
            rebuildPanelForEdgeChange()
        }
    }

    // MARK: - 点击外部关闭（仅左侧/底部模式）

    private func installOutsideClickMonitors() {
        if outsideClickGlobalMonitor == nil {
            outsideClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                self?.dismissPanelIfClickOutside()
            }
        }
        if outsideClickLocalMonitor == nil {
            outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                self?.dismissPanelIfClickOutside()
                return event
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let monitor = outsideClickGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickGlobalMonitor = nil
        }
        if let monitor = outsideClickLocalMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickLocalMonitor = nil
        }
    }

    private func dismissPanelIfClickOutside() {
        guard isVisible, let window = panelWindow else { return }
        let mouseLocation = NSEvent.mouseLocation
        if !window.frame.contains(mouseLocation) {
            hidePanel(completion: nil)
        }
    }

    // MARK: - 独立窗口 frame 持久化监听

    private func installFrameObservers(for window: NSWindow) {
        removeFrameObservers()
        windowDidMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.saveFloatingPanelFrame()
        }
        windowDidResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.saveFloatingPanelFrame()
        }
    }

    private func removeFrameObservers() {
        if let obs = windowDidMoveObserver {
            NotificationCenter.default.removeObserver(obs)
            windowDidMoveObserver = nil
        }
        if let obs = windowDidResizeObserver {
            NotificationCenter.default.removeObserver(obs)
            windowDidResizeObserver = nil
        }
    }
}


