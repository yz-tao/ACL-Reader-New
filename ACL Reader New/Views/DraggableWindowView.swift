//
//  DraggableWindowView.swift
//  ACL Reader New
//
//  Created by tyz on 1/16/26.
//  Created by CodeY.
//  Force-enabled drag support using performDrag(with:).
//

import SwiftUI
import AppKit

struct DraggableWindowView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DraggableView()
        // 关键：确保视图能随父容器自动调整大小，填满整个区域
        view.autoresizingMask = [.width, .height]
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    // 内部私有类
    private class DraggableView: NSView {
        // 1. 告诉系统：在这个视图上按下鼠标，是可以移动窗口的
        override var mouseDownCanMoveWindow: Bool { true }
        
        // 2. 【核弹级修复】如果上面的属性被 SwiftUI 忽略，
        // 我们手动监听鼠标按下事件，并直接命令窗口“开始拖拽”！
        override func mouseDown(with event: NSEvent) {
            // 只有当窗口存在时才触发
            self.window?.performDrag(with: event)
        }
        
        // 3. 确保这个视图是“实心”的，能接收到点击
        // 有时候透明视图会被系统优化掉，我们重写 hitTest 确保它永远在
        override func hitTest(_ point: NSPoint) -> NSView? {
            // 如果点在我的范围内，就返回我自己
            let localPoint = convert(point, from: superview)
            if self.bounds.contains(localPoint) {
                return self
            }
            return nil
        }
    }
}
