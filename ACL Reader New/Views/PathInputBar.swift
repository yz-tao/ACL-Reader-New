//
//  PathInputBar.swift
//  ACL Reader New
//
//  Created by tyz on 1/29/26.
//

import SwiftUI

struct PathInputBar: View {
    @Binding var currentPath: String
    
    // [删除] @Binding var backupTrigger: Bool (不需要了)
    
    var onCommit: (String) -> Void
    var onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    @State private var originalPath: String = ""
    
    var body: some View {
        HStack(spacing: 0) {
            TextField("前往文件夹", text: $currentPath)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .disableAutocorrection(true)
                .focused($isFocused)
                .padding(.leading, 7)
                .padding(.trailing, 5)
                .frame(maxHeight: .infinity)
                .onSubmit { handleSubmit() }
            
            Button(action: { handleCancel() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .frame(height: 27)
        .onAppear {
            originalPath = currentPath
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isFocused = true }
        }
        // [修改] 核心：直接监听名为 "forceBackupUpdate" 的全局通知
        // 只要收到这个通知，不管能不能看到，立刻更新备份
        .onReceive(NotificationCenter.default.publisher(for: .forceBackupUpdate)) { _ in
            originalPath = currentPath
        }
        .onExitCommand { handleCancel() }
    }
    
    private func handleSubmit() {
        let expanded = (currentPath as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) {
            if currentPath != expanded { currentPath = expanded }
            originalPath = expanded
            onCommit(expanded)
        } else {
            NSSound.beep()
        }
    }
    
    private func handleCancel() {
        currentPath = originalPath
        onCancel()
    }
}
