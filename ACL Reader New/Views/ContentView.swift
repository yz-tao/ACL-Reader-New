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
            
            // --- 1. 顶部控制区域 (Header) ---
            VStack(spacing: 0) {
                // 1.1 标题栏
                ZStack {
                    Text("ACL Reader New")
                        .font(.headline)
                        .foregroundColor(.primary.opacity(0.8))
                        .offset(y: -2)
                        .allowsHitTesting(false)
                }
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                
                // 1.2 控制栏
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
                    .disabled(viewModel.isScanning)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 4)
            }
            .background(
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            )
            .ignoresSafeArea(.container, edges: .top)
            
            // --- 2. 下方主内容与拖拽区 ---
            ZStack {
                Color.accentColor
                    .opacity(isDragTargeted ? 0.1 : 0.0)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.2), value: isDragTargeted)
                
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
                
                if viewModel.isScanning {
                    ProgressView("正在溯源...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // --- 3. 底部 Finder 样式路径栏 (常驻) ---
            FinderPathBar(path: viewModel.path) { newPath in
                viewModel.path = newPath
                viewModel.startScan()
            }
            // 路径栏保持纯白背景 (内容色)
            .background(Color(nsColor: .textBackgroundColor))
            .zIndex(2)
            
            // --- 4. 底部状态栏 (常驻) ---
            VStack(spacing: 0) {
                Divider() // 分割线
                
                HStack {
                    Spacer()
                    // 只有有结果时才显示文字
                    if !viewModel.results.isEmpty {
                        Text("\(viewModel.results.count) 项")
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.8)) // 稍微加深一点颜色
                    }
                    Spacer()
                }
                .frame(height: 26) // 高度与路径栏一致
                .background(
                    // [修改] 使用标准窗口背景色 (不透明灰色)
                    Color(nsColor: .windowBackgroundColor)
                )
            }
            .zIndex(2)
            
        } // End of Main VStack
        .frame(minWidth: 700, minHeight: 500)
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            if !viewModel.path.isEmpty && viewModel.results.isEmpty {
                viewModel.startScan()
            }
        }
    }
    
    // --- 拖拽逻辑 ---
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

// ACERowView 保持不变
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
