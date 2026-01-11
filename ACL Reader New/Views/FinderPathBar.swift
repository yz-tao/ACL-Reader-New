//
//  FinderPathBar.swift
//  ACL Reader New
//
//  Created by tyz on 1/11/26.
//

//
//  FinderPathBar.swift
//  ACL Reader New
//
//  Created by CodeX.
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
                        HStack(spacing: 4) {
                            // 图标
                            Image(nsImage: node.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                            
                            // 名称
                            Text(node.name)
                                .font(.system(size: 12))
                                // [修改] 统一字体样式，不再区分 isLast
                                .foregroundColor(.secondary) // 统一为灰色
                                .fontWeight(.regular)        // 统一为常规字重
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
                        .contentShape(Rectangle())
                        // 交互：点击跳转
                        .onTapGesture {
                            if !node.isLast {
                                onPathSelect(node.fullPath)
                            }
                        }
                        // 悬停效果
                        .onHover { isHovering in
                            if isHovering && !node.isLast {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            
            // 占位符，把内容推到左边
            Spacer()
            
            // [已删除] 右侧的文件类型文字
        }
        .frame(height: 26)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
