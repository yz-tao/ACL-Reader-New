//
//  ScannerViewModel.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//

import SwiftUI

// 使用 @MainActor 确保所有的 UI 更新都在主线程执行
@MainActor
class ScannerViewModel: ObservableObject {
    // 界面上显示的路径
    @Published var path: String = "/Library"
    // 扫描出来的权限列表
    @Published var results: [ACEEntry] = []
    // 是否正在扫描（用于控制加载动画）
    @Published var isScanning: Bool = false
    // 错误信息提示
    @Published var errorMessage: String? = nil

    // 执行扫描的函数
    func startScan() {
            guard !path.isEmpty else { return }
            
            isScanning = true
            errorMessage = nil
            // 1. 扫描前先清空旧结果，确保界面反馈及时
            self.results = []
            
            Task {
                do {
                    let entries = try await ACLScanner.scanWithAncestry(at: path)
                    self.results = entries
                    
                    // 2. 如果成功返回但列表为空，可以给个友好提示（可选）
                    if entries.isEmpty {
                        self.errorMessage = "该文件/文件夹没有设置扩展 ACL 权限。"
                    }
                } catch let error as POSIXError where error.code == .EACCES {
                    // 3. 专门捕获沙盒导致的“拒绝访问”错误
                    self.errorMessage = "🚫 权限不足 (沙盒限制)\n\n你手动输入的路径被 macOS 沙盒拦截了。\n\n解决办法：请点击“浏览”按钮并在弹窗中选中该文件，这样系统才会临时授权给 App 读取。"
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
            // 选择路径后自动尝试扫描，提升用户体验
            startScan()
        }
    }
}
