//
//  WindowHelpers.swift
//  ACL Reader New
//
//  Created by CodeY.
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.callback(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class ToolbarConfigurator {
    static func configure(_ window: NSWindow, with viewModel: ScannerViewModel) {
        // 使用 String 比较 ID，避免类型错误
        if window.toolbar?.identifier == NSToolbar.Identifier("MainNativeToolbar") { return }
        
        let coordinator = ToolbarCoordinator(viewModel: viewModel)
        objc_setAssociatedObject(window, "ToolbarCoordinator", coordinator, .OBJC_ASSOCIATION_RETAIN)
        
        let toolbar = NSToolbar(identifier: "MainNativeToolbar")
        toolbar.delegate = coordinator
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        
        // --- 核心样式：Expanded ---
        // 这种样式下，Title 位于红绿灯旁边，Toolbar 位于下方
        window.toolbarStyle = .expanded
        
        // 强制显示标题 (保证第一行不为空)
        window.titleVisibility = .visible
        window.title = "ACL Reader New"
        
        // 允许内容延伸到顶部，形成一体化背景
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        
        window.toolbar = toolbar
    }
}
