//
//  ContentView.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//  Refactored by CodeX on 12/30/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ScannerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // --- 顶部交互区域 ---
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
            .background(.ultraThinMaterial)

            // --- 错误信息显示 ---
            if let error = viewModel.errorMessage {
                VStack {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Divider()
                }
            }

            // --- 结果列表区域 ---
            if viewModel.results.isEmpty && !viewModel.isScanning {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "shield.text.clearcut")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("输入路径或点击“浏览”开始分析")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(viewModel.results) { entry in
                    ACERowView(entry: entry)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// --- 单条 ACE 记录的子视图 ---
struct ACERowView: View {
    let entry: ACEEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：姓名与类型
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
            
            // 第二行：具体权限位
            if !entry.permissions.isEmpty {
                Text(entry.permissions.joined(separator: "  •  "))
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.7))
                    .lineLimit(2)
            }
            
            // 第三行：遗传/标志位
            if !entry.flags.isEmpty {
                HStack {
                    Image(systemName: "arrow.turn.down.right")
                    Text(entry.flags.joined(separator: " | "))
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.blue)
            }
            
            // 第四行：溯源信息与掩码
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
                // [修改] 显示 permissionMask (短名)
                Text("Mask: 0x\(String(entry.permissionMask, radix: 16).uppercased())")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}
