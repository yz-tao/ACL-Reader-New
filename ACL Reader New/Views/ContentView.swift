//
//  ContentView.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//  Refactored by CodeX on 12/30/25.
//  Fixed by CodeY (Native Accessory Fix).
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
        ZStack {
            // --- 1. 内容主体 (实色背景) ---
            VStack(spacing: 0) {
                ZStack {
                    // 拖拽反馈
                    Color.accentColor.opacity(isDragTargeted ? 0.1 : 0.0).ignoresSafeArea()
                        .animation(.easeInOut(duration: 0.2), value: isDragTargeted)
                        .onTapGesture {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                    
                    // 内容列表
                    Group {
                        if !viewModel.results.isEmpty {
                            List(viewModel.results) { entry in ACERowView(entry: entry) }
                            .listStyle(.inset)
                            .opacity(isDragTargeted ? 0.4 : 1.0)
                            // [关键] 实色背景，遮挡毛玻璃，只让顶部透出来
                            .scrollContentBackground(.hidden)
                            .background(Color(nsColor: .windowBackgroundColor))
                        } else if let error = viewModel.errorMessage {
                            VStack { Text(error).foregroundColor(.red).padding() }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(nsColor: .windowBackgroundColor))
                        } else {
                            if !viewModel.isScanning {
                                VStack(spacing: 8) {
                                    Text(isDragTargeted ? "松开即可分析" : "拖拽至此或点击“浏览”开始分析")
                                        .font(.title3).foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(nsColor: .windowBackgroundColor))
                            }
                        }
                        
                        if viewModel.isScanning {
                            ProgressView("正在溯源...").padding().background(.regularMaterial).cornerRadius(8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor)) // 双重保险
                
                // --- Footer (路径栏) ---
                VStack(spacing: 0) {
                    Divider()
                    ZStack {
                        Color(nsColor: .textBackgroundColor)
                        // [无报错调用]
                        DrawerPathBar(path: $viewModel.path) {
                            viewModel.startScan()
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(height: 27)
                }
                .zIndex(2)
                
                // --- Status Bar ---
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
        }
        .frame(minWidth: 700, minHeight: 500)
        // --- 2. 原生工具栏：只放标题 ---
        // 这样红绿灯就会保持在标准高度，和标题对齐
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ACL Reader New")
                    .font(.headline)
                    .foregroundColor(.primary.opacity(0.8))
            }
        }
        // --- 3. 核心大招：注入 Accessory View ---
        // 使用修正后的 TitlebarAccessory，不报错
        .background(
            TitlebarAccessory(viewModel: viewModel)
        )
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

// --- 修正后的标题栏附件配置器 ---
struct TitlebarAccessory: NSViewRepresentable {
    @ObservedObject var viewModel: ScannerViewModel
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // 异步执行，确保 Window 已经生成
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            
            let accessoryIdentifier = "ACLInputAccessory"
            
            // [修复] 正确的去重检查逻辑：检查控制器的 title
            if window.titlebarAccessoryViewControllers.contains(where: { $0.title == accessoryIdentifier }) {
                return
            }
            
            // 1. 创建 SwiftUI 视图 (输入栏)
            let inputBarView = AccessoryInputBar(viewModel: viewModel)
            
            // 2. 包装进 HostingController
            let hostingController = NSHostingController(rootView: inputBarView)
            hostingController.view.frame.size.height = 44 // 设定高度 (标准附件高度)
            
            // 3. 创建 AccessoryController
            let accessoryController = NSTitlebarAccessoryViewController()
            accessoryController.layoutAttribute = .bottom // 挂在标题栏底部
            accessoryController.title = accessoryIdentifier // 设置 ID 以便去重
            
            // [关键修复] 正确地将 HostingController 嵌入 Accessory
            accessoryController.view = hostingController.view
            accessoryController.addChild(hostingController) // 保持生命周期
            
            // 4. 添加到窗口
            window.addTitlebarAccessoryViewController(accessoryController)
        }
    }
}

// --- 提取出的输入栏视图 (运行在标题栏附件中) ---
struct AccessoryInputBar: View {
    @ObservedObject var viewModel: ScannerViewModel
    
    var body: some View {
        ZStack {
            // 背景毛玻璃 (确保全屏不黑)
            VisualEffectBlur(material: .sidebar, blendingMode: .withinWindow)
                .ignoresSafeArea()
            
            HStack(spacing: 12) {
                TextField("目标路径", text: $viewModel.path)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 400)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        // 确保填满
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ACERowView 保持原样
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
