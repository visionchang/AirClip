//
//  URLUtils.swift
//  CopyX
//
//  Created by 张佳航 on 2025/11/18.
//

import Foundation

// MARK: - URL 工具类

enum URLUtils {
    
    /// 检测字符串是否是 URL
    static func isURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // 检查是否包含换行（多行文本不算链接）
        if trimmed.contains("\n") {
            return false
        }

        // 使用正则表达式检测 URL 格式
        let urlPattern = "^(https?://|www\\.).+"
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            if regex.firstMatch(in: trimmed, range: range) != nil {
                return true
            }
        }

        // 使用 URL 类型检测
        if let url = URL(string: trimmed),
           let scheme = url.scheme,
           ["http", "https", "ftp", "ftps"].contains(scheme.lowercased()) {
            return true
        }

        return false
    }
}

