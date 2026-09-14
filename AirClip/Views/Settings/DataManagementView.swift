import SwiftUI
import SwiftData
import AppKit

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var allItems: [ClipboardItem]

    // 筛选和搜索状态
    @State private var selectedCategory: ContentCategory = .all
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var filteredItems: [ClipboardItem] = []

    // 选中的项目（用于批量删除）
    @State private var selectedItemIDs: Set<PersistentIdentifier> = []
    @State private var showDeleteConfirmation = false

    // 防抖 Timer
    @State private var searchDebounceTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            // 侧边栏：分类筛选
            List(ContentCategory.allCases, selection: $selectedCategory) { category in
                HStack {
                    Image(systemName: category.icon)
                        .foregroundColor(category.color)
                        .frame(width: 16)
                    Text(category.title)
                    Spacer()
                    Text("\(getItemCount(for: category))")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
            .navigationTitle("分类")
        } detail: {
            // 详情：数据列表
            VStack(spacing: 0) {
                // 搜索栏和工具栏
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("搜索内容或应用名称", text: $searchText)
                            .textFieldStyle(.plain)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)

                    Spacer()

                    // 批量删除按钮
                    if !selectedItemIDs.isEmpty {
                        Text("已选中 \(selectedItemIDs.count) 项")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Label("删除选中", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding()

                Divider()

                // 数据列表
                if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    List(selection: $selectedItemIDs) {
                        ForEach(filteredItems) { item in
                            DataItemRow(item: item)
                                .tag(item.persistentModelID)
                                .contextMenu {
                                    Button {
                                        deleteItem(item)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }

                                    Button {
                                        toggleFavorite(item)
                                    } label: {
                                        Label(
                                            item.isFavorite ? "取消收藏" : "收藏",
                                            systemImage: item.isFavorite ? "heart.slash" : "heart"
                                        )
                                    }
                                }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle(selectedCategory.title)
        }
        .frame(width: 900, height: 600)
        .onAppear {
            performFilter()
        }
        .onChange(of: selectedCategory) { _, _ in
            selectedItemIDs.removeAll()
            performFilter()
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                searchDebounceTask?.cancel()
                debouncedSearchText = newValue
                performFilter()
                return
            }

            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        debouncedSearchText = newValue
                        performFilter()
                    }
                }
            }
        }
        .onChange(of: allItems.count) { _, _ in
            performFilter()
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteSelectedItems()
            }
        } message: {
            Text("确定要删除 \(selectedItemIDs.count) 条记录吗？此操作无法撤销。")
        }
    }

    // MARK: - 空状态视图

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: getEmptyStateIcon())
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(getEmptyStateMessage())
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func getEmptyStateIcon() -> String {
        if !searchText.isEmpty {
            return "magnifyingglass"
        } else {
            return "tray"
        }
    }

    private func getEmptyStateMessage() -> String {
        if !searchText.isEmpty {
            return "未找到匹配的内容"
        } else {
            return "暂无数据"
        }
    }

    // MARK: - 数据筛选

    private func performFilter() {
        var items = allItems

        // 分类筛选
        switch selectedCategory {
        case .all:
            break
        case .text:
            items = items.filter { item in
                (item.fileURLs == nil || item.fileURLs!.isEmpty) && item.imageWidth == nil
            }
        case .image:
            items = items.filter { $0.imageWidth != nil }
        case .file:
            items = items.filter { item in
                if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
                    return true
                }
                return false
            }
        case .favorite:
            items = items.filter { $0.isFavorite }
        }

        // 搜索筛选
        if !debouncedSearchText.isEmpty {
            let keyword = debouncedSearchText.lowercased()
            items = items.filter { item in
                (item.text?.lowercased().contains(keyword) ?? false) ||
                item.appName.lowercased().contains(keyword) ||
                (item.fileNames?.joined(separator: " ").lowercased().contains(keyword) ?? false)
            }
        }

        filteredItems = items
    }

    private func getItemCount(for category: ContentCategory) -> Int {
        switch category {
        case .all:
            return allItems.count
        case .text:
            return allItems.filter { item in
                (item.fileURLs == nil || item.fileURLs!.isEmpty) && item.imageWidth == nil
            }.count
        case .image:
            return allItems.filter { $0.imageWidth != nil }.count
        case .file:
            return allItems.filter { item in
                if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
                    return true
                }
                return false
            }.count
        case .favorite:
            return allItems.filter { $0.isFavorite }.count
        }
    }

    // MARK: - 数据操作方法

    /// 切换收藏状态
    private func toggleFavorite(_ item: ClipboardItem) {
        item.isFavorite.toggle()
        item.modifiedAt = Date()

        do {
            try modelContext.save()
            print("✅ 收藏状态已更新")
        } catch {
            print("❌ 保存失败: \(error)")
            modelContext.rollback()
        }
    }

    // MARK: - 删除操作

    private func deleteItem(_ item: ClipboardItem) {
        // 删除本地记录
        do {
            modelContext.delete(item)
            try modelContext.save()
            print("✅ 删除成功")
        } catch {
            print("❌ 删除失败: \(error)")
            modelContext.rollback()
        }
    }

    private func deleteSelectedItems() {
        // 删除本地记录
        do {
            for itemID in selectedItemIDs {
                if let item = allItems.first(where: { $0.persistentModelID == itemID }) {
                    modelContext.delete(item)
                }
            }
            try modelContext.save()
            selectedItemIDs.removeAll()
            print("✅ 批量删除成功")
        } catch {
            print("❌ 批量删除失败: \(error)")
            modelContext.rollback()
        }
    }
}

