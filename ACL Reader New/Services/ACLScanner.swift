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
        while let parentPath = getParentDirectory(of: currentPath), parentPath != "/", currentDepth <= 64 {
            
            // 1. 物理拓扑校验 (Inode Guard)
            // 获取父目录的物理身份证，若无法获取则中止溯源
            guard let currentNodeID = getFileSystemIdentifier(for: parentPath) else { break }
            
            // 查重逻辑：
            // a) 如果哈希值已存在，说明路径存在逻辑回环（软链接死循环），立即停止。
            // b) 同时也涵盖了磁盘挂载点变更检测。
            if visitedNodeHashes.contains(currentNodeID) {
                break
            }
            visitedNodeHashes.insert(currentNodeID)
            
            // 2. 执行扫描（维持当前逻辑：若在此处撞到沙盒墙，则抛出错误并由 ViewModel 显示引导）
            let parentEntries = try fetchRawEntries(at: parentPath, depth: currentDepth)
            
            var allConfirmed = true
            for idx in inheritedIndices {
                if finalEntries[idx].inheritanceDepth == -1 {
                    // 使用指纹匹配逻辑寻找显式源头
                    if let _ = findExplicitSource(for: finalEntries[idx], in: parentEntries) {
                        finalEntries[idx].inheritanceDepth = currentDepth
                        finalEntries[idx].sourcePath = parentPath
                    } else {
                        // 这一层没找到，需要继续向上
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
        // 尝试获取文件系统的扩展 ACL
        let rawAcl = acl_get_file(path, ACL_TYPE_EXTENDED)
        
        // 内存托管：一旦拿到原始指针，立即交给托管类处理
        if let validRawAcl = rawAcl {
            // 只要 aclManaged 变量在 fetchRawEntries 运行结束，其 ManagedACL 实例就会销毁并触发 acl_free
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
        
        // 权限探测逻辑
        if access(path, R_OK) != 0 {
            let e = errno
            if e == EACCES || e == EPERM {
                throw POSIXError(.EACCES)
            }
            if e == ENOENT {
                throw POSIXError(.ENOENT)
            }
        }
        
        // 有权限但无 ACL
        return []
    }

    // 获取物理标识符并进行哈希保护（去标识化处理）
    private static func getFileSystemIdentifier(for path: String) -> Int? {
        var st = stat()
        // 通过 stat 获取 st_dev (设备ID) 和 st_ino (节点ID)
        guard stat(path, &st) == 0 else { return nil }
        // 将两者组合为指纹并哈希，保证仅在内存中存在且外部无法还原物理 ID
        return "\(st.st_dev)-\(st.st_ino)".hashValue
    }

    // 将 UUID 转换为用户名或组名
    private static func resolveName(_ entry: acl_entry_t) -> String {
        guard let q = acl_get_qualifier(entry) else { return "未知" }
        // 核心加固：qualifier 产生的内存必须立刻转换并在此处手动释放
        defer { acl_free(q) }
        
        let uPtr = q.bindMemory(to: uuid_t.self, capacity: 1)
        var id: uid_t = 0
        var type: Int32 = 0
        
        let rawUuidPtr = UnsafeRawPointer(uPtr).assumingMemoryBound(to: UInt8.self)
        
        // 调用桥接后的系统函数解析身份
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
