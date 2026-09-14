import Foundation
import AppKit
import Carbon

/// 全局快捷键管理（支持自定义快捷键）
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()
    
    /// 快捷键触发时回调
    var onTrigger: (() -> Void)?
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    /// 默认快捷键：Command + Shift + V
    static let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_V)
    static let defaultModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    
    /// 当前快捷键配置
    private(set) var currentKeyCode: UInt32 = defaultKeyCode
    private(set) var currentModifiers: UInt32 = defaultModifiers
    
    private init() {
        loadAndRegisterHotKey()
    }
    
    deinit {
        unregisterHotKey()
    }
    
    /// 从 UserDefaults 加载并注册快捷键
    private func loadAndRegisterHotKey() {
        let defaults = UserDefaults.standard
        
        // 如果有保存的配置，使用保存的配置
        if defaults.object(forKey: PreferencesKeys.hotkeyKeyCode) != nil {
            currentKeyCode = UInt32(defaults.integer(forKey: PreferencesKeys.hotkeyKeyCode))
            currentModifiers = UInt32(defaults.integer(forKey: PreferencesKeys.hotkeyModifiers))
        }
        
        registerHotKey(keyCode: currentKeyCode, modifiers: currentModifiers)
    }
    
    /// 注册快捷键
    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        // 先取消之前的注册
        unregisterHotKey()
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyReleased))
        
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>
                .fromOpaque(userData)
                .takeUnretainedValue()
            manager.onTrigger?()
            return noErr
        }
        
        let userData = Unmanaged.passUnretained(self).toOpaque()
        
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         callback,
                                         1,
                                         &eventType,
                                         userData,
                                         &eventHandlerRef)
        guard status == noErr else { return }
        
        let hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: "cpyx".hashValue)),
                                     id: 1)
        
        let registerStatus = RegisterEventHotKey(keyCode,
                                                 modifiers,
                                                 hotKeyID,
                                                 GetApplicationEventTarget(),
                                                 0,
                                                 &hotKeyRef)
        if registerStatus != noErr {
            print("注册全局快捷键失败: \(registerStatus)")
        }
    }
    
    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
    
    /// 更新快捷键
    /// - Parameters:
    ///   - keyCode: Carbon keyCode (kVK_ 值)
    ///   - modifiers: Carbon modifier flags
    ///   - displayString: 用于显示的字符串，如 "⌘⇧V"
    func updateHotKey(keyCode: UInt32, modifiers: UInt32, displayString: String) {
        // 保存到 UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: PreferencesKeys.hotkeyKeyCode)
        defaults.set(Int(modifiers), forKey: PreferencesKeys.hotkeyModifiers)
        defaults.set(displayString, forKey: PreferencesKeys.hotkeyDisplay)
        
        // 更新当前配置
        currentKeyCode = keyCode
        currentModifiers = modifiers
        
        // 重新注册快捷键
        registerHotKey(keyCode: keyCode, modifiers: modifiers)
    }
    
    /// 重置为默认快捷键
    func resetToDefault() {
        updateHotKey(keyCode: Self.defaultKeyCode, modifiers: Self.defaultModifiers, displayString: "⌘+⇧+V")
    }
}

// MARK: - 辅助函数

extension GlobalHotKeyManager {
    
    /// 将 NSEvent.ModifierFlags 转换为 Carbon modifier flags
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        return carbonFlags
    }
    
    /// 将 NSEvent keyCode 转换为 Carbon keyCode（实际上它们是相同的）
    static func carbonKeyCode(from keyCode: UInt16) -> UInt32 {
        return UInt32(keyCode)
    }
    
    /// 生成快捷键显示字符串
    static func displayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        
        // 获取按键名称
        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)
        
        return parts.joined(separator: "+")
    }
    
    /// 将 keyCode 转换为可读字符串
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        // 字母键
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        // 数字键
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
        // 功能键
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        // 特殊键
        case kVK_Space: return "空格"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        // 符号键
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        default: return "?"
        }
    }
}


