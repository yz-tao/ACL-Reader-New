//
//  ScannerViewModel.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//

import SwiftUI

@MainActor
class ScannerViewModel: ObservableObject {
    // 界面上显示的路径
    @Published var path: String
    // 扫描出来的权限列表
    @Published var results: [ACEEntry] = []
    // 是否正在扫描
    @Published var isScanning: Bool = false
    // 错误信息提示
    @Published var errorMessage: String? = nil

    // [修改] 增加初始化方法，允许传入初始路径
    // 如果没有传入，默认设为空字符串，不再默认 "/Library" 以避免误导
    init(path: String? = nil) {
        self.path = path ?? ""
    }

    // 执行扫描的函数
    func startScan() {
        guard !path.isEmpty else { return }
        
        isScanning = true
        errorMessage = nil
        self.results = []
        
        Task {
            do {
                let entries = try await ACLScanner.scanWithAncestry(at: path)
                self.results = entries
                
                if entries.isEmpty {
                    self.errorMessage = "该文件/文件夹没有设置扩展 ACL 权限。"
                }
            } catch let error as POSIXError where error.code == .EACCES {
                self.errorMessage = "🚫 权限不足 (沙盒限制)\n\n你手动输入的路径被 macOS 沙盒拦截了。\n请尝试将文件**拖入窗口**，或点击“浏览”按钮选择。"
            } catch {
                self.errorMessage = "读取失败: \(error.localizedDescription)"
            }
            isScanning = false
        }
    }
    
    // 弹出 macOS 原生的文件夹选择窗口
    func selectPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "请选择要分析 ACL 权限的文件或文件夹"
        
        if panel.runModal() == .OK {
            self.path = panel.url?.path ?? ""
            startScan()
        }
    }
}
