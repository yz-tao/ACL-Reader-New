//
//  FinderPathBar.swift
//  ACL Reader New
//
//  Created by tyz on 1/11/26.
//  Refactored by CodeY to use NSPathControl
//

import SwiftUI
import AppKit

struct FinderPathBar: NSViewRepresentable {
    // 接收数据
    let path: String
    // 回传交互：当用户点击某个父文件夹时
    let onPathSelect: (String) -> Void
    
    // 1. 创建 NSPathControl
    func makeNSView(context: Context) -> NSPathControl {
        let pathControl = NSPathControl()
        
        // 【关键】开启标准样式 (Finder 底部导航栏样式)
        pathControl.pathStyle = .standard
        
        // 允许交互（点击父目录跳转）
        pathControl.isEditable = false
        
        // 设置背景颜色（通常不用设，默认透明或根据系统自适应）
        pathControl.backgroundColor = .clear
        
        // 绑定事件目标
        pathControl.target = context.coordinator
        pathControl.action = #selector(Coordinator.pathControlClicked(_:))
        
        // 拥抱自动布局，确保它能正确响应窗口缩放带来的压缩
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        return pathControl
    }
    
    // 2. 更新数据 (SwiftUI -> AppKit)
    func updateNSView(_ nsView: NSPathControl, context: Context) {
        if path.isEmpty {
            nsView.url = nil
        } else {
            // 将字符串转为 URL 喂给控件，它会自动解析图标和名称
            nsView.url = URL(fileURLWithPath: path)
        }
    }
    
    // 3. 处理交互 (AppKit -> SwiftUI)
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: FinderPathBar
        
        init(_ parent: FinderPathBar) {
            self.parent = parent
        }
        
        @objc func pathControlClicked(_ sender: NSPathControl) {
            // sender.clickedPathItem 获取用户点击的具体那个节点
            if let clickedItem = sender.clickedPathItem, let url = clickedItem.url {
                // 将 URL 转换回字符串路径，并通过闭包传回给 SwiftUI
                parent.onPathSelect(url.path)
            }
        }
    }
}
