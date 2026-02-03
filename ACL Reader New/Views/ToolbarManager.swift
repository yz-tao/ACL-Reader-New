//
//  ToolbarManager.swift
//  ACL Reader New
//
//  Created by CodeY.
//  Adjusted: Icons smaller (12pt), Right margin tighter (10pt).
//

import SwiftUI
import AppKit

extension NSToolbarItem.Identifier {
    static let appTitle = NSToolbarItem.Identifier("com.aclreader.appTitle")
    static let pathInput = NSToolbarItem.Identifier("com.aclreader.pathInput")
    static let rightActions = NSToolbarItem.Identifier("com.aclreader.rightActions")
}

class ToolbarCoordinator: NSObject, NSToolbarDelegate {
    var viewModel: ScannerViewModel
    
    init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.appTitle, .pathInput, .rightActions, .flexibleSpace]
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace, .pathInput, .flexibleSpace, .rightActions]
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        
        switch itemIdentifier {
        case .pathInput:
            // --- 路径输入框 ---
            let inputView = PathInputView(text: Binding(get: { self.viewModel.path }, set: { self.viewModel.path = $0 }), onSubmit: {
                self.viewModel.startScan()
            })
            let hostingView = NSHostingView(rootView: inputView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 28)
            item.view = hostingView
            item.label = "路径"
            item.isNavigational = true
            
        case .rightActions:
            // --- 右侧按钮组 ---
            let actionsView = RightActionsView(viewModel: viewModel)
            let hostingView = NSHostingView(rootView: actionsView)
            
            // 宽度计算：
            // 按钮宽(约32)*2 + 间距(8) + 右边距(10) = ~82
            // 给 88 留足余量
            hostingView.frame = NSRect(x: 0, y: 0, width: 88, height: 34)
            
            item.view = hostingView
            item.label = "操作"

        default:
            return nil
        }
        
        return item
    }
}

// --- 路径输入框 (不变) ---
struct PathInputView: View {
    @Binding var text: String
    var onSubmit: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("输入路径...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { onSubmit() }
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

// --- 调整后的按钮组 ---
struct RightActionsView: View {
    @ObservedObject var viewModel: ScannerViewModel
    
    var body: some View {
        // [调整] 内部间距微调为 8，配合小图标更协调
        HStack(spacing: 8) {
            
            // 按钮 1：浏览
            Button(action: {
                viewModel.selectPath()
                NotificationCenter.default.post(name: .forceBackupUpdate, object: nil)
            }) {
                Image(systemName: "folder")
                    // [调整] 字号 12pt (变小)
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.large) // 保持外部点击区域足够大
            .help("浏览文件")
            
            // 按钮 2：分析
            Button(action: viewModel.startScan) {
                if viewModel.isScanning {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "play.fill")
                        // [调整] 字号 12pt (变小)
                        .font(.system(size: 12, weight: .regular))
                        .frame(width: 16, height: 16)
                }
            }
            .disabled(viewModel.isScanning)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("分析 ACL")
        }
        // [调整] 右侧空白减小为 10pt
        .padding(.trailing, 10)
    }
}
