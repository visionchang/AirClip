//
//  ItemDetailView.swift
//  AirClip
//
//  Created by GitHub Copilot on 2026/01/13.
//

import SwiftUI
import SwiftData

struct ItemDetailView: View {
    let itemID: PersistentIdentifier
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var item: ClipboardItem?
    @State private var text: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // 内容区域
            if let item = item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // 文本内容
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled) // 允许选择文本
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                VStack {
                    ProgressView()
                    Text("Loading...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(NSLocalizedString("copy_and_close", comment: "复制并关闭")) {
                    copyAndClose()
                }
                .disabled(item == nil)
            }
        }
        .task {
            loadItem()
        }
    }
    
    private func loadItem() {
        if let fetchedItem = modelContext.model(for: itemID) as? ClipboardItem {
            self.item = fetchedItem
            self.text = fetchedItem.text ?? ""
        }
    }
    
    private func copyAndClose() {
        if let text = item?.text {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        dismiss()
    }
}
