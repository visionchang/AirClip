//
//  FileUtils.swift
//  CopyX
//
//  Created by 张佳航 on 2025/11/18.
//

import Foundation

// MARK: - 文件工具类

enum FileUtils {
    
    /// 根据文件扩展名返回对应的系统图标名称
    static func fileIcon(for fileName: String) -> String {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "pdf":
            return "doc.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "xls", "xlsx":
            return "tablecells.fill"
        case "ppt", "pptx":
            return "rectangle.stack.fill"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic":
            return "photo.fill"
        case "mp4", "mov", "avi", "mkv", "wmv":
            return "video.fill"
        case "mp3", "wav", "aac", "flac", "m4a":
            return "music.note"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox.fill"
        case "txt", "md", "rtf":
            return "doc.text.fill"
        case "html", "htm", "css", "js", "json", "xml":
            return "code"
        case "app", "dmg", "pkg":
            return "app.fill"
        default:
            return "doc.fill"
        }
    }
}

