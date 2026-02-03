//
//  ContentView.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//  Refactored by CodeY on 2/2/26.
//

import SwiftUI

extension Notification.Name {
    static let forceBackupUpdate = Notification.Name("forceBackupUpdate")
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: ScannerViewModel
    @State private var isDragTargeted: Bool = false
    @FocusState private var isPathFieldFocused: Bool

    init(initialPath: String? = nil) {
        _viewModel = StateObject(wrappedValue: ScannerViewModel(path: initialPath))
    }

    var body: some View {
        VStack(spacing: 0) {
            
            // Header 已移除，由 NSToolbar 接管
            
            // --- Body (完整保留) ---
            ZStack {
                Color.accentColor.opacity(isDragTargeted ? 0.1 : 0.0).ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.2), value: isDragTargeted)
                
                if !viewModel.results.isEmpty {
                    List(viewModel.results) { entry in ACERowView(entry: entry) }
                    .listStyle(.inset).opacity(isDragTargeted ? 0.4 : 1.0)
                } else if let error = viewModel.errorMessage {
                    VStack { Text(error).foregroundColor(.red).padding() }
                } else {
                    if !viewModel.isScanning {
                        VStack(spacing: 8) {
                            Text(isDragTargeted ? "松开即可分析" : "拖拽至此或点击上方“浏览”")
                                .font(.title3).foregroundColor(.secondary)
                        }
                    }
                }
                
                if viewModel.isScanning {
                    ProgressView("正在溯源...").padding().background(.regularMaterial).cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // --- Footer Path Bar (完整保留) ---
            VStack(spacing: 0) {
                Divider()
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    DrawerPathBar(path: $viewModel.path) {
                        viewModel.startScan()
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: 27)
            }
            .zIndex(2)
            
            // --- Status Bar (完整保留) ---
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    if !viewModel.results.isEmpty {
                        Text("\(viewModel.results.count) 项").font(.system(size: 11)).foregroundColor(.primary.opacity(0.8)).allowsHitTesting(false)
                    }
                    Spacer()
                }
                .frame(height: 27).background(Color(nsColor: .windowBackgroundColor))
                .overlay(DraggableWindowView())
            }
            .zIndex(2)
        }
        .frame(minWidth: 700, minHeight: 500)
        // [挂载配置]
        .background(WindowAccessor { window in
            guard let window = window else { return }
            ToolbarConfigurator.configure(window, with: viewModel)
        })
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            if !viewModel.path.isEmpty && viewModel.results.isEmpty { viewModel.startScan() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusPathField)) { _ in
            DispatchQueue.main.async { isPathFieldFocused = true }
        }
    }
    
    // [保留] 拖拽逻辑
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
        guard !fileProviders.isEmpty else { return false }

        Task {
            var validPaths: [String] = []
            for provider in fileProviders {
                if let url = try? await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) as? URL {
                    validPaths.append(url.path)
                } else if let data = try? await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    validPaths.append(url.path)
                }
            }
            
            await MainActor.run {
                guard !validPaths.isEmpty else { return }
                viewModel.path = validPaths[0]
                NotificationCenter.default.post(name: .forceBackupUpdate, object: nil)
                viewModel.startScan()
                if validPaths.count > 1 {
                    for i in 1..<validPaths.count { openWindow(id: "viewer", value: validPaths[i]) }
                }
            }
        }
        return true
    }
}
// ACERowView 代码保持不变，为节省篇幅省略

// ACERowView 保持不变...
// ACERowView 修改版
// ACERowView 颜色修正版：蓝色图标 + 粗体文字
struct ACERowView: View {
    let entry: ACEEntry
    
    // 图标名称逻辑：保持实心 (.fill)
    private var iconName: String {
        // 1. Everyone -> 三人实心
        if entry.name.caseInsensitiveCompare("everyone") == .orderedSame {
            return "person.3.fill"
        }
        // 2. 当前用户 -> 圆形头像
        if entry.name == NSUserName() {
            return "person.crop.circle"
        }
        // 3. 组 -> 双人实心
        if entry.isGroup {
            return "person.2.fill"
        }
        // 4. 普通用户 -> 单人实心
        return "person.fill"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            HStack(spacing: 6) {
                
                // 1. 图标区域
                Image(systemName: iconName)
                    // 保持 Regular (标准体)，避免变粗
                    .font(.system(size: 15, weight: .regular))
                    // [关键修改] 指定为蓝色，找回原本的感觉
                    .foregroundColor(.blue)
                
                // 2. 文字区域：保持 Headline (粗体)
                Text(entry.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // 权限类型标签
                Text(entry.type.uppercased())
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(entry.type == "Allow" ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .foregroundColor(entry.type == "Allow" ? .green : .red)
                    .cornerRadius(4)
            }
            
            // 下方详情保持不变
            if !entry.permissions.isEmpty {
                Text(entry.permissions.joined(separator: "  •  "))
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.7))
                    .lineLimit(2)
            }
            if !entry.flags.isEmpty {
                HStack {
                    Image(systemName: "arrow.turn.down.right")
                    Text(entry.flags.joined(separator: " | "))
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.blue)
            }
            HStack {
                if entry.isInherited {
                    HStack(spacing: 4) {
                        Image(systemName: entry.isSystemInterrupted ? "exclamationmark.shield.fill" : "link")
                            .foregroundColor(entry.isSystemInterrupted ? .red : (entry.isHeuristicMatch ? .orange : .secondary))
                        Text(entry.isHeuristicMatch ? "兼容继承自: \(entry.sourcePath)" : "继承自: \(entry.sourcePath)")
                            .foregroundColor(entry.isSystemInterrupted ? .red : (entry.isHeuristicMatch ? .orange : .secondary))
                        if entry.isHeuristicMatch {
                            Text("(权限位缩减)")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                        }
                    }
                } else {
                    Text("本地显式定义")
                }
                Spacer()
                Text("Mask: 0x\(String(entry.permissionMask, radix: 16).uppercased())")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}
#Preview {
    ContentView()
        .frame(minWidth: 700, minHeight: 500) // 模拟一个窗口大小
}
