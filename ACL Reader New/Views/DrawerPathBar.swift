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
    
    // MARK: - 动画配置
    private let slideDuration: TimeInterval = 0.35
    private let fadeDuration: TimeInterval = 0.2
    
    // MARK: - 状态管理
    @State private var isCovered: Bool = false
    @State private var showInput: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                
                // --- 层级 A: 原生面包屑 (常驻) ---
                FinderPathBar(path: path) { newPath in
                    path = newPath
                    onNavigate()
                }
                .frame(width: geo.size.width) // 强制撑满
                .contentShape(Rectangle())
                .onTapGesture {
                    startEditingSequence()
                }
                
                // --- 层级 B: 遮盖幕布 (动画层) ---
                Color(nsColor: .textBackgroundColor)
                    .frame(width: isCovered ? geo.size.width : 0)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                // --- 层级 C: 路径输入栏 (功能层) ---
                if showInput {
                    // 直接调用分离出来的组件
                    PathInputBar(
                        currentPath: $path,
                        onCommit: { newPath in
                            // 1. 更新路径
                            path = newPath
                            // 2. 触发导航
                            onNavigate()
                            // 3. 退出编辑动画
                            cancelEditSequence()
                        },
                        onCancel: {
                            // 退出编辑动画
                            cancelEditSequence()
                        }
                    )
                    // 组件进出动画
                    .transition(.opacity.animation(.easeInOut(duration: fadeDuration)))
                }
            }
        }
        .frame(height: 27)
        // 幕布动画绑定
        .animation(.easeInOut(duration: slideDuration), value: isCovered)
        
        // 监听全局快捷键
        .onReceive(NotificationCenter.default.publisher(for: .focusPathField)) { _ in
            startEditingSequence()
        }
    }
    
    // MARK: - 动画时序控制 (保持不变)
    
    func startEditingSequence() {
        guard !isCovered else { return }
        
        // 1. 拉幕布
        isCovered = true
        
        // 2. 等待幕布关好
        Task {
            try? await Task.sleep(nanoseconds: UInt64(slideDuration * 1_000_000_000))
            // 3. 显示输入栏
            await MainActor.run {
                showInput = true
            }
        }
    }
    
    func cancelEditSequence() {
        guard showInput else { return }
        
        // 1. 隐藏输入栏
        showInput = false
        
        // 2. 等待淡出
        Task {
            try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
            // 3. 拉开幕布
            await MainActor.run {
                isCovered = false
            }
        }
    }
}