// MARK: - 内容分类枚举

enum ContentCategory: String, CaseIterable, Identifiable {
    case all = "all"
    case text = "text"
    case image = "image"
    case file = "file"
    case favorite = "favorite"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        case .favorite: return "收藏"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc.fill"
        case .favorite: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .all: return .primary
        case .text: return .blue
        case .image: return .green
        case .file: return .orange
        case .favorite: return .red
        }
    }
}

// MARK: - 数据项行视图

struct DataItemRow: View {
    @Bindable var item: ClipboardItem
    
    // 缩略图状态
    @State private var thumbnailImage: NSImage?
    @State private var isImageLoaded = false
    
    // 预览状态
    @State private var showImagePreview = false
    @State private var fullImage: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: contentIcon)
                .font(.system(size: 24))
                .foregroundColor(contentColor)
                .frame(width: 32)

            // 内容预览
            VStack(alignment: .leading, spacing: 4) {
                // 如果是图片类型，显示缩略图
                if item.imageWidth != nil {
                    HStack(spacing: 8) {
                        if let nsImage = thumbnailImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipped()
                                .cornerRadius(4)
                                .onTapGesture {
                                    showImagePreview = true
                                    loadFullImage()
                                }
                                .help("点击预览大图")
                        } else {
                            // 占位符，等待图片加载
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.6)
                                )
                                .task {
                                    loadThumbnail()
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(contentPreview)
                                    .font(.system(size: 13))
                                    .lineLimit(2)

                                if item.isFavorite {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.red)
                                }
                            }
                            
                            HStack(spacing: 8) {
                                Text(item.appName)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                Text("•")
                                    .foregroundColor(.secondary)

                                Text(formattedDate)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                let desc = item.localizedDisplayDescription
                                if !desc.isEmpty {
                                    Text("•")
                                        .foregroundColor(.secondary)

                                    Text(desc)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    // 非图片类型：正常显示
                    HStack {
                        Text(contentPreview)
                            .font(.system(size: 13))
                            .lineLimit(2)

                        if item.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(item.appName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text(formattedDate)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        let desc = item.localizedDisplayDescription
                        if !desc.isEmpty {
                            Text("•")
                                .foregroundColor(.secondary)

                            Text(desc)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()
            
            // 复制按钮
            Button {
                copyItem()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .help("复制")
        }
        .padding(.vertical, 4)
        // 当 item 变化时重置图片状态（防止视图复用导致状态混乱）
        .onChange(of: item.persistentModelID) { _, _ in
            thumbnailImage = nil
            isImageLoaded = false
            fullImage = nil
        }
        .sheet(isPresented: $showImagePreview) {
            ImagePreviewView(image: fullImage, item: item)
        }
    }
    
    /// 复制项目到剪贴板
    private func copyItem() {
        // 应用内复制：将该条记录提到最新（保持原来源应用名称/图标不变）
        AirClipApp.clipboardMonitor?.markInternalCopy(itemID: item.persistentModelID)
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // 优先处理文件
        if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
            var nsURLObjects: [NSURL] = []
            for filePath in fileURLs {
                let url = URL(fileURLWithPath: filePath)
                if FileManager.default.fileExists(atPath: filePath) {
                    nsURLObjects.append(url as NSURL)
                }
            }
            if !nsURLObjects.isEmpty {
                pasteboard.writeObjects(nsURLObjects)
            }
        } else if let text = item.text, !text.isEmpty {
            pasteboard.setString(text, forType: .string)
        } else if let imageData = item.imageData,
           let image = NSImage(data: imageData) {
            pasteboard.writeObjects([image])
        }
    }
    
    /// 异步加载完整图片（用于预览）
    private func loadFullImage() {
        guard fullImage == nil else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = item.imageData, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    fullImage = image
                }
            }
        }
    }
    
    /// 异步加载缩略图（优先使用预存的缩略图，大幅减少内存占用）
    private func loadThumbnail() {
        guard !isImageLoaded else { return }
        isImageLoaded = true
        
        // 优先使用预存的缩略图数据（内存效率最高）
        if let thumbnailData = item.thumbnailData {
            DispatchQueue.global(qos: .userInitiated).async {
                if let thumbnail = NSImage(data: thumbnailData) {
                    DispatchQueue.main.async {
                        thumbnailImage = thumbnail
                    }
                }
            }
            return
        }
        
        // 兼容旧数据：如果没有预存缩略图，使用 imageData 生成
        guard let data = item.imageData else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = NSImage(data: data) {
                // 生成小尺寸缩略图
                let maxSize: CGFloat = 32
                let size = image.size
                let aspectRatio = size.width / size.height
                let newSize: NSSize
                
                if size.width > size.height {
                    newSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
                } else {
                    newSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
                }
                
                let thumbnail = NSImage(size: newSize)
                thumbnail.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1.0)
                thumbnail.unlockFocus()
                
                DispatchQueue.main.async {
                    thumbnailImage = thumbnail
                }
            }
        }
    }

    private var contentIcon: String {
        if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
            return fileURLs.count == 1 ? "doc.fill" : "doc.on.doc.fill"
        }

        if item.imageWidth != nil {
            return "photo"
        }

        return "text.alignleft"
    }

    private var contentColor: Color {
        if item.fileURLs != nil && !item.fileURLs!.isEmpty {
            return .orange
        }

        if item.imageWidth != nil {
            return .green
        }

        return .blue
    }

    private var contentPreview: String {
        if let fileNames = item.fileNames, !fileNames.isEmpty {
            return fileNames.joined(separator: ", ")
        }

        if item.imageWidth != nil, let width = item.imageWidth, let height = item.imageHeight {
            return "图片 (\(width) × \(height) 像素)"
        }

        if let text = item.text, !text.isEmpty {
            let cleanText = text.replacingOccurrences(of: "\n", with: " ")
            // 限制预览长度，避免超长文本导致卡顿
            return cleanText.count > 500 ? String(cleanText.prefix(500)) + "..." : cleanText
        }

        return "未知内容"
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
    }
}

// MARK: - 图片预览视图

struct ImagePreviewView: View {
    let image: NSImage?
    let item: ClipboardItem
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.9)
                        .ignoresSafeArea()
                    
                    if let nsImage = image {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        VStack {
                            ProgressView()
                            Text("加载中...")
                                .foregroundColor(.white)
                                .padding(.top, 8)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    if let width = item.imageWidth, let height = item.imageHeight {
                        Text("\(width) × \(height) 像素")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
