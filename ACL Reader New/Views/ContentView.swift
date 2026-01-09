//
//  ContentView.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//  Refactored by CodeX on 12/30/25.
//

import SwiftUI

struct ContentView: View {
    // 引入环境动作，用于打开新窗口
    @Environment(\.openWindow) private var openWindow
    
    @StateObject private var viewModel: ScannerViewModel
    
    // 拖拽悬停状态
    @State private var isDragTargeted: Bool = false

    // 自定义初始化，支持传入初始路径
    init(initialPath: String? = nil) {
        _viewModel = StateObject(wrappedValue: ScannerViewModel(path: initialPath))
    }

    var body: some View {
        VStack(spacing: 0) {
            // --- 顶部控制栏 ---
            HStack(spacing: 12) {
                TextField("目标路径", text: $viewModel.path)
                    .textFieldStyle(.roundedBorder)
                    .overlay(alignment: .trailing) {
                        if !viewModel.path.isEmpty {
                            Button(action: { viewModel.path = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                        }
                    }
                
                Button("浏览...", action: viewModel.selectPath)
                
                Button(action: viewModel.startScan) {
                    if viewModel.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("分析 ACL")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.isScanning || viewModel.path.isEmpty)
            }
            .padding()
            // 使用磨砂背景，去掉底部分割线，与下方自然融合
            .background(.ultraThinMaterial)
            .zIndex(1) // 确保控制栏在图层最上方

            // --- 下方主内容与拖拽区 ---
            ZStack {
                // 1. 背景层：负责显示拖拽的高亮反馈
                Color.accentColor
                    .opacity(isDragTargeted ? 0.1 : 0.0) // 悬停时显示极淡的主题色
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.2), value: isDragTargeted)
                
                // 2. 内容层
                if !viewModel.results.isEmpty {
                    // 有结果时显示列表
                    List(viewModel.results) { entry in
                        ACERowView(entry: entry)
                    }
                    .listStyle(.inset)
                    // 即使显示列表，也可以再次拖入覆盖
                    .opacity(isDragTargeted ? 0.4 : 1.0) // 悬停时让列表变淡，突出“即将替换”的感觉
                } else if let error = viewModel.errorMessage {
                    // 显示错误信息
                    VStack {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                } else {
                    // 空状态 (Idle State)
                    // 只有在没结果、没错误、没在扫描时显示
                    if !viewModel.isScanning {
                        VStack(spacing: 16) {
                            Text(isDragTargeted ? "松开即可分析" : "拖拽至此或点击“浏览”开始分析")
                                .font(.title3)
                                .fontWeight(isDragTargeted ? .bold : .regular)
                                .foregroundColor(.secondary)
                                // 添加轻微的缩放动画
                                .scaleEffect(isDragTargeted ? 1.05 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragTargeted)
                        }
                    }
                }
                
                // 3. 扫描中的 Loading (居中覆盖)
                if viewModel.isScanning {
                    ProgressView("正在溯源...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(8)
                }
            }
            // 将整个下半部分设为拖拽接收区
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                handleDrop(providers: providers)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        // 视图出现时，如果有初始路径（通过新窗口打开），自动开始扫描
        .onAppear {
            if !viewModel.path.isEmpty && viewModel.results.isEmpty {
                viewModel.startScan()
            }
        }
    }
    
    // --- 拖拽处理逻辑 ---
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // 筛选出文件类型的提供者
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
        guard !fileProviders.isEmpty else { return false }

        Task {
            var validPaths: [String] = []
            
            for provider in fileProviders {
                // 尝试加载 URL
                if let url = try? await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) as? URL {
                    validPaths.append(url.path)
                }
                // 某些情况下系统可能返回 Data 形式的 URL
                else if let data = try? await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) as? Data,
                        let url = URL(dataRepresentation: data, relativeTo: nil) {
                    validPaths.append(url.path)
                }
            }
            
            // 回到主线程更新 UI
            await MainActor.run {
                guard !validPaths.isEmpty else { return }
                
                // 1. 第一个文件：在当前窗口处理
                viewModel.path = validPaths[0]
                viewModel.startScan()
                
                // 2. 后续文件：打开新窗口
                if validPaths.count > 1 {
                    for i in 1..<validPaths.count {
                        openWindow(id: "viewer", value: validPaths[i])
                    }
                }
            }
        }
        return true
    }
}

// --- 保持原有的 ACERowView 不变 ---
struct ACERowView: View {
    let entry: ACEEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(entry.name, systemImage: entry.isGroup ? "person.2.fill" : "person.fill")
                    .font(.system(.headline, design: .rounded))
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
