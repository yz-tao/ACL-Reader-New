//
//  FinderPathBar.swift
//  ACL Reader New
//
//  Created by tyz on 1/11/26.
//

import SwiftUI

struct FinderPathBar: View {
    let path: String
    let onPathSelect: (String) -> Void
    
    // 引入环境遍历以检测深浅色模式（虽然主要逻辑在 ButtonStyle 里，但 View 层也可以用）
    @Environment(\.colorScheme) var colorScheme
    
    private struct PathNode: Identifiable {
        let id = UUID()
        let name: String
        let fullPath: String
        let icon: NSImage
        let isLast: Bool
    }
    
    private var pathNodes: [PathNode] {
        let url = URL(fileURLWithPath: path)
        var nodes: [PathNode] = []
        let components = url.pathComponents
        
        var currentPath = ""
        for (index, component) in components.enumerated() {
            if component == "/" {
                currentPath = "/"
            } else {
                if currentPath == "/" {
                    currentPath += component
                } else {
                    currentPath += "/" + component
                }
            }
            
            var displayName = component
            if component == "/" {
                displayName = FileManager.default.displayName(atPath: "/")
            }
            let icon = NSWorkspace.shared.icon(forFile: currentPath)
            
            nodes.append(PathNode(
                name: displayName,
                fullPath: currentPath,
                icon: icon,
                isLast: index == components.count - 1
            ))
        }
        return nodes
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(pathNodes) { node in
                        Button(action: {
                            onPathSelect(node.fullPath)
                        }) {
                            HStack(spacing: 4) {
                                Image(nsImage: node.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                                
                                Text(node.name)
                                    .font(.system(size: 12))
                                    // [关键修改] 这里不再写死颜色，颜色由 ButtonStyle 统一控制
                                    .fontWeight(.regular)
                                    .lineLimit(1)
                                    .fixedSize()
                                
                                if !node.isLast {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.secondary.opacity(0.5)) // 箭头保持半透明
                                        .padding(.leading, 4)
                                        .padding(.trailing, 2)
                                }
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        // 应用新样式
                        .buttonStyle(FinderNodeButtonStyle(isLast: node.isLast))
                        .disabled(node.isLast)
                    }
                }
                .padding(.horizontal, 10)
            }
            Spacer()
        }
        .frame(height: 26)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// [重写] 更加原生的无边框点击反馈样式
struct FinderNodeButtonStyle: ButtonStyle {
    let isLast: Bool
    @Environment(\.colorScheme) var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // 1. 颜色逻辑：
            // - 常态：Secondary (灰色)
            // - 按下：Primary (浅色模式下变黑，深色模式下变白)
            // - 最后一个节点(isLast)：始终为 Primary
            .foregroundColor(
                configuration.isPressed || isLast ? .primary : .secondary
            )
            // 2. 亮度逻辑 (针对图标)：
            // - 按下时，浅色模式下稍微变暗(-0.1)，深色模式下稍微变亮(+0.1)
            // - 这会让彩色图标也有点击反馈，而不仅仅是文字变色
            .brightness(
                configuration.isPressed && !isLast
                ? (colorScheme == .dark ? 0.1 : -0.1)
                : 0
            )
            // [关键] 移除了 background，不再有方块轮廓
            // 保持透明背景，仅通过上面的颜色和亮度变化来反馈交互
    }
}
