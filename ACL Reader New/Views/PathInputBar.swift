//
//  PathInputBar.swift
//  ACL Reader New
//
//  Created by tyz on 1/29/26.
//

import SwiftUI

struct PathInputBar: View {
    // 外部传入的数据
    @Binding var currentPath: String
    
    // 回调函数
    var onCommit: (String) -> Void
    var onCancel: () -> Void
    
    // 内部状态
    @State private var editingText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // 1. 输入框
            TextField("前往文件夹", text: $editingText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .disableAutocorrection(true)
                .focused($isFocused)
                // 【核心稳健性配置】
                // 左侧 7px：对齐底层面包屑图标，兼顾左侧光标防切
                .padding(.leading, 7)
                // 右侧 5px：给光标留出物理“停车位”，防止长路径被切
                .padding(.trailing, 5)
                // 垂直撑满：防止光标高度被压缩
                .frame(maxHeight: .infinity)
                .onSubmit {
                    handleSubmit()
                }
            
            // 2. 清除/取消按钮
            Button(action: { onCancel() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6) // 按钮右边距
        }
        // 固定容器高度，确保与面包屑一致
        .frame(height: 27)
        // 初始化逻辑
        .onAppear {
            editingText = currentPath
            // 稍微延迟聚焦，确保视图渲染完毕
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
        // 监听 ESC 键
        .onExitCommand {
            onCancel()
        }
    }
    
    // MARK: - 逻辑处理
    
    private func handleSubmit() {
        // 处理波浪号 ~
        let expanded = (editingText as NSString).expandingTildeInPath
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) {
            // 路径有效，通过回调传出
            onCommit(expanded)
        } else {
            // 路径无效，报错保持编辑
            NSSound.beep()
        }
    }
}
