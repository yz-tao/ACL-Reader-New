//
//  FinderPathBar.swift
//  ACL Reader New
//
//  Fixed by CodeY: Uses index-based resolution to bypass read-only 'url' property.
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
        pathControl.target = context.coordinator
        pathControl.action = #selector(Coordinator.pathControlClicked(_:))
        
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // 5. 【关键修复】去掉蓝框 & 解决"点两次"问题
        // .none 去掉视觉上的蓝色光圈
        pathControl.focusRingType = .none
        // true 拒绝成为第一响应者，这样点击会立即触发 Action，而不是先获取焦点
        pathControl.refusesFirstResponder = true
        return pathControl
    }
    
    func updateNSView(_ nsView: NSPathControl, context: Context) {
        // 【关键修复 1】时刻同步 parent，确保 Coordinator 访问到最新的 path 数据
        context.coordinator.parent = self
        
        if path.isEmpty {
            nsView.pathItems = []
            return
        }

        let fileURL = URL(fileURLWithPath: path)
        let componentsStrings = fileURL.pathComponents
        
        var items: [NSPathControlItem] = []
        var currentURL = URL(fileURLWithPath: "/")
        
        for component in componentsStrings {
            let item = NSPathControlItem()
            
            if component == "/" {
                // --- 根节点视觉处理 ---
                // 获取卷标名称 (如 "Macintosh HD")
                let volumeName = (try? currentURL.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Macintosh HD"
                item.title = volumeName
                item.image = NSWorkspace.shared.icon(forFile: "/")
                
                // 注意：我们不设置 item.url，因为它是只读的
            } else {
                // --- 普通节点视觉处理 ---
                currentURL.appendPathComponent(component)
                item.title = component
                item.image = NSWorkspace.shared.icon(forFile: currentURL.path)
            }
            
            items.append(item)
        }
        
        nsView.pathItems = items
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: FinderPathBar
        init(_ parent: FinderPathBar) { self.parent = parent }
        
        @objc func pathControlClicked(_ sender: NSPathControl) {
            // 【关键修复 2】通过索引推算路径
            // 1. 获取用户点击了第几个节点
            guard let clickedItem = sender.clickedPathItem,
                  let index = sender.pathItems.firstIndex(of: clickedItem)
            else { return }
            
            // 2. 获取当前的完整路径组件
            let fullURL = URL(fileURLWithPath: parent.path)
            let allComponents = fullURL.pathComponents
            
            // 安全检查：防止数组越界
            guard index < allComponents.count else { return }
            
            // 3. 截取从根目录到被点击节点的路径组件
            let targetComponents = Array(allComponents[0...index])
            
            // 4. 重组为路径字符串
            let newPath = NSString.path(withComponents: targetComponents)
            
            // 5. 回调
            parent.onPathSelect(newPath)
        }
    }
}
