//
//  SettingsView_iOS.swift
//  AirClip-iOS
//
//  Created on 2025/12/18.
//

import SwiftUI
import CloudKit
import Combine

struct SettingsView_iOS: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // iCloud 同步
                SyncSection()

                // 关于
                AboutSection()
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 同步设置

struct SyncSection: View {
    @State private var iCloudAvailable = false
    @State private var accountStatus: CKAccountStatus = .couldNotDetermine
    @State private var syncMonitor = CloudKitSyncMonitor.shared

    // 复用同一个 CKContainer 实例，避免重复创建
    private let container = CKContainer(identifier: "iCloud.com.example.AirClip")

    // 定时检查 publisher（每10秒触发一次）
    private let checkTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        Section {
            // iCloud 状态
            HStack {
                Image(systemName: iCloudAvailable ? "checkmark.icloud.fill" : "xmark.icloud")
                    .foregroundColor(iCloudAvailable ? .green : .red)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(iCloudAvailable ? "iCloud 已连接" : "iCloud 未连接")
                        .font(.headline)
                    Text(accountStatusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !iCloudAvailable {
                    Button("检查") {
                        checkiCloudStatus()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // 同步状态（与 mac 端一致的展示）
            HStack {
                Text("同步状态")
                Spacer()
                if syncMonitor.isSyncing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                        Text("同步中...")
                    }
                    .foregroundColor(.accentColor)
                } else {
                    Label("空闲", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            HStack {
                Text("最后同步")
                Spacer()
                if let lastSync = syncMonitor.lastSyncTime {
                    Text(DateUtils.formatRelativeDate(lastSync))
                        .foregroundColor(.secondary)
                } else {
                    Text("尚未同步")
                        .foregroundColor(.secondary)
                }
            }

            if let error = syncMonitor.syncError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
        } header: {
            Text("iCloud 同步")
        } footer: {
            if !iCloudAvailable {
                Text("请确保已登录 iCloud 账户并启用 iCloud Drive")
            } else {
                Text("如要禁用同步，请在系统偏好设置中关闭 iCloud Drive 对 AirClip 的访问权限。")
            }
        }
        .onAppear {
            // 首次加载时检查 iCloud 状态
            checkiCloudStatus()
            // 刷新同步状态 UI
            syncMonitor.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange)) { _ in
            // 监听 iCloud 账户身份变化（登录/登出）
            print("📡 检测到 iCloud 账户变化，重新检查状态")
            checkiCloudStatus()
        }
        .onReceive(checkTimer) { _ in
            // 定期检查 iCloud 状态
            checkiCloudStatus()
        }
    }

    private var accountStatusDescription: String {
        switch accountStatus {
        case .available:
            return "账户可用"
        case .noAccount:
            return "未登录 iCloud 账户"
        case .restricted:
            return "iCloud 访问受限"
        case .couldNotDetermine:
            return "无法确定账户状态"
        case .temporarilyUnavailable:
            return "iCloud 暂时不可用"
        @unknown default:
            return "未知状态"
        }
    }

    private func checkiCloudStatus() {
        container.accountStatus { status, error in
            Task { @MainActor in
                accountStatus = status
                iCloudAvailable = (status == .available)

                if let error = error {
                    print("⚠️ iCloud 状态检查失败: \(error)")
                }
            }
        }
    }
}

// MARK: - 关于

struct AboutSection: View {
    var body: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("设备")
                Spacer()
                Text(UIDevice.current.name)
                    .foregroundColor(.secondary)
            }

            if let deviceID = UserDefaults.standard.string(forKey: PreferencesKeys.deviceID) {
                HStack {
                    Text("设备 ID")
                    Spacer()
                    Text(String(deviceID.prefix(8)) + "...")
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
            }
        } header: {
            Text("关于")
        }
    }
}

#Preview {
    SettingsView_iOS()
}
