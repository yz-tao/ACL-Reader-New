//
//  VisualEffectBlur.swift
//  ACL Reader New
//
//  Created by tyz on 1/10/26.
//

import SwiftUI
import AppKit // 必须导入 AppKit

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = DraggableVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// 核心：子类化 NSVisualEffectView
class DraggableVisualEffectView: NSVisualEffectView {
    // 只要重写这个属性并返回 true，macOS 就会自动处理窗口拖拽
    // 无需手动编写 mouseDown 事件
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
}
