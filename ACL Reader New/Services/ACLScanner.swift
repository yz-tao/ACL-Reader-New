//
//  ACLScanner.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//

import Foundation
import Darwin // 很多底层 C 常量和函数（如 getgrgid, getpwuid）在这里

actor ACLScanner {
    // 递归扫描的主入口：不仅读取当前路径，还会向上追溯继承源
    static func scanWithAncestry(at path: String) async throws -> [ACEEntry] {
        var finalEntries = try fetchRawEntries(at: path, depth: 0)
        let inheritedIndices = finalEntries.indices.filter { finalEntries[$0].isInherited }
        
        // 如果没有继承项，直接返回结果
        if inheritedIndices.isEmpty { return finalEntries }
        
        var currentPath = path
        var currentDepth = 1
        
        // 向上爬升，直到所有继承项找到源头，或到达根目录（限制最高64层以防万一）
        while let parentPath = getParentDirectory(of: currentPath), parentPath != "/", currentDepth <= 64 {
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
        // 1. 原生推门：使用 access 检查读权限 (R_OK)
        // 这是区分“无权限”和“未设置”最权威的底层方法
        if access(path, R_OK) != 0 {
            let e = errno
            if e == EACCES || e == EPERM || e == ENOENT {
                // 在沙盒中，权限不足时系统常返回 EACCES 或伪装成 ENOENT
                throw POSIXError(.EACCES)
            }
        }

        // 2. 原生搜屋：只有在 access 确认能进门后，才读取 ACL
        let acl = acl_get_file(path, ACL_TYPE_EXTENDED)
        
        // 如果 acl 为 nil 但 access 成功了，这才是真正的“未设置 ACL”
        if acl == nil {
            return []
        }
        
        // 3. 安全释放：拿到对象后，确保在退出作用域前释放 C 内存
        defer { acl_free(UnsafeMutableRawPointer(acl!)) }
        
        // 4. 标准解析逻辑
        var results: [ACEEntry] = []
        var entry: acl_entry_t? = nil
        var res = acl_get_entry(acl!, ACL_FIRST_ENTRY.rawValue, &entry)
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
            res = acl_get_entry(acl!, ACL_NEXT_ENTRY.rawValue, &entry)
            i += 1
        }
        return results
    }

    // 安全读取权限掩码，不使用危险的内存加载
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

    // 将 UUID 转换为人能看懂的用户名或组名
    private static func resolveName(_ entry: acl_entry_t) -> String {
            guard let q = acl_get_qualifier(entry) else { return "未知" }
            defer { acl_free(q) }
            
            let uPtr = q.bindMemory(to: uuid_t.self, capacity: 1)
            var id: uid_t = 0
            var type: Int32 = 0
            
            return withUnsafePointer(to: uPtr.pointee) { p -> String in
                // 将 uuid_t 转换为指向 UInt8 的原始指针
                let rawUuidPtr = UnsafeRawPointer(p).assumingMemoryBound(to: UInt8.self)
                
                // 调用我们上面手动声明或系统提供的函数
                if mbr_uuid_to_id(rawUuidPtr, &id, &type) == 0 {
                    if type == ID_TYPE_GID, let g = getgrgid(id) { return String(cString: g.pointee.gr_name) }
                    if type == ID_TYPE_UID, let p = getpwuid(id) { return String(cString: p.pointee.pw_name) }
                }
                return "ID: \(id)"
            }
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

    // 指纹匹配核心逻辑
    private static func findExplicitSource(for target: ACEEntry, in parentEntries: [ACEEntry]) -> ACEEntry? {
        parentEntries.first {
            !$0.isInherited &&
            $0.uuidString == target.uuidString &&
            $0.type == target.type &&
            $0.rawBitmask == target.rawBitmask
        }
    }
}

