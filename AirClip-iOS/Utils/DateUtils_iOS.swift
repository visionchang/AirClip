//
//  DateUtils_iOS.swift
//  AirClip-iOS
//
//  Lightweight DateUtils for iOS target
//

import Foundation

enum DateUtils {
    /// 格式化日期：显示相对时间
    static func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        // 确保是过去的时间
        guard interval > 0 else {
            return NSLocalizedString("just_now", comment: "Just now")
        }

        let calendar = Calendar.current
        let seconds = Int(interval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        let weeks = days / 7
        let months = days / 30

        // 1分钟以内
        if seconds < 60 {
            return NSLocalizedString("just_now", comment: "Just now")
        }

        // 1小时以内
        if minutes < 60 {
            return String(format: NSLocalizedString("minutes_ago", comment: "%d minutes ago"), minutes)
        }

        // 判断是否在同一天（自然天）
        if calendar.isDate(date, inSameDayAs: now) {
            return String(format: NSLocalizedString("hours_ago", comment: "%d hours ago"), hours)
        }

        // 判断是否是昨天（自然天）
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return NSLocalizedString("yesterday", comment: "Yesterday")
        }

        // 判断是否是前天（自然天）
        if let dayBeforeYesterday = calendar.date(byAdding: .day, value: -2, to: now),
           calendar.isDate(date, inSameDayAs: dayBeforeYesterday) {
            return NSLocalizedString("day_before_yesterday", comment: "The day before yesterday")
        }

        // 1周以内
        if days < 7 {
            return String(format: NSLocalizedString("days_ago", comment: "%d days ago"), days)
        }

        // 1个月以内
        if days < 30 {
            return String(format: NSLocalizedString("weeks_ago", comment: "%d weeks ago"), weeks)
        }

        // 1年以内
        if months < 12 {
            return String(format: NSLocalizedString("months_ago", comment: "%d months ago"), months)
        }

        // 超过1年
        let years = months / 12
        return String(format: NSLocalizedString("years_ago", comment: "%d years ago"), years)
    }
}
