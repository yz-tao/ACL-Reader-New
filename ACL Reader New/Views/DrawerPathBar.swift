//
//  DrawerPathBar.swift
//  ACL Reader New
//
//  Created by tyz on 1/27/26.
//

import SwiftUI

struct DrawerPathBar: View {
    @Binding var path: String
    let onNavigate: () -> Void
    
    // 状态
    @State private var isEditing: Bool = false
    @State private var tempText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                
                // --- 层级 1 (最底层): 原生面包屑 ---
                FinderPathBar(path: path) { newPath in
                    path = newPath
                    onNavigate()
                }
                // 【核心修复】强行撑满宽度，防止消失
                .frame(width: geo.size.width)
                // 点击触发
                .contentShape(Rectangle())
                .onTapGesture {
                    startEditing()
                }
                
                // --- 层级 2 (中间层): 遮盖幕布 ---
                // 既然原生控件不能 mask，我们就用一块背景色的板子盖住它
                // 颜色必须和底色一致 (ContentView 里用的是 textBackgroundColor)
                Color(nsColor: .textBackgroundColor)
                    .frame(width: isEditing ? geo.size.width : 0) // 宽度动画
                    .frame(maxWidth: .infinity, alignment: .trailing) // 靠右对齐，从而实现从右向左生长
                
                // --- 层级 3 (最顶层): 输入框 ---
                if isEditing {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("前往文件夹...", text: $tempText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .disableAutocorrection(true)
                            .focused($isFocused)
                            .onSubmit {
                                commitPath()
                            }
                        
                        Button(action: { cancelEdit() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    // 输入框淡入，稍微延迟一点，等幕布盖好了再出来
                    .transition(.opacity.animation(.easeInOut(duration: 0.15).delay(0.2)))
                }
            }
        }
        .frame(height: 27)
        // 幕布动画：平滑擦除
        .animation(.easeInOut(duration: 0.3), value: isEditing)
        
        // 监听快捷键 Cmd+Shift+G
        .onReceive(NotificationCenter.default.publisher(for: .focusPathField)) { _ in
            startEditing()
        }
    }
    
    // --- 逻辑 ---
    
    func startEditing() {
        tempText = path
        isEditing = true
        // 延迟聚焦，等输入框显示出来
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isFocused = true
        }
    }
    
    func cancelEdit() {
        isEditing = false
        isFocused = false
    }
    
    func commitPath() {
        let expanded = (tempText as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) {
            path = expanded
            onNavigate()
            cancelEdit()
        } else {
            NSSound.beep()
        }
    }
}
