//
//  ACL_Reader_NewApp.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//

import SwiftUI

@main
struct ACL_Reader_NewApp: App {
    var body: some Scene {
        // 1. 主窗口（默认启动）
        WindowGroup {
            ContentView()
        }
        // 限制 macOS 只能运行一个主实例不太可能，但我们可以给它定义名字
        .commands {
            // 这里可以添加自定义菜单，目前先保持默认
        }

        // 2. 辅助查看器窗口（用于打开新文件）
        // 当调用 openWindow(id: "viewer", value: path) 时触发
        WindowGroup("ACL 查看器", id: "viewer", for: String.self) { $path in
            ContentView(initialPath: path)
        }
    }
}
