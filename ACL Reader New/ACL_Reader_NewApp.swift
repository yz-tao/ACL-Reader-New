//
//  ACL_Reader_NewApp.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//

import SwiftUI

// [新增] 定义一个通知名称，用于发送“聚焦输入框”的信号
extension Notification.Name {
    static let focusPathField = Notification.Name("focusPathField")
}

@main
struct ACL_Reader_NewApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
            
        }
        // [关键] 声明统一工具栏样式，这是实现全屏整体下滑的“入场券”
        .windowToolbarStyle(.unified)
        .windowStyle(.hiddenTitleBar)
        // [新增] 添加菜单栏命令
        .commands {
            CommandMenu("前往") {
                Button("前往文件夹...") {
                    // 发送通知，通知 ContentView 聚焦输入框
                    NotificationCenter.default.post(name: .focusPathField, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift]) // 绑定 Cmd+Shift+G
            }
        }

        WindowGroup("ACL 查看器", id: "viewer", for: String.self) { $path in
            ContentView(initialPath: path)
        }
        .windowStyle(.hiddenTitleBar)
        // 新窗口也需要支持这个菜单，SwiftUI 会自动处理
    }
}
