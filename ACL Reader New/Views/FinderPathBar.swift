//
//  FinderPathBar.swift
//  ACL Reader New
//
//  Created by tyz on 1/11/26.
//  手动解析完整路径，复刻 Finder 收缩逻辑
//

import SwiftUI
import AppKit

struct FinderPathBar: NSViewRepresentable {
    let path: String
    let onPathSelect: (String) -> Void
    
    func makeNSView(context: Context) -> NSPathControl {
        let pathControl = NSPathControl()
        pathControl.pathStyle = .standard
        pathControl.isEditable = false
        pathControl.backgroundColor = .clear
        
        // 绑定交互
        pathControl.target = context.coordinator
        pathControl.action = #selector(Coordinator.pathControlClicked(_:))
        
        // 设置收缩优先级：允许水平方向压缩，触发 Finder 标志性的 "..." 省略逻辑
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return pathControl
    }
    
    func updateNSView(_ nsView: NSPathControl, context: Context) {
        guard !path.isEmpty else {
            nsView.pathItems = []
            return
        }
        
        // --- 核心修改：手动解析完整路径组件 ---
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents // 获取 [/ , Users, tyz, Desktop, ...]
        
        var currentPath = ""
        var items: [NSPathControlItem] = []
        
        for component in components {
            if component == "/" {
                currentPath = "/"
            } else {
                currentPath = (currentPath == "/") ? "/\(component)" : "\(currentPath)/\(component)"
            }
            
            // 每一个节点都手动创建一个 Item
            let item = NSPathControlItem()
            
            // 【关键技巧】手动指定 Title 和 Image，不再依赖系统的 URL 自动解析
            // 这样即使在沙盒内，只要我们手动给了文字和图标，它就能显示完整
            item.title = component == "/" ? FileManager.default.displayName(atPath: "/") : component
            item.image = NSWorkspace.shared.icon(forFile: currentPath)
            
            // 为了让点击事件能拿到路径，我们还得通过 KVC 绕过只读属性设置 URL (或者在 Coordinator 处理)
            // 这里我们采用最稳妥的方案：在 Coordinator 里手动映射
            items.append(item)
        }
        
        // 强制喂入所有层级，不再让系统自己去猜
        nsView.pathItems = items
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: FinderPathBar
        init(_ parent: FinderPathBar) { self.parent = parent }
        
        @objc func pathControlClicked(_ sender: NSPathControl) {
            // 因为我们是手动构建的 Items，点击时我们根据索引重新计算路径
            let clickedIndex = sender.pathItems.firstIndex { $0 === sender.clickedPathItem }
            if let index = clickedIndex {
                let fullComponents = URL(fileURLWithPath: parent.path).pathComponents
                let selectedComponents = fullComponents.prefix(index + 1)
                let newPath = NSString.path(withComponents: Array(selectedComponents))
                parent.onPathSelect(newPath)
            }
        }
    }
}
