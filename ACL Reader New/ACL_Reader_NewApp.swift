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
        WindowGroup {
            ContentView()
        }
        // [新增] 隐藏系统默认标题栏，实现沉浸式效果
        // 这会让 ContentView 充满整个窗口，包括红绿灯区域
        .windowStyle(.hiddenTitleBar)

        WindowGroup("ACL 查看器", id: "viewer", for: String.self) { $path in
            ContentView(initialPath: path)
        }
        // 新窗口同样需要这个样式
        .windowStyle(.hiddenTitleBar)
    }
}
