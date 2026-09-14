//
//  PanelWindow.swift
//  CopyX
//
//  自定义面板窗口，支持键盘输入但不抢夺其他应用的焦点
//

import AppKit

final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false  // 不成为主窗口，避免激活应用
    }
}


