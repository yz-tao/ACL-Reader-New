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
    
    // --- 动画状态机 ---
    // 1. 控制幕布是否盖住面包屑
    @State private var isCovered: Bool = false
    // 2. 控制输入框是否显示 (必须等幕布盖严实了再显示)
    @State private var showInput: Bool = false
    
    // 输入框内容
    @State private var tempText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                
                // --- 层级 1 (底层): 原生面包屑 ---
                // 它一直都在，只是会被上面的东西盖住
                FinderPathBar(path: path) { newPath in
                    path = newPath
                    onNavigate()
                }
                // 强制撑满宽度，防止塌缩
                .frame(width: geo.size.width)
                // 点击触发编辑
                .contentShape(Rectangle())
                .onTapGesture {
                    startEditingSequence()
                }
                
                // --- 层级 2 (中间层): 遮盖幕布 (The Curtain) ---
                // 使用与背景完全一致的颜色
                Color(nsColor: .textBackgroundColor)
                    // 宽度动画：覆盖时全宽，浏览时0宽
                    .frame(width: isCovered ? geo.size.width : 0)
                    // 【关键】靠右对齐！
                    // 这样宽度增加时，看起来是从右向左生长 (盖住面包屑)
                    // 宽度减少时，看起来是从左向右收缩 (露出面包屑)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                // --- 层级 3 (顶层): 输入框 ---
                // 只有当 showInput 为 true 时才渲染/显示
                if showInput {
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
                        
                        Button(action: { cancelEditSequence() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    // 输入框的进出动画：简单的淡入淡出
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
        }
        .frame(height: 27) // 锁定高度
        // 幕布动画配置：稍微慢一点，体现“抽屉”的质感
        .animation(.easeInOut(duration: 0.25), value: isCovered)
        
        // 监听快捷键
        .onReceive(NotificationCenter.default.publisher(for: .focusPathField)) { _ in
            startEditingSequence()
        }
    }
    
    // --- 时序控制逻辑 (核心) ---
    
    func startEditingSequence() {
        // 1. 初始化文本
        tempText = path
        
        // 2. 第一步：拉上幕布 (盖住面包屑)
        // 动画时长由上面的 .animation(.easeInOut(duration: 0.25)) 控制
        isCovered = true
        
        // 3. 第二步：等待幕布完全盖住后，显示输入框
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showInput = true
            // 再稍微等一点点，让输入框出来后再聚焦，体验更稳
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }
    
    func cancelEditSequence() {
        // 1. 第一步：隐藏输入框 (淡出)
        // 动画时长由 .transition 里的 0.15s 控制
        showInput = false
        isFocused = false
        
        // 2. 第二步：等待输入框完全消失后，拉开幕布 (露出面包屑)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isCovered = false
        }
    }
    
    func commitPath() {
        let expanded = (tempText as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) {
            path = expanded
            onNavigate()
            // 提交成功，执行退场动画
            cancelEditSequence()
        } else {
            NSSound.beep()
        }
    }
}
