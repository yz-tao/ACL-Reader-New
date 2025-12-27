//
//  ACLScanner.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//

import Foundation
import Darwin

actor ACLScanner {
    
    // --- 核心加固：内存托管包装类 (RAII 模式) ---
    // 逻辑：利用 Swift 类生命周期管理 ARC 引用计数，确保 C 指针在对象销毁时自动触发析构释放。
    private class ManagedACL {
        let pointer: acl_t
        init(_ p: acl_t) { self.pointer = p }
        deinit {
            // 当 ManagedACL 实例引用计数归零时，自动执行洗手程序
            acl_free(UnsafeMutableRawPointer(pointer))
        }
    }

    // 递归扫描的主入口：不仅读取当前路径，还会向上追溯继承源
    static func scanWithAncestry(at path: String) async throws -> [ACEEntry] {
        
        // --- 探针代码开始 ---
        let testPath = "/Users/通用共享/毕业照1" // 确保路径完全准确
        var st = stat()

        // 1. 测试基础物理信息获取
        if stat(testPath, &st) == 0 {
            print("探针检测 - Inode: \(st.st_ino)")
        }

        // 2. 测试 ACL 获取 (这是你 App 报错的核心点)
        let rawAcl = acl_get_file(testPath, ACL_TYPE_EXTENDED)
        if rawAcl == nil {
            let errorNum = errno
            let errorDesc = String(cString: strerror(errorNum))
            print("❌ 探针结果：内核拒绝访问！Errno: \(errorNum) (\(errorDesc))")
            
            if errorNum == EPERM {
                print("💡 实锤结论：这是 TCC/SIP 级别的内核拦截。")
            }
        } else {
            print("✅ 探针结果：奇怪，代码层级竟然可以访问。")
            acl_free(UnsafeMutableRawPointer(rawAcl!))
        }
        // --- 探针代码结束 ---
        
        
        var finalEntries = try fetchRawEntries(at: path, depth: 0)
        let inheritedIndices = finalEntries.indices.filter { finalEntries[$0].isInherited }
        
        // 如果没有继承项，直接返回结果
        if inheritedIndices.isEmpty { return finalEntries }
        
        var currentPath = path
        var currentDepth = 1
        
        // --- 核心加固：带隐私保护的物理路径守卫 ---
        // 逻辑：仅在内存中存储物理 ID 的哈希值，任务结束自动销毁。
        var visitedNodeHashes = Set<Int>()
        
        // 登记起始路径的物理身份指纹
        if let rootID = getFileSystemIdentifier(for: path) {
            visitedNodeHashes.insert(rootID)
        }
        
        // 向上爬升（限制最高64层以防万一）
        // --- 在新分支 Sandbox-Refactor 中重构此循环 ---
        while let parentPath = getParentDirectory(of: currentPath), parentPath != "/", currentDepth <= 64 {
            
            // 物理守卫逻辑维持不变
            guard let currentNodeID = getFileSystemIdentifier(for: parentPath) else { break }
            if visitedNodeHashes.contains(currentNodeID) { break }
            visitedNodeHashes.insert(currentNodeID)
            
            // --- 核心改进：优雅降级逻辑 ---
            let parentEntries: [ACEEntry]
            do {
                // 尝试获取父目录 ACL
                parentEntries = try fetchRawEntries(at: parentPath, depth: currentDepth)
            } catch {
                // 关键点：如果在溯源过程中遇到权限问题（EACCES/EPERM），不再抛出错误。
                // 我们选择优雅地“就地解散”，保留目前已有的发现。
                print("溯源至 \(parentPath) 时触发系统限制: \(error.localizedDescription)")
                break
            }
            
            var allConfirmed = true
            for idx in inheritedIndices {
                if finalEntries[idx].inheritanceDepth == -1 {
                    if let _ = findExplicitSource(for: finalEntries[idx], in: parentEntries) {
                        finalEntries[idx].inheritanceDepth = currentDepth
                        finalEntries[idx].sourcePath = parentPath
                    } else {
                        allConfirmed = false
                    }
                }
            }
            
            if allConfirmed { break }
            currentPath = parentPath
            currentDepth += 1
        }
        
        // 兜底：如果溯源到顶还没找到，标记为未知
        for i in inheritedIndices where finalEntries[i].inheritanceDepth == -1 {
            finalEntries[i].inheritanceDepth = 999
            finalEntries[i].sourcePath = "远程或未知源头"
        }
        
        return finalEntries
    }

    // --- 核心辅助函数 ---

    private static func fetchRawEntries(at path: String, depth: Int) throws -> [ACEEntry] {
            let rawAcl = acl_get_file(path, ACL_TYPE_EXTENDED)
            
            if let validRawAcl = rawAcl {
                let aclManaged = ManagedACL(validRawAcl)
                let aclPtr = aclManaged.pointer
                
                var results: [ACEEntry] = []
                var entry: acl_entry_t? = nil
                var res = acl_get_entry(aclPtr, ACL_FIRST_ENTRY.rawValue, &entry)
                var i = 0
                
                while res == 0, let e = entry {
                    results.append(ACEEntry(
                        name: resolveName(e),
                        uuidString: getUUIDString(e),
                        isGroup: checkIsGroup(e),
                        type: getTagType(e),
                        permissions: parsePermissions(e),
                        flags: parseFlags(e),
                        rawBitmask: getSafeRawMask(e),
                        isInherited: checkIsInherited(e),
                        inheritanceDepth: checkIsInherited(e) ? -1 : 0,
                        sourcePath: checkIsInherited(e) ? "正在溯源..." : path,
                        index: i
                    ))
                    res = acl_get_entry(aclPtr, ACL_NEXT_ENTRY.rawValue, &entry)
                    i += 1
                }
                return results
            }
            
            // --- 文件夹 B 拒绝访问的精准诊断逻辑 ---
            if access(path, R_OK) != 0 {
                let err = errno
                if err == EPERM {
                    // EPERM 通常代表 Operation not permitted，常见于 SIP 保护或 TCC 硬拦截
                    throw CustomError.systemRestricted(path)
                } else if err == EACCES {
                    // EACCES 代表 Permission denied，可能是 POSIX 000 或沙盒未授权
                    if isPrivacySensitivePath(path) {
                        throw CustomError.privacyRestricted(path)
                    }
                    throw POSIXError(.EACCES)
                } else if err == ENOENT {
                    throw POSIXError(.ENOENT)
                }
            }
            return []
        }

        // 判断是否属于 TCC 隐私敏感区域（如 Documents, Desktop, Downloads）
    private static func isPrivacySensitivePath(_ path: String) -> Bool {
        let sensitivePatterns = ["/Documents", "/Desktop", "/Downloads", "/Library/Mail", "/Library/Messages"]
        // 修正：使用 $0 代表当前遍历到的字符串模式
        return sensitivePatterns.contains { path.contains($0) }
    }

        private static func getFileSystemIdentifier(for path: String) -> Int? {
            var st = stat()
            guard stat(path, &st) == 0 else { return nil }
            return "\(st.st_dev)-\(st.st_ino)".hashValue
        }

        private static func resolveName(_ entry: acl_entry_t) -> String {
            guard let q = acl_get_qualifier(entry) else { return "未知" }
            defer { acl_free(q) }
            let uPtr = q.bindMemory(to: uuid_t.self, capacity: 1)
            var id: uid_t = 0
            var type: Int32 = 0
            let rawUuidPtr = UnsafeRawPointer(uPtr).assumingMemoryBound(to: UInt8.self)
            if mbr_uuid_to_id(rawUuidPtr, &id, &type) == 0 {
                if type == ID_TYPE_GID, let g = getgrgid(id) { return String(cString: g.pointee.gr_name) }
                if type == ID_TYPE_UID, let p = getpwuid(id) { return String(cString: p.pointee.pw_name) }
            }
            return "ID: \(id)"
        }

    private static func getSafeRawMask(_ entry: acl_entry_t) -> UInt32 {
        var ps: acl_permset_t? = nil
        acl_get_permset(entry, &ps)
        guard let validPs = ps else { return 0 }
        var fullMask: UInt32 = 0
        for perm in ACLPermission.allCases {
            if acl_get_perm_np(validPs, acl_perm_t(perm.bitmask)) == 1 {
                fullMask |= perm.bitmask
            }
        }
        return fullMask
    }

    private static func parsePermissions(_ entry: acl_entry_t) -> [String] {
        var ps: acl_permset_t? = nil
        acl_get_permset(entry, &ps)
        guard let validPs = ps else { return [] }
        return ACLPermission.allCases.compactMap { perm in
            acl_get_perm_np(validPs, acl_perm_t(perm.bitmask)) == 1 ? perm.rawValue : nil
        }
    }

    private static func parseFlags(_ entry: acl_entry_t) -> [String] {
        var fs: acl_flagset_t? = nil
        acl_get_flagset_np(UnsafeMutableRawPointer(entry), &fs)
        guard let validFs = fs else { return [] }
        return ACEFlag.allCases.compactMap { flag in
            acl_get_flag_np(validFs, acl_flag_t(flag.bitmask)) == 1 ? flag.rawValue : nil
        }
    }

    private static func checkIsInherited(_ entry: acl_entry_t) -> Bool {
        var fs: acl_flagset_t? = nil
        acl_get_flagset_np(UnsafeMutableRawPointer(entry), &fs)
        guard let validFs = fs else { return false }
        return acl_get_flag_np(validFs, acl_flag_t(ACL_ENTRY_INHERITED.rawValue)) == 1
    }

    private static func getUUIDString(_ entry: acl_entry_t) -> String {
        guard let q = acl_get_qualifier(entry) else { return "" }
        defer { acl_free(q) }
        return UUID(uuid: q.bindMemory(to: uuid_t.self, capacity: 1).pointee).uuidString
    }

    private static func checkIsGroup(_ entry: acl_entry_t) -> Bool {
        var tag: acl_tag_t = ACL_UNDEFINED_TAG
        acl_get_tag_type(entry, &tag)
        return tag == ACL_EXTENDED_ALLOW || tag == ACL_EXTENDED_DENY
    }

    private static func getTagType(_ entry: acl_entry_t) -> String {
        var tag: acl_tag_t = ACL_UNDEFINED_TAG
        acl_get_tag_type(entry, &tag)
        return tag == ACL_EXTENDED_ALLOW ? "Allow" : "Deny"
    }

    private static func getParentDirectory(of path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        return (parent == path) ? nil : parent
    }

    private static func findExplicitSource(for target: ACEEntry, in parentEntries: [ACEEntry]) -> ACEEntry? {
        parentEntries.first {
            !$0.isInherited &&
            $0.uuidString == target.uuidString &&
            $0.type == target.type &&
            $0.rawBitmask == target.rawBitmask
        }
    }
}
enum CustomError: LocalizedError {
    case systemRestricted(String)
    case privacyRestricted(String)
    
    var errorDescription: String? {
        switch self {
        case .systemRestricted(let path):
            return "系统强制保护: 文件夹 '\(URL(fileURLWithPath: path).lastPathComponent)' 受 macOS 系统完整性保护 (SIP) 或内核拦截，无法读取 ACL。"
        case .privacyRestricted(let path):
            return "隐私受限: 无法读取 '\(URL(fileURLWithPath: path).lastPathComponent)'。请在“系统设置 -> 隐私与安全性 -> 完全磁盘访问权限”中授权此 App。"
        }
    }
}
