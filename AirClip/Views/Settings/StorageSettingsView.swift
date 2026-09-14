import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

struct StorageSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query private var items: [ClipboardItem]
    @State private var showClearConfirmation = false
    @State private var showExportSuccess = false
    @State private var exportMessage = ""

    // MARK: - 映射函数（静态函数，可在初始化时使用）

    /// 将滑块值（1-90）映射到实际缓存条数（100-1000，步进50）
    private static func mapSliderToItemCount(_ sliderValue: Double) -> Int {
        if sliderValue >= 100.0 {
            return -1 // 无限制
        }
        // 滑块值 1-90 映射到 100-1000，步进50
        // 实际值范围：100, 150, 200, ..., 1000 (共19个值)
        // 线性映射到滑块值 1-90
        let clampedValue = max(1.0, min(90.0, sliderValue))
        // 计算在100-1000范围内的位置（0-1）
        let ratio = (clampedValue - 1.0) / 89.0
        // 映射到100-1000，然后取最近的步进值（50的倍数）
        let rawValue = 100.0 + ratio * 900.0
        // 取最近的50的倍数
        let steppedValue = round(rawValue / 50.0) * 50.0
        return Int(steppedValue)
    }

    /// 将实际缓存条数转换为滑块值（1-90）
    private static func mapItemCountToSlider(_ actualValue: Double) -> Double {
        if actualValue < 100 {
            return 1.0
        }
        if actualValue >= 1000 {
            return 90.0
        }
        // 取最近的50的倍数
        let steppedValue = round(actualValue / 50.0) * 50.0
        // 映射到滑块值 1-90
        let ratio = (steppedValue - 100.0) / 900.0
        return 1.0 + ratio * 89.0
    }

    /// 将滑块值（1-90）映射到实际缓存空间MB（100-1000，步进50）
    private static func mapSliderToTotalMB(_ sliderValue: Double) -> Int {
        if sliderValue >= 100.0 {
            return -1 // 无限制
        }
        // 滑块值 1-90 映射到 100-1000，步进50
        // 实际值范围：100, 150, 200, ..., 1000 (共19个值)
        let clampedValue = max(1.0, min(90.0, sliderValue))
        // 计算在100-1000范围内的位置（0-1）
        let ratio = (clampedValue - 1.0) / 89.0
        // 映射到100-1000，然后取最近的步进值（50的倍数）
        let rawValue = 100.0 + ratio * 900.0
        // 取最近的50的倍数
        let steppedValue = round(rawValue / 50.0) * 50.0
        return Int(steppedValue)
    }

    /// 将实际缓存空间MB转换为滑块值（1-90）
    private static func mapTotalMBToSlider(_ actualMB: Double) -> Double {
        if actualMB < 100 {
            return 1.0
        }
        if actualMB >= 1000 {
            return 90.0
        }
        // 取最近的50的倍数
        let steppedValue = round(actualMB / 50.0) * 50.0
        // 映射到滑块值 1-90
        let ratio = (steppedValue - 100.0) / 900.0
        return 1.0 + ratio * 89.0
    }

    /// 吸附最大缓存条数滑块到最近的步进值
    private static func snapItemCountSlider(_ value: Double) -> Double {
        if value >= 100.0 {
            return 100.0 // 无限制
        }
        if value < 1.0 {
            return 1.0
        }
        // 先将滑块值转换为实际值
        let actualValue = mapSliderToItemCount(value)
        if actualValue == -1 {
            return 100.0
        }
        // 将实际值转换回滑块值（这样会吸附到正确的步进值）
        return mapItemCountToSlider(Double(actualValue))
    }

    /// 吸附最大缓存空间滑块到最近的步进值
    private static func snapTotalMBSlider(_ value: Double) -> Double {
        if value >= 100.0 {
            return 100.0 // 无限制
        }
        if value < 1.0 {
            return 1.0
        }
        // 先将滑块值转换为实际值
        let actualMB = mapSliderToTotalMB(value)
        if actualMB == -1 {
            return 100.0
        }
        // 将实际值转换回滑块值（这样会吸附到正确的步进值）
        return mapTotalMBToSlider(Double(actualMB))
    }

    /// 将滑块值（1-90）映射到实际文件大小MB（1-50，步进1）
    private static func mapSliderToFileSizeMB(_ sliderValue: Double) -> Int {
        if sliderValue >= 100.0 {
            return -1 // 无限制
        }
        // 滑块值 1-90 映射到 1-50MB，步进1
        // 实际值范围：1, 2, 3, ..., 50 (共50个值)
        let clampedValue = max(1.0, min(90.0, sliderValue))
        // 计算在1-50范围内的位置（0-1）
        let ratio = (clampedValue - 1.0) / 89.0
        // 映射到1-50，然后取整（步进为1）
        let rawValue = 1.0 + ratio * 49.0
        return Int(round(rawValue))
    }

    /// 将实际文件大小MB转换为滑块值（1-90）
    private static func mapFileSizeMBToSlider(_ actualMB: Double) -> Double {
        if actualMB < 1 {
            return 1.0
        }
        if actualMB >= 50 {
            return 90.0
        }
        // 映射到滑块值 1-90
        let ratio = (actualMB - 1.0) / 49.0
        return 1.0 + ratio * 89.0
    }

    /// 吸附最大文件大小滑块到最近的步进值
    private static func snapFileSizeSlider(_ value: Double) -> Double {
        if value >= 100.0 {
            return 100.0 // 无限制
        }
        if value < 1.0 {
            return 1.0
        }
        // 先将滑块值转换为实际值
        let actualMB = mapSliderToFileSizeMB(value)
        if actualMB == -1 {
            return 100.0
        }
        // 将实际值转换回滑块值（这样会吸附到正确的步进值）
        return mapFileSizeMBToSlider(Double(actualMB))
    }

    /// 将滑块值（1-90）映射到实际字符数（1000-50000，步进1000）
    private static func mapSliderToTextCharacterCount(_ sliderValue: Double) -> Int {
        if sliderValue >= 100.0 {
            return -1 // 无限制
        }
        let clampedValue = max(1.0, min(90.0, sliderValue))
        let ratio = (clampedValue - 1.0) / 89.0
        let rawValue = 1000.0 + ratio * 49000.0
        let steppedValue = round(rawValue / 1000.0) * 1000.0
        return Int(steppedValue)
    }

    /// 将实际字符数转换为滑块值（1-90）
    private static func mapTextCharacterCountToSlider(_ actualCount: Double) -> Double {
        if actualCount < 1000 {
            return 1.0
        }
        if actualCount >= 50000 {
            return 90.0
        }
        let steppedValue = round(actualCount / 1000.0) * 1000.0
        let ratio = (steppedValue - 1000.0) / 49000.0
        return 1.0 + ratio * 89.0
    }

    /// 吸附最大缓存字符数滑块到最近的步进值
    private static func snapTextCharacterCountSlider(_ value: Double) -> Double {
        if value >= 100.0 {
            return 100.0 // 无限制
        }
        if value < 1.0 {
            return 1.0
        }
        let actualCount = mapSliderToTextCharacterCount(value)
        if actualCount == -1 {
            return 100.0
        }
        return mapTextCharacterCountToSlider(Double(actualCount))
    }

    // 滑块值：1-90 映射到实际值，100 表示无限制
    @State private var maxItemCountSlider: Double = {
        let v = UserDefaults.standard.integer(forKey: PreferencesKeys.maxItemCount)
        if v == -1 { return 100.0 } // 无限制
        let actualValue = v > 0 ? v : PreferencesDefaults.maxItemCount
        // 将实际值转换为滑块值（1-90）
        return StorageSettingsView.mapItemCountToSlider(Double(actualValue))
    }()

    // 滑块值：1-90 映射到实际值，100 表示无限制
    @State private var maxTotalMBSlider: Double = {
        let bytes = UserDefaults.standard.integer(forKey: PreferencesKeys.maxTotalBytes)
        if bytes == -1 { return 100.0 } // 无限制
        let actualMB = bytes > 0 ? Double(bytes) / 1024 / 1024 : Double(PreferencesDefaults.maxTotalBytes) / 1024 / 1024
        // 将实际值转换为滑块值（1-90）
        return StorageSettingsView.mapTotalMBToSlider(actualMB)
    }()

    // 滑块值：1-90 映射到实际值，100 表示无限制
    @State private var maxFileSizeSlider: Double = {
        let bytes = UserDefaults.standard.integer(forKey: PreferencesKeys.maxFileSizeBytes)
        if bytes == -1 { return 100.0 } // 无限制
        let actualMB = bytes > 0 ? Double(bytes) / 1024 / 1024 : Double(PreferencesDefaults.maxFileSizeBytes) / 1024 / 1024
        // 将实际值转换为滑块值（1-90）
        return StorageSettingsView.mapFileSizeMBToSlider(actualMB)
    }()

    // 滑块值：1-90 映射到实际值，100 表示无限制
    @State private var maxTextCharacterCountSlider: Double = {
        if UserDefaults.standard.object(forKey: PreferencesKeys.maxTextCharacterCount) == nil {
            return 100.0 // 默认无限制
        }
        let count = UserDefaults.standard.integer(forKey: PreferencesKeys.maxTextCharacterCount)
        if count == -1 { return 100.0 } // 无限制
        if count <= 0 { return 100.0 }
        return StorageSettingsView.mapTextCharacterCountToSlider(Double(count))
    }()

    @State private var retentionSliderValue: Double = {
        let v = UserDefaults.standard.double(forKey: PreferencesKeys.retentionSliderValue)
        if v == -1.0 { return -1.0 } // 永久
        if v <= 0 { return PreferencesDefaults.retentionSliderValue } // 默认永久
        // 确保最小值是 1
        return max(v, 1.0)
    }()

    // 数据迁移
    @StateObject private var migrationManager: DataMigrationManager = {
        // 获取 modelContainer（这里需要从 App 获取）
        guard let container = AirClipApp.sharedModelContainer else {
            fatalError("ModelContainer not available")
        }
        return DataMigrationManager(modelContainer: container)
    }()

    @State private var totalItemCount: Int = 0

    // 使用预存的 contentSize 字段进行统计（避免触发外部存储加载）

    private var totalBytes: Int {
        items.reduce(0) { $0 + $1.contentSize }
    }

    // 文本内容大小统计（使用 imageWidth 判断是否是图片，fileURLs 判断是否是文件）
    private var textBytes: Int {
        items.reduce(0) { total, item in
            // 文本项：没有图片尺寸信息，也没有文件URL
            if item.imageWidth == nil && (item.fileURLs == nil || item.fileURLs!.isEmpty) {
                return total + item.contentSize
            }
            return total
        }
    }

    // 图片内容大小统计（使用 imageWidth 判断，避免访问 imageData）
    private var imageBytes: Int {
        items.reduce(0) { total, item in
            // 图片项：有图片尺寸信息
            if item.imageWidth != nil {
                return total + item.contentSize
            }
            return total
        }
    }

    // 文件内容大小统计（使用 fileURLs 判断）
    private var fileBytes: Int {
        items.reduce(0) { total, item in
            // 文件项：有文件URL列表
            if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
                return total + item.contentSize
            }
            return total
        }
    }

    private var usageRatio: CGFloat {
        // 如果是无限制，不显示进度
        let maxMB = Self.mapSliderToTotalMB(maxTotalMBSlider)
        if maxMB == -1 { return 0 }

        let maxBytes = maxMB * 1024 * 1024
        guard maxBytes > 0 else { return 0 }
        return min(CGFloat(totalBytes) / CGFloat(maxBytes), 1.0)
    }

    private var usageColor: Color {
        if usageRatio > 0.9 { return .red }
        else if usageRatio > 0.7 { return .orange }
        else { return .accentColor }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("cached_items")
                    Spacer()
                    Text("\(items.count)")
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("used_space")
                        Spacer()
                        Text(formattedSize(bytes: totalBytes))
                            .foregroundColor(.secondary)
                    }

                    // 进度条
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(usageColor)
                                .frame(width: geometry.size.width * usageRatio, height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        let maxMB = Self.mapSliderToTotalMB(maxTotalMBSlider)
                        Text(maxMB == -1 ? "" : String(format: "%.1f%%", usageRatio * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(maxMB == -1 ? NSLocalizedString("unlimited", comment: "") : String(format: NSLocalizedString("total_mb", comment: ""), maxMB))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 分类统计
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "text.alignleft")
                            .foregroundColor(.blue)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text("text")
                            .font(.system(size: 13))
                        Spacer()
                        Text(formattedSize(bytes: textBytes))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "photo")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text("image")
                            .font(.system(size: 13))
                        Spacer()
                        Text(formattedSize(bytes: imageBytes))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "doc")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text("file")
                            .font(.system(size: 13))
                        Spacer()
                        Text(formattedSize(bytes: fileBytes))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            } header: {
                Text("usage")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    let actualItemCount = Self.mapSliderToItemCount(maxItemCountSlider)
                    Text(actualItemCount == -1 ? NSLocalizedString("max_items_unlimited", comment: "") : String(format: NSLocalizedString("max_items", comment: ""), actualItemCount))
                        .font(.system(size: 13))

                    VStack(spacing: 0) {
                        Slider(
                            value: $maxItemCountSlider,
                            in: 1 ... 100
                        ) { isEditing in
                            if !isEditing {
                                // 拖拽结束或点击时吸附到最近的锚点
                                maxItemCountSlider = Self.snapItemCountSlider(maxItemCountSlider)
                            }
                        }
                        .labelsHidden()
                        .tint(.accentColor)
                        .zIndex(2)
                        .onChange(of: maxItemCountSlider) { _, newValue in
                            let actualValue = Self.mapSliderToItemCount(newValue)
                            UserDefaults.standard.set(actualValue, forKey: PreferencesKeys.maxItemCount)
                        }

                        // 灰色锚点
                        GeometryReader { geometry in
                            let padding: CGFloat = 9 // 两端留出的距离
                            let dotWidth: CGFloat = 2
                            let availableWidth = geometry.size.width - padding * 2
                            
                            ZStack(alignment: .leading) {
                                // 100-1000，步进50，共19个锚点
                                ForEach(0..<19) { index in
                                    let actualValue = 100 + index * 50
                                    let sliderValue = Self.mapItemCountToSlider(Double(actualValue))
                                    Circle()
                                        .fill(Color.gray.opacity(0.4))
                                        .frame(width: dotWidth, height: dotWidth)
                                        .offset(x: padding + availableWidth * (sliderValue - 1.0) / 99.0 - dotWidth / 2)
                                }
                                
                                // 永久：100
                                Circle()
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: dotWidth, height: dotWidth)
                                    .offset(x: padding + availableWidth * (100.0 - 1.0) / 99.0 - dotWidth / 2)
                            }
                        }
                        .frame(height: 3)
                        .offset(y: -2)

                        // 底部刻度文字
                        GeometryReader { geometry in
                            let padding: CGFloat = 9 // 与锚点相同的padding
                            let availableWidth = geometry.size.width - padding * 2
                            
                            ZStack(alignment: .leading) {
                                // 100：位置1
                                Text("100")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (1.0 - 1.0) / 99.0 - 12)
                                
                                // 1000：位置90
                                Text("1000")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (90.0 - 1.0) / 99.0 - 15)
                                
                                // 永久：位置100
                                Text("♾️")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (100.0 - 1.0) / 99.0 - 6)
                            }
                        }
                        .frame(height: 13)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    let actualMB = Self.mapSliderToTotalMB(maxTotalMBSlider)
                    Text(actualMB == -1 ? NSLocalizedString("max_space_unlimited", comment: "") : String(format: NSLocalizedString("max_space", comment: ""), actualMB))
                        .font(.system(size: 13))

                    VStack(spacing: 0) {
                        Slider(
                            value: Binding(
                                get: {
                                    maxTotalMBSlider
                                },
                                set: { newValue in
                                    maxTotalMBSlider = Self.snapTotalMBSlider(newValue)
                                }
                            ),
                            in: 1 ... 100
                        )
                        .labelsHidden()
                        .tint(.accentColor)
                        .zIndex(2)
                        .onChange(of: maxTotalMBSlider) { _, newValue in
                            let actualValue = Self.mapSliderToTotalMB(newValue)
                            UserDefaults.standard.set(actualValue * 1024 * 1024, forKey: PreferencesKeys.maxTotalBytes)
                        }

                        // 灰色锚点
                        GeometryReader { geometry in
                            let padding: CGFloat = 9 // 两端留出的距离
                            let dotWidth: CGFloat = 2
                            let availableWidth = geometry.size.width - padding * 2
                            
                            ZStack(alignment: .leading) {
                                // 100-1000，步进50，共19个锚点
                                ForEach(0..<19) { index in
                                    let actualMB = 100 + index * 50
                                    let sliderValue = Self.mapTotalMBToSlider(Double(actualMB))
                                    Circle()
                                        .fill(Color.gray.opacity(0.4))
                                        .frame(width: dotWidth, height: dotWidth)
                                        .offset(x: padding + availableWidth * (sliderValue - 1.0) / 99.0 - dotWidth / 2)
                                }
                                
                                // 永久：100
                                Circle()
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: dotWidth, height: dotWidth)
                                    .offset(x: padding + availableWidth * (100.0 - 1.0) / 99.0 - dotWidth / 2)
                            }
                        }
                        .frame(height: 3)
                        .offset(y: -2)

                        // 底部刻度文字
                        GeometryReader { geometry in
                            let padding: CGFloat = 9 // 与锚点相同的padding
                            let availableWidth = geometry.size.width - padding * 2
                            
                            ZStack(alignment: .leading) {
                                // 100：位置1
                                Text("100")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (1.0 - 1.0) / 99.0 - 12)
                                
                                // 1000：位置90
                                Text("1000")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (90.0 - 1.0) / 99.0 - 15)
                                
                                // 永久：位置100
                                Text("♾️")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (100.0 - 1.0) / 99.0 - 6)
                            }
                        }
                        .frame(height: 13)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    let actualFileSizeMB = Self.mapSliderToFileSizeMB(maxFileSizeSlider)
                    Text(actualFileSizeMB == -1 ? NSLocalizedString("max_file_unlimited", comment: "") : String(format: NSLocalizedString("max_file", comment: ""), actualFileSizeMB))
                        .font(.system(size: 13))

                    VStack(spacing: 0) {
                        Slider(
                            value: Binding(
                                get: {
                                    maxFileSizeSlider
                                },
                                set: { newValue in
                                    maxFileSizeSlider = Self.snapFileSizeSlider(newValue)
                                }
                            ),
                            in: 1 ... 100
                        )
                        .labelsHidden()
                        .tint(.accentColor)
                        .zIndex(2)
                        .onChange(of: maxFileSizeSlider) { _, newValue in
                            let actualValue = Self.mapSliderToFileSizeMB(newValue)
                            if actualValue == -1 {
                                UserDefaults.standard.set(-1, forKey: PreferencesKeys.maxFileSizeBytes)
                            } else {
                                UserDefaults.standard.set(actualValue * 1024 * 1024, forKey: PreferencesKeys.maxFileSizeBytes)
                            }
                        }

                        // 灰色锚点
                        GeometryReader { geometry in
                            let padding: CGFloat = 9 // 两端留出的距离
                            let dotWidth: CGFloat = 2
                            let availableWidth = geometry.size.width - padding * 2
                            
                            ZStack(alignment: .leading) {
                                // 1-50，步进1，共50个锚点
                                ForEach(0..<50) { index in
                                    let actualMB = 1 + index
                                    let sliderValue = Self.mapFileSizeMBToSlider(Double(actualMB))
                                    Circle()
                                        .fill(Color.gray.opacity(0.4))
                                        .frame(width: dotWidth, height: dotWidth)
                                        .offset(x: padding + availableWidth * (sliderValue - 1.0) / 99.0 - dotWidth / 2)
                                }
                                
                                // 无限制：100
                                Circle()
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: dotWidth, height: dotWidth)
                                    .offset(x: padding + availableWidth * (100.0 - 1.0) / 99.0 - dotWidth / 2)
                            }
                        }
                        .frame(height: 3)
                        .offset(y: -2)

                        // 底部刻度文字
                        GeometryReader { geometry in
                            let padding: CGFloat = 9 // 与锚点相同的padding
                            let availableWidth = geometry.size.width - padding * 2
                            
                            ZStack(alignment: .leading) {
                                // 1：位置1
                                Text("1")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (1.0 - 1.0) / 99.0 - 4)
                                
                                // 50：位置90
                                Text("50")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (90.0 - 1.0) / 99.0 - 8)
                                
                                // 无限制：位置100
                                Text("♾️")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (100.0 - 1.0) / 99.0 - 6)
                            }
                        }
                        .frame(height: 13)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    let actualCharCount = Self.mapSliderToTextCharacterCount(maxTextCharacterCountSlider)
                    Text(actualCharCount == -1 ? NSLocalizedString("max_text_chars_unlimited", comment: "") : String(format: NSLocalizedString("max_text_chars", comment: ""), actualCharCount))
                        .font(.system(size: 13))

                    VStack(spacing: 0) {
                        Slider(
                            value: Binding(
                                get: {
                                    maxTextCharacterCountSlider
                                },
                                set: { newValue in
                                    maxTextCharacterCountSlider = Self.snapTextCharacterCountSlider(newValue)
                                }
                            ),
                            in: 1 ... 100
                        )
                        .labelsHidden()
                        .tint(.accentColor)
                        .zIndex(2)
                        .onChange(of: maxTextCharacterCountSlider) { _, newValue in
                            let actualValue = Self.mapSliderToTextCharacterCount(newValue)
                            UserDefaults.standard.set(actualValue, forKey: PreferencesKeys.maxTextCharacterCount)
                        }

                        GeometryReader { geometry in
                            let padding: CGFloat = 9
                            let dotWidth: CGFloat = 2
                            let availableWidth = geometry.size.width - padding * 2

                            ZStack(alignment: .leading) {
                                ForEach(0..<50) { index in
                                    let actualCount = 1000 + index * 1000
                                    let sliderValue = Self.mapTextCharacterCountToSlider(Double(actualCount))
                                    Circle()
                                        .fill(Color.gray.opacity(0.4))
                                        .frame(width: dotWidth, height: dotWidth)
                                        .offset(x: padding + availableWidth * (sliderValue - 1.0) / 99.0 - dotWidth / 2)
                                }

                                Circle()
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: dotWidth, height: dotWidth)
                                    .offset(x: padding + availableWidth * (100.0 - 1.0) / 99.0 - dotWidth / 2)
                            }
                        }
                        .frame(height: 3)
                        .offset(y: -2)

                        GeometryReader { geometry in
                            let padding: CGFloat = 9
                            let availableWidth = geometry.size.width - padding * 2

                            ZStack(alignment: .leading) {
                                Text("1K")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (1.0 - 1.0) / 99.0 - 6)

                                Text("50K")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (90.0 - 1.0) / 99.0 - 10)

                                Text("♾️")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .offset(x: padding + availableWidth * (100.0 - 1.0) / 99.0 - 6)
                            }
                        }
                        .frame(height: 13)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: NSLocalizedString("max_retention", comment: ""), mapSliderToRetention(retentionSliderValue).description))
                        .font(.system(size: 13))

                    SmartRetentionSlider(sliderValue: $retentionSliderValue)
                        .onChange(of: retentionSliderValue) { _, newValue in
                            let saveValue: Double
                            if newValue >= 100.0 {
                                saveValue = -1.0 // 永久
                            } else {
                                saveValue = max(newValue, 1.0) // 最小值是 1（1 天）
                            }
                            UserDefaults.standard.set(saveValue, forKey: PreferencesKeys.retentionSliderValue)
                        }
                }
            } header: {
                Text("cache_limits")
            }

            Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("data_management")
                            Text("data_management_desc")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("open") {
                            openWindow(id: "data-management")
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("clear_all_cache")
                            Text("clear_all_desc")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("clear") {
                            showClearConfirmation = true
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("export_data")
                            Text("export_data_desc")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("export") {
                            exportToJSON()
                        }
                        .buttonStyle(.bordered)
                        .disabled(items.isEmpty)
                    }
            } header: {
                Text("management")
            }

            // 数据迁移 Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("optimize_history")
                            Text("optimize_desc")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()

                            switch migrationManager.status {
                        case .idle:
                            Button("start_optimize") {
                                migrationManager.performFullMigration()
                            }
                            .buttonStyle(.bordered)
                            .disabled(totalItemCount == 0)

                        case let .running(progress, total):
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("\(progress)/\(total)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                        case let .completed(success, failed):
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(String(format: NSLocalizedString("migration_completed", comment: ""), success, failed))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                        case let .error(message):
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                            }
                        }
                    }

                    if totalItemCount > 0 && migrationManager.status == .idle {
                        Text(String(format: NSLocalizedString("migration_will_process", comment: ""), totalItemCount))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    // 迁移进度条
                    if case let .running(progress, total) = migrationManager.status {
                        ProgressView(value: Double(progress), total: Double(total))
                            .progressViewStyle(.linear)
                    }
                }
            } header: {
                Text("data_optimization")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("storage")
        .onAppear {
            // 获取总记录数量
            totalItemCount = migrationManager.getTotalItemCount()
        }
        .alert(NSLocalizedString("confirm_clear_title", comment: ""), isPresented: $showClearConfirmation) {
            Button(NSLocalizedString("cancel_button", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("clear", comment: ""), role: .destructive) {
                clearAllItems()
            }
        } message: {
            let nonFavoriteCount = items.filter { !$0.isFavorite }.count
            let favoriteCount = items.filter { $0.isFavorite }.count
            if favoriteCount > 0 {
                Text(String(format: NSLocalizedString("confirm_clear_non_favorites", comment: ""), nonFavoriteCount, favoriteCount))
            } else {
                Text(String(format: NSLocalizedString("confirm_clear_all", comment: ""), items.count))
            }
        }
        .alert(NSLocalizedString("export_completed", comment: ""), isPresented: $showExportSuccess) {
            Button(NSLocalizedString("ok", comment: ""), role: .cancel) {}
        } message: {
            Text(exportMessage)
        }
    }

    private func formattedSize(bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / 1024.0 / 1024.0)
        }
    }

    private func clearAllItems() {
        do {
            // 先统计收藏和未收藏的数量
            let favoriteCount = items.filter { $0.isFavorite }.count
            var deletedCount = 0

            for item in items {
                // 只删除未收藏的项目
                if !item.isFavorite {
                    modelContext.delete(item)
                    deletedCount += 1
                }
            }
            try modelContext.save()

            if favoriteCount > 0 {
                print("✅ 成功清空 \(deletedCount) 条缓存记录，保留了 \(favoriteCount) 条收藏记录")
            } else {
                print("✅ 成功清空 \(deletedCount) 条缓存记录")
            }
        } catch {
            print("❌ 清空缓存失败: \(error)")
            print("错误详情: \(error.localizedDescription)")

            // 如果保存失败，尝试回滚
            modelContext.rollback()
        }
    }

    private func exportToJSON() {
        struct ExportItem: Codable {
            let id: String
            let contentType: String // "text", "image", "file"
            let text: String?
            // 对于 image/file：此字段保存导出包内相对路径（images.zip 或 files.zip 内的路径）
            let assetPaths: [String]?
            let appName: String
            let appBundleIdentifier: String?
            let createdAt: Date
            let isFavorite: Bool
        }

        struct ExportData: Codable {
            let exportDate: Date
            let appVersion: String
            let itemCount: Int
            let items: [ExportItem]
        }

        // 快照 items（SwiftData 对象应在主线程读取）
        let snapshot = items
        guard !snapshot.isEmpty else {
            exportMessage = "没有可导出的记录"
            showExportSuccess = true
            return
        }

        // 显示保存面板（最终导出的 zip）
        let savePanel = NSSavePanel()
        savePanel.title = "导出剪贴板数据"
        savePanel.nameFieldStringValue = "AirClip_Export_\(formatDateForFilename(Date())).zip"
        savePanel.allowedContentTypes = [UTType.zip]
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }

            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                let tempBase = fileManager.temporaryDirectory.appendingPathComponent("AirClipExport_\(self.formatDateForFilename(Date()))")

                do {
                    // 清理旧目录并创建结构
                    if fileManager.fileExists(atPath: tempBase.path) {
                        try fileManager.removeItem(at: tempBase)
                    }
                    try fileManager.createDirectory(at: tempBase, withIntermediateDirectories: true)

                    let imagesDir = tempBase.appendingPathComponent("images")
                    let filesDir = tempBase.appendingPathComponent("files")
                    try fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
                    try fileManager.createDirectory(at: filesDir, withIntermediateDirectories: true)

                    var exportItems: [ExportItem] = []

                    // helper: detect image ext
                    func imageExtension(for data: Data) -> String {
                        let bytes = [UInt8](data.prefix(12))
                        if bytes.count >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
                            return "png"
                        } else if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8 {
                            return "jpg"
                        } else if bytes.count >= 12 {
                            // RIFF....WEBP
                            if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
                                bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
                                return "webp"
                            }
                        }
                        return "bin"
                    }

                    for item in snapshot {
                        let id = item.syncID ?? UUID().uuidString
                        var contentType = "text"
                        var assetPaths: [String]? = nil

                        if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
                            contentType = "file"
                            // 为该项创建子目录
                            let itemFilesDir = filesDir.appendingPathComponent(id)
                            try fileManager.createDirectory(at: itemFilesDir, withIntermediateDirectories: true)

                            var relativePaths: [String] = []
                            for urlString in fileURLs {
                                let srcURL = URL(fileURLWithPath: urlString)
                                if fileManager.fileExists(atPath: srcURL.path) {
                                    let filename = srcURL.lastPathComponent
                                    let dst = itemFilesDir.appendingPathComponent(filename)
                                    // 如果目标已存在，添加序号
                                    var finalDst = dst
                                    var k = 1
                                    while fileManager.fileExists(atPath: finalDst.path) {
                                        let newName = "\(dst.deletingPathExtension().lastPathComponent)_\(k).\(dst.pathExtension)"
                                        finalDst = itemFilesDir.appendingPathComponent(newName)
                                        k += 1
                                    }
                                    try fileManager.copyItem(at: srcURL, to: finalDst)
                                    let rel = "files/\(id)/\(finalDst.lastPathComponent)"
                                    relativePaths.append(rel)
                                }
                            }
                            if !relativePaths.isEmpty { assetPaths = relativePaths }
                        } else if let data = item.imageData {
                            contentType = "image"

                            // 尝试将任意二进制数据解码为 NSImage，然后优先导出为 PNG（保证图片格式），失败后尝试 JPEG，最后回退写原始数据并尽量推断扩展名
                            var finalExt = "png"
                            var finalData: Data? = nil

                            if let nsImage = NSImage(data: data), let tiff = nsImage.tiffRepresentation {
                                if let rep = NSBitmapImageRep(data: tiff) {
                                    if let pngData = rep.representation(using: .png, properties: [:]) {
                                        finalData = pngData
                                        finalExt = "png"
                                    } else if let jpgData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                                        finalData = jpgData
                                        finalExt = "jpg"
                                    }
                                }
                            }

                            // 如果无法通过 NSImage 转换，退回到根据二进制头判断扩展名并写入原始数据
                            if finalData == nil {
                                finalExt = imageExtension(for: data)
                                finalData = data
                            }

                            let imageName = "\(id).\(finalExt)"
                            let dst = imagesDir.appendingPathComponent(imageName)
                            try finalData?.write(to: dst)
                            assetPaths = ["images/\(imageName)"]
                        }

                        // 文本项保留全文
                        let textValue = (item.imageWidth == nil && (item.fileURLs == nil || item.fileURLs!.isEmpty)) ? item.text : nil

                        let exportItem = ExportItem(
                            id: id,
                            contentType: contentType,
                            text: textValue,
                            assetPaths: assetPaths,
                            appName: item.appName,
                            appBundleIdentifier: item.appBundleIdentifier,
                            createdAt: item.createdAt,
                            isFavorite: item.isFavorite
                        )

                        exportItems.append(exportItem)
                    }

                    // 生成 JSON
                    let exportData = ExportData(exportDate: Date(), appVersion: "1.0.0", itemCount: exportItems.count, items: exportItems)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    let jsonData = try encoder.encode(exportData)
                    let jsonURL = tempBase.appendingPathComponent("export.json")
                    try jsonData.write(to: jsonURL)

                    // 使用系统 zip 工具将整个 tempBase 文件夹打包为单个 zip
                    let finalTempZip = fileManager.temporaryDirectory.appendingPathComponent("AirClip_Export_\(self.formatDateForFilename(Date())).zip")
                    if fileManager.fileExists(atPath: finalTempZip.path) {
                        try fileManager.removeItem(at: finalTempZip)
                    }

                    // 使用 ZIPFoundation 生成 zip（纯 Swift，适合沙盒环境）
                    guard let archive = Archive(url: finalTempZip, accessMode: .create) else {
                        throw NSError(domain: "zip", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法创建压缩包"])
                    }

                    // 递归添加 tempBase 下的所有文件（保留相对路径）
                    let basePath = tempBase.path
                    let enumerator = fileManager.enumerator(at: tempBase, includingPropertiesForKeys: nil)
                    while let file = enumerator?.nextObject() as? URL {
                        let resourceValues = try file.resourceValues(forKeys: [.isDirectoryKey])
                        if resourceValues.isDirectory == true { continue }
                        // 计算相对路径
                        var rel = file.path
                        if rel.hasPrefix(basePath) {
                            rel = String(rel.dropFirst(basePath.count + 1))
                        }
                        try archive.addEntry(with: rel, fileURL: file, compressionMethod: .deflate)
                    }

                    // 将 zip 移动到用户选择的位置（如果存在则先删除）
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    try fileManager.moveItem(at: finalTempZip, to: destinationURL)

                    // 清理临时目录
                    try? fileManager.removeItem(at: tempBase)

                    DispatchQueue.main.async {
                        self.exportMessage = "成功导出 \(exportItems.count) 条记录，文件已保存到：\(destinationURL.path)"
                        self.showExportSuccess = true
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.exportMessage = "导出失败: \(error.localizedDescription)"
                        self.showExportSuccess = true
                    }
                }
            }
        }
    }

    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}

