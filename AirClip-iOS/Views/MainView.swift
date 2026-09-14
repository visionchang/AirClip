//
//  MainView.swift
//  AirClip-iOS
//
//  Created on 2025/12/18.
//

import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]

    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var showFavoritesOnly = false
    @State private var copiedItemID: PersistentIdentifier?
    @State private var isPasting = false
    @FocusState private var isSearchFocused: Bool

    var filteredItems: [ClipboardItem] {
        var result = items

        // 收藏过滤
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }

        // 搜索过滤
        if !searchText.isEmpty {
            result = result.filter { item in
                item.text?.localizedCaseInsensitiveContains(searchText) == true ||
                item.appName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                // 内容列表
                if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    itemsList
                }
            }
            .navigationTitle("AirClip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                // 将粘贴按钮移动到导航栏左上角（与设置按钮尺寸匹配且无背景）
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isSearchFocused {
                        Button {
                            Task {
                                isPasting = true
                                await pasteFromClipboard()
                                isPasting = false
                            }
                        } label: {
                            if isPasting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "doc.on.clipboard")
                            }
                        }
                        .disabled(isPasting)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView_iOS()
            }
        }
    }

    // MARK: - 底部工具栏

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // （粘贴按钮已移到导航栏左上角）

            // 搜索框
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))

                TextField("搜索", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .glassEffect(.regular.interactive())

            // 收藏过滤按钮（搜索聚焦时隐藏）
            if !isSearchFocused {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFavoritesOnly.toggle()
                    }
                } label: {
                    Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(showFavoritesOnly ? .red : .primary)
                        .frame(width: 50, height: 50)
                }
                .glassEffect(.regular.interactive())
                .transition(.scale.combined(with: .opacity))
            }

            // 取消按钮（搜索聚焦时显示）
            if isSearchFocused {
                Button {
                    searchText = ""
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 50, height: 50)
                }
                .glassEffect(.regular.interactive())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.25), value: isSearchFocused)
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if !searchText.isEmpty {
                // 搜索无结果
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("没找到「\(searchText)」的相关结果")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                // 无数据
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text(showFavoritesOnly ? "暂无收藏项目" : "暂无剪贴板记录")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("在其他设备复制内容后\n会自动同步到这里")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 列表

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredItems) { item in
                    ClipboardItemRow_iOS(
                        item: item,
                        isCopied: copiedItemID == item.persistentModelID,
                        onTap: { copyItem(item) },
                        onToggleFavorite: { toggleFavorite(item) },
                        onDelete: { deleteItem(item) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 操作方法

    private func copyItem(_ item: ClipboardItem) {
        iOSClipboardManager.shared.copyItem(item)

        withAnimation {
            copiedItemID = item.persistentModelID
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                if copiedItemID == item.persistentModelID {
                    copiedItemID = nil
                }
            }
        }
    }

    private func toggleFavorite(_ item: ClipboardItem) {
        item.isFavorite.toggle()
        item.modifiedAt = Date()
        try? modelContext.save()
    }

    private func deleteItem(_ item: ClipboardItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    /// 手动从剪贴板粘贴
    private func pasteFromClipboard() async {
        await iOSClipboardManager.shared.checkAndSaveClipboard(modelContext: modelContext)
    }
}

#Preview {
    MainView()
        .modelContainer(for: ClipboardItem.self, inMemory: true)
}
