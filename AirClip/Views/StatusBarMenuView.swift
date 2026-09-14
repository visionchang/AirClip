import SwiftUI
import AppKit
import Carbon

struct StatusBarMenuView: View {
    let panelManager: MainPanelManager
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var monitoringState: ClipboardMonitoringState

    /// 获取快捷键字符（用于 keyboardShortcut）
    private var panelShortcutKey: KeyEquivalent {
        let defaults = UserDefaults.standard
        // 检查是否有保存的值，如果没有则使用默认值
        let keyCode: Int
        if defaults.object(forKey: PreferencesKeys.hotkeyKeyCode) != nil {
            keyCode = defaults.integer(forKey: PreferencesKeys.hotkeyKeyCode)
        } else {
            keyCode = Int(GlobalHotKeyManager.defaultKeyCode)
        }
        let char = keyCodeToCharacter(keyCode)
        return KeyEquivalent(char)
    }

    /// 获取快捷键修饰键（用于 keyboardShortcut）
    private var panelShortcutModifiers: SwiftUI.EventModifiers {
        let defaults = UserDefaults.standard
        // 检查是否有保存的值，如果没有则使用默认值
        let carbonModifiers: Int
        if defaults.object(forKey: PreferencesKeys.hotkeyModifiers) != nil {
            carbonModifiers = defaults.integer(forKey: PreferencesKeys.hotkeyModifiers)
        } else {
            carbonModifiers = Int(GlobalHotKeyManager.defaultModifiers)
        }
        return carbonToEventModifiers(UInt32(carbonModifiers))
    }

    /// 将 Carbon keyCode 转换为字符
    private func keyCodeToCharacter(_ keyCode: Int) -> Character {
        switch keyCode {
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "v" // 默认 V
        }
    }

    /// 将 Carbon modifier flags 转换为 SwiftUI EventModifiers
    private func carbonToEventModifiers(_ carbonFlags: UInt32) -> SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if carbonFlags & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        if carbonFlags & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if carbonFlags & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if carbonFlags & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        return modifiers
    }

    var body: some View {

        Button("open_main_panel") {
            panelManager.togglePanel()
        }
        .keyboardShortcut(panelShortcutKey, modifiers: panelShortcutModifiers)

        Button("settings_ellipsis") {
            openSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        // 暂停/恢复录制（位于设置下方）
        Button {
            guard let monitor = AirClipApp.clipboardMonitor else { return }
            if monitoringState.isPaused {
                monitor.resumeMonitoring()
            } else {
                monitor.pauseMonitoring()
            }
            monitoringState.isPaused = monitor.isMonitoringPausedPublic
        } label: {
            Text(LocalizedStringKey(monitoringState.isPaused ? "resume_recording" : "pause_recording"))
        }

        Divider()

        Button("quit_airclip") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    // 打开设置窗口并激活应用
    private func openSettingsWindow() {
        // 先关闭主面板（避免后续弹窗从面板窗口发起）
        AirClipApp.panelManager?.hide()

        // 先激活应用程序（确保后续窗口/弹窗走正确的 keyWindow）
        NSApp.activate(ignoringOtherApps: true)

        // 打开设置窗口
        openWindow(id: "settings")

        // 延迟确保窗口已创建并获取焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)

            for window in NSApp.windows {
                if window.identifier?.rawValue == "settings" || window.title == NSLocalizedString("settings_title", comment: "") {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
        }
    }
}


