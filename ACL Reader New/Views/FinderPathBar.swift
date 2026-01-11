//
//  FinderPathBar.swift
//  ACL Reader New
//
//  Created by tyz on 1/11/26.
//

import SwiftUI

struct FinderPathBar: View {
    let path: String
    // 回调：当用户点击路径上的某个节点时，返回该节点的完整路径
    let onPathSelect: (String) -> Void
    
    // 路径节点模型
    private struct PathNode: Identifiable {
        let id = UUID()
        let name: String
        let fullPath: String
        let icon: NSImage
        let isLast: Bool
    }
    
    // 计算属性：构建完全还原 Finder 的路径链
    private var pathNodes: [PathNode] {
        let url = URL(fileURLWithPath: path)
        var nodes: [PathNode] = []
        
        // 1. 解析路径组件
        let components = url.pathComponents
        
        var currentPath = ""
        for (index, component) in components.enumerated() {
            // 拼接当前节点的完整路径
            if component == "/" {
                currentPath = "/"
            } else {
                if currentPath == "/" {
                    currentPath += component
                } else {
                    currentPath += "/" + component
                }
            }
            
            // 2. 获取显示名称 (还原卷标)
            var displayName = component
            if component == "/" {
                displayName = FileManager.default.displayName(atPath: "/")
            }
            
            // 3. 获取系统图标
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
            // --- 左侧：路径面包屑 ---
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(pathNodes) { node in
                        // [核心修改] 使用 Button 替代 onTapGesture
                        // Button 天然支持“按下高亮、松开触发、移出取消”的标准交互逻辑
                        Button(action: {
                            onPathSelect(node.fullPath)
                        }) {
                            HStack(spacing: 4) {
                                // 图标
                                Image(nsImage: node.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                                
                                // 名称
                                Text(node.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .fontWeight(.regular)
                                    .lineLimit(1)
                                    .fixedSize()
                                
                                // 分隔符 (除了最后一个)
                                if !node.isLast {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.secondary.opacity(0.5))
                                        .padding(.leading, 4)
                                        .padding(.trailing, 2)
                                }
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle()) // 确保点击区域完整
                        }
                        // [关键] 应用自定义样式，去掉默认按钮外观，只保留行为
                        .buttonStyle(FinderNodeButtonStyle(isLast: node.isLast))
                        // 禁用最后一个节点的交互（因为它就是当前目录，无需跳转）
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

// [新增] 自定义按钮样式，模拟 Finder 点击反馈
struct FinderNodeButtonStyle: ButtonStyle {
    let isLast: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // 按下时背景变深，且仅当不是最后一个节点时才显示反馈
            .background(
                configuration.isPressed && !isLast
                ? Color.secondary.opacity(0.15)
                : Color.clear
            )
            .cornerRadius(4)
    }
}
