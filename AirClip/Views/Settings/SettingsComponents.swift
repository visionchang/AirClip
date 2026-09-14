import SwiftUI

// MARK: - 辅助组件

struct KeyCapView: View {
    let key: String

    var body: some View {
        Text(key.trimmingCharacters(in: .whitespaces))
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - 时间保留设置组件

struct RetentionValue: CustomStringConvertible {
    enum Unit { case day(Int), week(Int), month(Int), year, forever }

    let unit: Unit

    var description: String {
        switch unit {
        case let .day(d): return "\(d) 天"
        case let .week(w): return "\(w) 周"
        case let .month(m): return "\(m) 个月"
        case .year: return "1 年"
        case .forever: return "永久"
        }
    }

    /// 转换为秒数（用于计算过期时间）
    var seconds: TimeInterval? {
        switch unit {
        case let .day(d): return TimeInterval(d * 24 * 60 * 60)
        case let .week(w): return TimeInterval(w * 7 * 24 * 60 * 60)
        case let .month(m): return TimeInterval(m * 30 * 24 * 60 * 60) // 简化：每月按30天计算
        case .year: return TimeInterval(365 * 24 * 60 * 60)
        case .forever: return nil
        }
    }
}

/// 将 sliderValue (1~100 或 -1 表示永久) 转换为 天/周/月/年/永久
func mapSliderToRetention(_ value: Double) -> RetentionValue {
    // 如果值小于 0 或 >= 100，表示永久保留
    if value < 0 || value >= 100 {
        return .init(unit: .forever)
    }

    // 使用 Double 值进行精确判断
    let doubleValue = value

    if doubleValue >= 1 && doubleValue <= 25 {
        // 1d ~ 6d
        // 1 对应 1 天，25 对应 6 天
        let day = Int(round(((doubleValue - 1.0) * 5.0 / 24.0) + 1.0))
        return .init(unit: .day(min(max(day, 1), 6)))

    } else if doubleValue >= 30 && doubleValue <= 50 {
        // 1w ~ 3w
        // 30 对应 1 周，40 对应 3 周
        let week = Int(round(((doubleValue - 30.0) * 3.0 / 20.0) + 1.0))
        return .init(unit: .week(min(max(week, 1), 3)))

    } else if doubleValue >= 60 && doubleValue <= 87.28 {
        // 1m ~ 11m
        // 60 对应 1 个月，72.28 对应 11 个月
        let month = Int(round(((doubleValue - 60.0) * 10.0 / 27.28) + 1.0))
        return .init(unit: .month(min(max(month, 1), 11)))

    } else if doubleValue >= 90 && doubleValue < 100 {
        // 1 年
        return .init(unit: .year)

    } else if doubleValue >= 100 {
        // 永久
        return .init(unit: .forever)

    } else {
        return .init(unit: .forever)
    }
}

struct SmartRetentionSlider: View {
    @Binding var sliderValue: Double // 1~100，-1 表示永久

    var body: some View {
        VStack(spacing: 0) {
            // 主滑条
            Slider(
                value: Binding(
                    get: {
                        if sliderValue < 0 { return 100.0 } // 永久
                        return max(sliderValue, 1.0) // 最小值是 1（1 天）
                    },
                    set: { newValue in
                        sliderValue = snapSlider(newValue)
                    }
                ),
                in: 1 ... 100
            )
            .labelsHidden()
            .tint(.accentColor)
            .zIndex(2)

            // 灰色锚点
            GeometryReader { geometry in
                let padding: CGFloat = 9 // 两端留出的距离
                let dotWidth: CGFloat = 2
                let availableWidth = geometry.size.width - padding * 2
                
                ZStack(alignment: .leading) {
                    // 天区间：1-30，7个吸附点
                    ForEach(0..<7) { index in
                        let position = 1.0 + Double(index) * 29.0 / 6.0
                        Circle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: dotWidth, height: dotWidth)
                            .offset(x: padding + availableWidth * (position - 1.0) / 99.0 - 1.5)
                    }
                    
                    // 周区间：30-60，4个吸附点
                    ForEach(0..<4) { index in
                        let position = 30.0 + Double(index) * 30.0 / 3.0
                        Circle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: dotWidth, height: dotWidth)
                            .offset(x: padding + availableWidth * (position - 1.0) / 99.0 - 1.5)
                    }
                    
                    // 月区间：60-90，12个吸附点
                    ForEach(0..<12) { index in
                        let position = 60.0 + Double(index) * 30.0 / 11.0
                        Circle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: dotWidth, height: dotWidth)
                            .offset(x: padding + availableWidth * (position - 1.0) / 99.0 - 1.5)
                    }
                    
                    // 年区间：90
                    Circle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: dotWidth, height: dotWidth)
                        .offset(x: padding + availableWidth * (90.0 - 1.0) / 99.0 - 1.5)
                    
                    // 永久：100
                    Circle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: dotWidth, height: dotWidth)
                        .offset(x: padding + availableWidth * (100.0 - 1.0) / 99.0 - 1.5)
                }
            }
            .frame(height: 3)
            .offset(y: -2)

            // 底部刻度文字
            GeometryReader { geometry in
                let padding: CGFloat = 9 // 与锚点相同的padding
                let availableWidth = geometry.size.width - padding * 2
                
                ZStack(alignment: .leading) {
                    // 天：位置1（第一个锚点）
                    Text("天")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .offset(x: padding + availableWidth * (1.0 - 1.0) / 99.0 - 6) // 减去文字宽度的一半来居中
                    
                    // 周：位置30（周区间第一个锚点）
                    Text("周")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .offset(x: padding + availableWidth * (30.0 - 1.0) / 99.0 - 6)
                    
                    // 月：位置60（月区间第一个锚点）
                    Text("月")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .offset(x: padding + availableWidth * (60.0 - 1.0) / 99.0 - 6)
                    
                    // 年：位置90
                    Text("年")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .offset(x: padding + availableWidth * (90.0 - 1.0) / 99.0 - 6)
                    
                    // 永久：位置100
                    Text("永久")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .offset(x: padding + availableWidth * (100.0 - 1.0) / 99.0 - 12) // "永久"是两个字，减去更多
                }
            }
            .frame(height: 20)
        }
    }
}

