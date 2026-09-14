//
//  SyncSettingsView.swift
//  AirClip
//
//  Created by Claude on 2025/12/17.
//

import SwiftUI
import CloudKit

struct SyncSettingsView: View {
    @State private var iCloudAvailable = false
    @State private var accountStatus: CKAccountStatus = .couldNotDetermine
    @State private var syncMonitor = CloudKitSyncMonitor.shared

    // 复用同一个 CKContainer 实例，避免重复创建
    private let container = CKContainer(identifier: "iCloud.com.example.AirClip")

    // 通过通知实时监听 iCloud / CloudKit 账户变化（替代定期轮询）

    var body: some View {
        Form {
            // iCloud 状态
            Section {
                HStack {
                    Image(systemName: iCloudAvailable ? "checkmark.icloud.fill" : "xmark.icloud")
                        .foregroundColor(iCloudAvailable ? .green : .red)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(iCloudAvailable ? NSLocalizedString("icloud_connected", comment: "") : NSLocalizedString("icloud_not_connected", comment: ""))
                            .font(.headline)
                        Text(accountStatusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !iCloudAvailable {
                        Button("check") {
                            checkiCloudStatus()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                    Text("icloud_sync")
            } footer: {
                if !iCloudAvailable {
                    Text("icloud_sync_instruction")
                } else {
                    Text("icloud_sync_disable")
                }
            }

            // 同步状态
            if iCloudAvailable {
                Section {
                    HStack {
                        Text("sync_status")
                        Spacer()
                        if syncMonitor.isSyncing {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                                Text("syncing")
                            }
                            .foregroundColor(.accentColor)
                        } else {
                            Label("idle", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }

                    if let lastSync = syncMonitor.lastSyncTime {
                        HStack {
                            Text("last_sync")
                            Spacer()
                            Text(DateUtils.formatRelativeDate(lastSync))
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
                    Text("status")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // 首次加载时检查一次状态
            checkiCloudStatus()
            // 刷新同步状态 UI
            syncMonitor.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange)) { _ in
            // 监听 iCloud 账户身份变化（登录/登出）
            print("📡 检测到 iCloud 账户变化，重新检查状态")
            checkiCloudStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.CKAccountChanged)) { _ in
            // 监听 CloudKit 账户状态变化（例如登录/登出或权限变化）
            print("📡 检测到 CloudKit 账户变化，重新检查状态")
            checkiCloudStatus()
        }
    }

    // MARK: - 辅助方法

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

    private var accountStatusDescription: String {
        switch accountStatus {
        case .available:
            return NSLocalizedString("account_available", comment: "")
        case .noAccount:
            return NSLocalizedString("not_signed_in", comment: "")
        case .restricted:
            return NSLocalizedString("access_restricted", comment: "")
        case .couldNotDetermine:
            return NSLocalizedString("unknown_account_status", comment: "")
        case .temporarilyUnavailable:
            return NSLocalizedString("temporarily_unavailable", comment: "")
        @unknown default:
            return NSLocalizedString("unknown_status", comment: "")
        }
    }
}

#Preview {
    SyncSettingsView()
        .frame(width: 400, height: 500)
}
