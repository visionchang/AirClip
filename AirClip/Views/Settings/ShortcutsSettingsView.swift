import SwiftUI
import Carbon

struct ShortcutsSettingsView: View {
    @State private var hotkeyDisplay: String = UserDefaults.standard.string(forKey: PreferencesKeys.hotkeyDisplay) ?? PreferencesDefaults.hotkeyDisplay
    @State private var isRecording: Bool = false
    @State private var localMonitor: Any?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("appear_panel")
                    Spacer()
                    
                    // 快捷键显示/录制按钮
                    Button(action: {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isRecording {
                                Text("press_shortcut")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(hotkeyDisplay.split(separator: "+"), id: \.self) { key in
                                    KeyCapView(key: String(key))
                                }
                            }
                        }
                        .frame(minHeight: 24)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // 重置按钮
                HStack {
                    Spacer()
                    Button("reset_to_default") {
                        resetToDefault()
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }
            } header: {
                Text("global_shortcut_header")
            } footer: {
                Text("global_shortcut_footer")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("shortcuts")
        .onDisappear {
            stopRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        
        // 添加本地事件监听
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
            return nil // 消费事件
        }
    }
    
    private func stopRecording() {
        isRecording = false
        
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // 如果按下 Escape，取消录制
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        
        // 必须包含至少一个修饰键（Command、Control 或 Option）
        let hasRequiredModifier = modifiers.contains(.command) || 
                                  modifiers.contains(.control) || 
                                  modifiers.contains(.option)
        
        guard hasRequiredModifier else { return }
        
        // 忽略只按修饰键的情况
        let keyCode = event.keyCode
        let modifierOnlyKeys: [UInt16] = [
            UInt16(kVK_Command), UInt16(kVK_Shift), 
            UInt16(kVK_Option), UInt16(kVK_Control),
            UInt16(kVK_RightCommand), UInt16(kVK_RightShift),
            UInt16(kVK_RightOption), UInt16(kVK_RightControl)
        ]
        
        if modifierOnlyKeys.contains(keyCode) { return }
        
        // 生成显示字符串
        let displayString = GlobalHotKeyManager.displayString(keyCode: keyCode, modifiers: modifiers)
        
        // 转换为 Carbon 格式
        let carbonKeyCode = GlobalHotKeyManager.carbonKeyCode(from: keyCode)
        let carbonModifiers = GlobalHotKeyManager.carbonModifiers(from: modifiers)
        
        // 更新快捷键
        GlobalHotKeyManager.shared.updateHotKey(keyCode: carbonKeyCode, modifiers: carbonModifiers, displayString: displayString)
        
        // 更新显示
        hotkeyDisplay = displayString
        
        // 停止录制
        stopRecording()
    }
    
    private func resetToDefault() {
        GlobalHotKeyManager.shared.resetToDefault()
        hotkeyDisplay = "⌘+⇧+V"
    }
}

