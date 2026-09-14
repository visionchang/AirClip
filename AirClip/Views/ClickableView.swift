//
//  ClickableView.swift
//  CopyX
//
//  Created by 张佳航 on 2025/11/18.
//

import SwiftUI
import AppKit

// MARK: - 可点击视图（支持即时单击和双击）

struct ClickableView: NSViewRepresentable {
    let onClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ClickHandlingView()
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? ClickHandlingView {
            view.onClick = onClick
            view.onDoubleClick = onDoubleClick
        }
    }
}

class ClickHandlingView: NSView {
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 允许右下角区域（收藏按钮所在区域）把事件传给 SwiftUI 按钮，避免被整块遮挡
    override func hitTest(_ point: NSPoint) -> NSView? {
        let ignoreSize: CGFloat = 40
        let ignoreRect = NSRect(
            x: bounds.maxX - ignoreSize,
            y: 0,
            width: ignoreSize,
            height: ignoreSize
        )

        if ignoreRect.contains(point) {
            return nil
        }

        return self
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 {
            print("🖱️ 单击触发")
            onClick?()
        } else if event.clickCount == 2 {
            print("🖱️🖱️ 双击触发")
            onDoubleClick?()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

