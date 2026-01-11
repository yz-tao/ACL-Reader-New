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
                                    .fontWeight(.regular)
                                    .lineLimit(1)
                                    .fixedSize()
                                
                                if !node.isLast {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.secondary.opacity(0.5))
                                        .padding(.leading, 4)
                                        .padding(.trailing, 2)
                                    // 修正：修正了箭头间距，使其更紧凑
                                }
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(FinderNodeButtonStyle(isLast: node.isLast))
                        .disabled(node.isLast)
                    }
                }
                .padding(.horizontal, 10)
            }
            Spacer()
        }
        .frame(height: 26)
        // [修改] 使用 textBackgroundColor 也就是纯白色 (浅色模式下)
        // 之前是 .windowBackgroundColor (浅灰色)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// 按钮样式保持不变
struct FinderNodeButtonStyle: ButtonStyle {
    let isLast: Bool
    @Environment(\.colorScheme) var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(
                configuration.isPressed || isLast ? .primary : .secondary
            )
            .brightness(
                configuration.isPressed && !isLast
                ? (colorScheme == .dark ? 0.3 : -0.3)
                : 0
            )
    }
}
