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
    
    // MARK: - 1. 动画配置 (在这里修改速度)
    // 幕布擦除/生长的耗时 (面包屑消失/出现)
    private let slideDuration: TimeInterval = 0.35
    // 输入框淡入/淡出的耗时
    private let fadeDuration: TimeInterval = 0.2
    
    // MARK: - 2. 状态管理
    // 控制幕布状态 (true = 盖住面包屑, false = 露出面包屑)
    @State private var isCovered: Bool = false
    // 控制输入框可见性 (true = 显示, false = 隐藏)
    @State private var showInput: Bool = false
    
    // 输入框数据
    @State private var tempText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                
                // --- 层级 A: 原生面包屑 (最底层) ---
                FinderPathBar(path: path) { newPath in
                    path = newPath
                    onNavigate()
                }
                // 【核心稳健性】强行撑满宽度，防止原生控件塌缩
                .frame(width: geo.size.width)
                .contentShape(Rectangle())
                .onTapGesture {
                    startEditingSequence()
                }
                
                // --- 层级 B: 遮盖幕布 (中间层) ---
                // 颜色与背景一致，负责“擦除”视觉效果
                Color(nsColor: .textBackgroundColor)
                    // 宽度动画：覆盖时全宽，浏览时 0 宽
                    .frame(width: isCovered ? geo.size.width : 0)
                    // 靠右对齐：宽度增加时从右向左长，宽度减小时从左向右缩
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                // --- 层级 C: 输入框 (最顶层) ---
                if showInput {
                    HStack(spacing: 0) {
                        // 1. 输入框
                        // 去掉所有修饰，纯文字，实现“原地编辑”的视觉融合感
                        TextField("前往文件夹...", text: $tempText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .disableAutocorrection(true)
                            .focused($isFocused)
                            // 【UI 微调】左边距设为 4，修正文字与底层图标的视觉误差，实现对齐
                            .padding(.leading, 7)
                            .onSubmit {
                                commitPath()
                            }
                        
                        // 2. 清除/取消按钮
                        // 保持在最右侧，低调显示
                        Button(action: { cancelEditSequence() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                    }
                    // 高度与面包屑容器一致
                    .frame(height: 27)
                    // 只有淡入淡出，没有背景板，看起来更原生
                    .transition(.opacity.animation(.easeInOut(duration: fadeDuration)))
                }
            }
        }
        .frame(height: 27)
        // 幕布动画绑定
        .animation(.easeInOut(duration: slideDuration), value: isCovered)
        
        // 监听全局快捷键 (Cmd+Shift+G)
        .onReceive(NotificationCenter.default.publisher(for: .focusPathField)) { _ in
            startEditingSequence()
        }
    }
    
    // MARK: - 3. 时序控制逻辑 (严格状态机)
    
    func startEditingSequence() {
        // 防止重复触发
        guard !isCovered else { return }
        
        tempText = path
        
        // 步骤 1: 拉上幕布 (面包屑开始从右向左消失)
        isCovered = true
        
        // 步骤 2: 等待幕布完全盖住
        Task {
            // 精确等待 slideDuration 秒
            try? await Task.sleep(nanoseconds: UInt64(slideDuration * 1_000_000_000))
            
            // 步骤 3: 幕布盖严后，输入框淡入
            await MainActor.run {
                showInput = true
                // 稍微给一点点视觉缓冲再聚焦，体验更柔和
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFocused = true
                }
            }
        }
    }
    
    func cancelEditSequence() {
        // 防止重复触发
        guard showInput else { return }
        
        // 步骤 1: 隐藏输入框 (开始淡出)
        showInput = false
        isFocused = false
        
        // 步骤 2: 等待输入框完全消失
        Task {
            try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
            
            // 步骤 3: 输入框没了，拉开幕布 (面包屑显示)
            await MainActor.run {
                isCovered = false
            }
        }
    }
    
    func commitPath() {
        let expanded = (tempText as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) {
            path = expanded
            onNavigate()
            cancelEditSequence()
        } else {
            // 错误反馈：播放系统提示音
            NSSound.beep()
        }
    }
}
