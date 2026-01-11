//
//  ContentView.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//  Refactored by CodeX on 12/30/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: ScannerViewModel
    @State private var isDragTargeted: Bool = false

    init(initialPath: String? = nil) {
        _viewModel = StateObject(wrappedValue: ScannerViewModel(path: initialPath))
    }

    var body: some View {
        VStack(spacing: 0) {
            
            // --- 顶部控制区域 (Header) ---
            VStack(spacing: 0) {
                
                // 1. 标题栏区域
                ZStack {
                    Text("ACL Reader New")
                        .font(.headline)
                        .foregroundColor(.primary.opacity(0.8))
                        // [修正1] 向上微调 2pt，视觉上与红绿灯对齐
                        .offset(y: -2)
                        // 禁止文字捕获鼠标，确保点击标题也能拖拽窗口
                        .allowsHitTesting(false)
                }
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                
                // 2. 控制栏
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
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 4) // 稍微收紧一点间距
            }
            .background(
                // 头部背景，支持拖拽
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            )
            // 让 Header 顶到窗口最上沿 (Y=0)
            .ignoresSafeArea(.container, edges: .top)
            
            // [修正2] 删除了这里的 Divider() 分割线
            
            // --- 下方主内容与拖拽区 ---
            ZStack {
                // 1. 背景层：高亮反馈
                Color.accentColor
                    .opacity(isDragTargeted ? 0.1 : 0.0)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.2), value: isDragTargeted)
                
                // 2. 内容层
                if !viewModel.results.isEmpty {
                    List(viewModel.results) { entry in
                        ACERowView(entry: entry)
                    }
                    .listStyle(.inset)
                    .opacity(isDragTargeted ? 0.4 : 1.0)
                } else if let error = viewModel.errorMessage {
                    VStack {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                } else {
                    // 空状态
                    if !viewModel.isScanning {
                        VStack(spacing: 8) {
                            Text(isDragTargeted ? "松开即可分析" : "拖拽至此或点击“浏览”开始分析")
                                .font(.title3)
                                .fontWeight(isDragTargeted ? .bold : .regular)
                                .foregroundColor(.secondary)
                                .scaleEffect(isDragTargeted ? 1.05 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragTargeted)
                        }
                    }
                }
                
                // 3. Loading
                if viewModel.isScanning {
                    ProgressView("正在溯源...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                handleDrop(providers: providers)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            if !viewModel.path.isEmpty && viewModel.results.isEmpty {
                viewModel.startScan()
            }
        }
    }
    
    // --- 拖拽处理逻辑 ---
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
                viewModel.startScan()
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

// 保持 ACERowView 不变
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

#Preview {
    ContentView()
        .frame(minWidth: 700, minHeight: 500) // 模拟一个窗口大小
}
