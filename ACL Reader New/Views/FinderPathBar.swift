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
        // pathComponents 会返回 ["/", "Users", "tyz", ...]
        let components = url.pathComponents
        
        var currentPath = ""
        for (index, component) in components.enumerated() {
            // 拼接当前节点的完整路径
            if component == "/" {
                currentPath = "/"
            } else {
                // 处理路径拼接，避免出现 //Users 的情况
                if currentPath == "/" {
                    currentPath += component
                } else {
                    currentPath += "/" + component
                }
            }
            
            // 2. 获取显示名称 (关键步骤：还原卷标)
            var displayName = component
            if component == "/" {
                // 如果是根路径，获取磁盘的实际名称 (例如 "Macintosh HD")
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
    
    // 获取当前项的类型描述
    private var currentItemType: String {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return isDir.boolValue ? "文件夹" : "文件"
        }
        return "未知"
    }

    var body: some View {
        HStack(spacing: 0) {
            // --- 左侧：路径面包屑 ---
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) { // Finder 节点间距非常紧凑
                    ForEach(pathNodes) { node in
                        HStack(spacing: 4) {
                            // 图标
                            Image(nsImage: node.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                            
                            // 名称
                            Text(node.name)
                                .font(.system(size: 12)) // Finder 字体
                                .foregroundColor(node.isLast ? .primary : .secondary)
                                .fontWeight(node.isLast ? .semibold : .regular)
                                .lineLimit(1)
                                .fixedSize() // 防止文字被压缩
                            
                            // 分隔符 (除了最后一个)
                            if !node.isLast {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold)) // 很小的箭头
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .padding(.leading, 4)
                                    .padding(.trailing, 2)
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle()) // 扩大点击区域
                        // 交互：点击跳转
                        .onTapGesture {
                            if !node.isLast {
                                onPathSelect(node.fullPath)
                            }
                        }
                        // 悬停效果：模仿 Finder，鼠标放上去会有个背景色
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
            
            Spacer()
            
            // --- 右侧：类型信息 ---
            // 按照要求，只显示 "文件" 或 "文件夹"
            Text(currentItemType)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.trailing, 16)
        }
        .frame(height: 26) // Finder 底部栏标准高度
        .background(Color(nsColor: .windowBackgroundColor)) // 原生窗口背景色
        .overlay(alignment: .top) {
            Divider() // 顶部分割线
        }
    }
}
