//
//  ContentView.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//  Refactored by CodeX on 12/30/25.
//  Fixed by CodeY (Layout & One-Piece Glass).
//

import SwiftUI
import AppKit

// [保持原样] 定义通知名称
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
            
            // --- 1. 自定义输入栏 (Row 2) ---
            // 将输入框从 Toolbar 移到这里，避免红绿灯垂直居中
            // 它是 Body 的一部分，但视觉上和顶部连成一片
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    TextField("目标路径", text: $viewModel.path)
                        .textFieldStyle(.roundedBorder)
                        .focused($isPathFieldFocused)
                        .overlay(alignment: .trailing) {
                            if !viewModel.path.isEmpty {
                                Button(action: { viewModel.path = "" }) {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                                }
                                .buttonStyle(.plain).padding(.trailing, 8)
                            }
                        }
                    
                    Button("浏览...", action: {
                        viewModel.selectPath()
                        NotificationCenter.default.post(name: .forceBackupUpdate, object: nil)
                    })
                    
                    Button(action: viewModel.startScan) {
                        if viewModel.isScanning { ProgressView().controlSize(.small) } else { Text("分析 ACL") }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(viewModel.isScanning)
                }
                .padding(.horizontal, 16).padding(.bottom, 12).padding(.top, 8)
            }
            // [关键] 这里的背景设为毛玻璃，并让它忽略安全区域向上延伸
            // 这样它会“垫”在 System Toolbar 下面，形成“一体化”的视觉效果
            .background(VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
            .zIndex(10) // 保证在最上层
            
            // --- 2. 内容层 (Body) ---
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
                            Text(isDragTargeted ? "松开即可分析" : "拖拽至此或点击“浏览”开始分析")
                                .font(.title3).foregroundColor(.secondary)
                        }
                    }
                }
                
                if viewModel.isScanning {
                    ProgressView("正在溯源...").padding().background(.regularMaterial).cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // --- 3. 底部路径栏 (Footer) ---
            VStack(spacing: 0) {
                Divider()
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    // [修复] 严格照抄你给的代码，不传 isEditing，杜绝报错
                    DrawerPathBar(path: $viewModel.path) {
                        viewModel.startScan()
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: 27)
            }
            .zIndex(2)
            
            // --- 4. 底部状态栏 (Status Bar) ---
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
        // --- 核心改动：Toolbar 只放标题 ---
        // 这样 System Toolbar 的高度保持标准，红绿灯就会乖乖待在最上面，和标题平齐
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ACL Reader New")
                    .font(.headline)
                    .foregroundColor(.primary.opacity(0.8))
            }
        }
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

// 你的 ACERowView 保持不变
struct ACERowView: View {
    let entry: ACEEntry
    
    private var iconName: String {
        if entry.name.caseInsensitiveCompare("everyone") == .orderedSame { return "person.3.fill" }
        if entry.name == NSUserName() { return "person.crop.circle" }
        if entry.isGroup { return "person.2.fill" }
        return "person.fill"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.blue)
                
                Text(entry.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(entry.type.uppercased())
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(entry.type == "Allow" ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .foregroundColor(entry.type == "Allow" ? .green : .red)
                    .cornerRadius(4)
            }
            
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
