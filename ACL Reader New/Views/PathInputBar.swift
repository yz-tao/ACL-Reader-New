//
//  PathInputBar.swift
//  ACL Reader New
//
//  Created by tyz on 1/29/26.
//

import SwiftUI

struct PathInputBar: View {
    // 直接绑定外部数据源
    @Binding var currentPath: String
    
    // 回调函数
    var onCommit: (String) -> Void
    var onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    // [新增] 用于“反悔”的备份
    // 因为是实时修改，如果用户按 ESC，我们需要知道原来的路径是什么才能改回去
    @State private var originalPath: String = ""
    
    var body: some View {
        HStack(spacing: 0) {
            // 1. 输入框
            // [核心修改] 直接绑定 $currentPath，实现双向实时同步
            TextField("前往文件夹", text: $currentPath)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .disableAutocorrection(true)
                .focused($isFocused)
                // 稳健性布局配置
                .padding(.leading, 7)  // 对齐图标
                .padding(.trailing, 5) // 光标防切
                .frame(maxHeight: .infinity)
                .onSubmit {
                    handleSubmit()
                }
            
            // 2. 清除/取消按钮
            Button(action: { handleCancel() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .frame(height: 27)
        .onAppear {
            // 1. 进场时备份原始路径 (为了支持 ESC 撤销)
            originalPath = currentPath
            
            // 2. 延迟聚焦
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
        // 监听 ESC 键
        .onExitCommand {
            handleCancel()
        }
    }
    
    // MARK: - 逻辑处理
    
    private func handleSubmit() {
        // 处理波浪号 ~
        // 虽然已经实时绑定了，但需要在提交瞬间把 ~ 展开成完整路径
        let expanded = (currentPath as NSString).expandingTildeInPath
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) {
            // 如果展开后路径变了（例如把 ~ 变成了 /Users/...），更新回去
            if currentPath != expanded {
                currentPath = expanded
            }
            // 确认提交，更新备份（这样下次取消就不会回滚了）
            originalPath = expanded
            onCommit(expanded)
        } else {
            // 路径无效，报错，保持当前输入状态让用户修改
            NSSound.beep()
        }
    }
    
    private func handleCancel() {
        // [关键] 恢复备份
        // 如果用户只是打了一半就想退出，把路径还原回去，避免残留脏数据
        currentPath = originalPath
        onCancel()
    }
}