extension SmartRetentionSlider {

    /// 实现"吸附到最近步进"
    func snapSlider(_ value: Double) -> Double {
        if value >= 1 && value <= 30 {
            // 天区间：1-30，只有 7 个吸附点（对应 1-7 天）
            let day = ((value - 1.0) * 6.0 / 29.0) + 1.0
            let clampedDay = min(max(Int(round(day)), 1), 7)
            // 反向计算：value = ((day - 1) * 29 / 6) + 1
            let snapValue = Double((clampedDay - 1) * 29 / 6) + 1.0
            return min(max(snapValue, 1.0), 30.0)

        } else if value >= 30 && value <= 60 {
            // 周区间：30-60，只有 4 个吸附点（对应 1-4 周）
            let week = ((value - 30.0) * 3.0 / 30.0) + 1.0
            let clampedWeek = min(max(Int(round(week)), 1), 4)
            // 反向计算：value = ((week - 1) * 30 / 3) + 30
            let snapValue = Double(clampedWeek - 1) * 30.0 / 3.0 + 30.0
            return min(max(snapValue, 30.0), 60.0)

        } else if value >= 60 && value <= 90 {
            // 月区间：60-90，只有 12 个吸附点（对应 1-12 个月）
            let month = ((value - 60.0) * 11.0 / 30.0) + 1.0
            let clampedMonth = min(max(Int(round(month)), 1), 12)
            // 反向计算：value = ((month - 1) * 30 / 11) + 60
            let snapValue = Double(clampedMonth - 1) * 30.0 / 11.0 + 60.0
            return min(max(snapValue, 60.0), 90.0)

        } else if value >= 90 && value < 100 {
            // 年区间：90-99，吸附到 90
            return 90.0

        } else if value >= 100 {
            // 永久
            return 100.0

        } else {
            // 默认吸附到 1
            return 1.0
        }
    }
}

