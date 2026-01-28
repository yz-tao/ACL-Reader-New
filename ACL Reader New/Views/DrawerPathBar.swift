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
    
    // MARK: - 1. 动画配置 (在这里修改速度，逻辑会自动同步)
    // 面包屑擦除/生长的耗时
    private let slideDuration: TimeInterval = 5.35  //0.55
    // 输入框淡入/淡出的耗时
    private let fadeDuration: TimeInterval = 0.2
    
    // MARK: - 2. 状态管理
    // 控制幕布的状态 (true = 盖住面包屑, false = 露出面包屑)
    @State private var isCovered: Bool = false
    // 控制输入框的可见性 (true = 显示, false = 隐藏)
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
                .frame(width: geo.size.width) // 强制撑满
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
                    // 使用配置好的 fadeDuration
                    .transition(.opacity.animation(.easeInOut(duration: fadeDuration)))
                }
            }
        }
        .frame(height: 27)
        // 幕布动画绑定配置好的 slideDuration
        .animation(.easeInOut(duration: slideDuration), value: isCovered)
        
        // 全局快捷键
        .onReceive(NotificationCenter.default.publisher(for: .focusPathField)) { _ in
            startEditingSequence()
        }
    }
    
    // MARK: - 3. 时序控制逻辑 (核心修复)
    
    func startEditingSequence() {
        // 防止重复触发
        guard !isCovered else { return }
        
        tempText = path
        
        // 步骤 1: 开始拉幕布 (面包屑开始消失)
        isCovered = true
        
        // 步骤 2: 等待幕布动画完全结束 (Dynamic Delay)
        Task {
            // 将秒转换为纳秒，确保等待时间与动画时间精确匹配
            try? await Task.sleep(nanoseconds: UInt64(slideDuration * 1_000_000_000))
            
            // 步骤 3: 幕布盖严实了，输入框才淡入
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
        
        // 步骤 1: 隐藏输入框 (淡出)
        showInput = false
        isFocused = false
        
        // 步骤 2: 等待输入框淡出动画结束
        Task {
            try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
            
            // 步骤 3: 只有输入框彻底没了，幕布才拉开 (面包屑显露)
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
            NSSound.beep()
        }
    }
}
