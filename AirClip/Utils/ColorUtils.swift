//
//  ColorUtils.swift
//  CopyX
//
//  Created by 张佳航 on 2025/11/18.
//

import SwiftUI
import AppKit

// MARK: - 颜色工具类

enum ColorUtils {
    
    /// 检测字符串是否是颜色值
    static func isColorString(_ string: String) -> Bool {
        parseColor(from: string) != nil
    }
    
    /// 从字符串解析颜色
    static func parseColor(from string: String) -> Color? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // 检查是否是 HEX 颜色格式
        if let hexColor = parseHexColor(trimmed) {
            return hexColor
        }

        // 检查是否是 RGB/RGBA 格式
        if let rgbColor = parseRGBColor(trimmed) {
            return rgbColor
        }

        return nil
    }
    
    /// 判断颜色是否为深色
    static func isDarkColor(_ color: Color) -> Bool {
        // 将 SwiftUI Color 转换为 NSColor
        let nsColor = NSColor(color)

        // 转换到 RGB 色彩空间
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
            return false
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        // 使用相对亮度公式（人眼对绿色最敏感）
        // 参考：https://www.w3.org/TR/WCAG20/#relativeluminancedef
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue

        // 亮度小于 0.5 认为是深色
        return luminance < 0.5
    }

    /// 解析 HEX 颜色 (#RGB, #RRGGBB, #RRGGBBAA)
    static func parseHexColor(_ string: String) -> Color? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // HEX 格式必须带 # 号才判断为颜色
        guard trimmed.hasPrefix("#") else {
            return nil
        }

        // 移除 # 号
        var hex = String(trimmed.dropFirst())

        // 检查长度是否有效
        guard [3, 6, 8].contains(hex.count) else {
            return nil
        }

        // 检查是否全是十六进制字符
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        guard hex.unicodeScalars.allSatisfy({ hexCharacterSet.contains($0) }) else {
            return nil
        }

        // 展开短格式 (#RGB -> #RRGGBB)
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }

        // 解析颜色值
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)

        let r, g, b, a: Double
        if hex.count == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else { // hex.count == 8
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        }

        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// 解析 RGB/RGBA 颜色格式
    static func parseRGBColor(_ string: String) -> Color? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 匹配 rgb(r, g, b) 或 rgba(r, g, b, a)
        let rgbPattern = "^rgba?\\s*\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)(?:\\s*,\\s*([0-9.]+))?\\s*\\)$"

        guard let regex = try? NSRegularExpression(pattern: rgbPattern, options: []) else {
            return nil
        }

        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard let match = regex.firstMatch(in: trimmed, range: range) else {
            return nil
        }

        // 提取各个颜色分量
        let nsString = trimmed as NSString
        guard let r = Int(nsString.substring(with: match.range(at: 1))),
              let g = Int(nsString.substring(with: match.range(at: 2))),
              let b = Int(nsString.substring(with: match.range(at: 3))),
              r >= 0, r <= 255,
              g >= 0, g <= 255,
              b >= 0, b <= 255 else {
            return nil
        }

        // 提取 alpha 值（如果有）
        let a: Double
        if match.range(at: 4).location != NSNotFound {
            let alphaString = nsString.substring(with: match.range(at: 4))
            a = Double(alphaString) ?? 1.0
        } else {
            a = 1.0
        }

        return Color(.sRGB, red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0, opacity: a)
    }
}

