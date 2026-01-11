//
//  ScannerViewModel.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//

import SwiftUI

@MainActor
class ScannerViewModel: ObservableObject {
    @Published var path: String
    @Published var results: [ACEEntry] = []
    @Published var isScanning: Bool = false
    @Published var errorMessage: String? = nil

    init(path: String? = nil) {
        self.path = path ?? ""
    }

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
