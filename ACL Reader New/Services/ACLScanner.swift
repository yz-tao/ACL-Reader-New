//
//  ACLScanner.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//

import Foundation
import Darwin

// --- 【新增：匹配强度策略】 ---
enum MatchGrade {
    case strict      // 第一阶段：位全等匹配（严谨）
    case compatible // 第二阶段：子集包含匹配（解决权限缩减变异）
}

actor ACLScanner {
    
    private class ManagedACL {
        let pointer: acl_t
        init(_ p: acl_t) { self.pointer = p }
        deinit { acl_free(UnsafeMutableRawPointer(pointer)) }
    }

    // --- 【重构后的主函数】 ---
    static func scanWithAncestry(at path: String) async throws -> [ACEEntry] {
        // 1. 获取初始条目
        var finalEntries = try fetchRawEntries(at: path, depth: 0)
        let inheritedIndices = finalEntries.indices.filter { finalEntries[$0].isInherited }
        if inheritedIndices.isEmpty { return finalEntries }
        
        // --- 【第一阶段：严谨扫描】 ---
        // 逻辑：寻找完全相等的源头。如果是“毕业照1”中的变异条目，此处会因为位不匹配而跳过。
        await performClimb(for: &finalEntries, startPath: path, grade: .strict)
        
        // --- 【第二阶段：补偿扫描】 ---
        // 逻辑：检查是否仍有未找到源头的继承项。如果有，启动子集匹配。
        let orphansExist = finalEntries.contains { $0.isInherited && $0.inheritanceDepth == -1 }
        
        if orphansExist {
            print("💡 发现权限缩减项，启动第二阶段补偿扫描...")
            // 补偿扫描会利用子集匹配，在爬到 /Users 之前，在“通用共享”处成功收网并 break 循环。
            await performClimb(for: &finalEntries, startPath: path, grade: .compatible)
        }
        
        // 兜底处理：最终依然无法追溯的条目
        for i in finalEntries.indices where finalEntries[i].isInherited && finalEntries[i].inheritanceDepth == -1 {
            finalEntries[i].inheritanceDepth = 999
            finalEntries[i].sourcePath = "系统受限或未知源头"
        }
        
        return finalEntries
    }

    // --- 【新增：封装的路径爬升引擎】 ---
    private static func performClimb(for entries: inout [ACEEntry], startPath: String, grade: MatchGrade) async {
        var currentPath = startPath
        var currentDepth = 1
        var visitedNodeHashes = Set<Int>() // 物理 Inode 守卫

        if let rootID = getFileSystemIdentifier(for: startPath) {
            visitedNodeHashes.insert(rootID)
        }

        while let parentPath = getParentDirectory(of: currentPath), parentPath != "/", currentDepth <= 64 {
            
            // A. Inode 守卫防止死循环
            guard let currentNodeID = getFileSystemIdentifier(for: parentPath) else { break }
            if visitedNodeHashes.contains(currentNodeID) { break }
            visitedNodeHashes.insert(currentNodeID)
            
            // B. 获取父目录权限
            let parentEntries: [ACEEntry]
            do {
                parentEntries = try fetchRawEntries(at: parentPath, depth: currentDepth)
            } catch {
                // --- 【修改：在中断时记录当前路径并标记红色警告】 ---
                        for i in entries.indices where entries[i].isInherited && entries[i].inheritanceDepth == -1 {
                            entries[i].sourcePath = "中断于: \(URL(fileURLWithPath: parentPath).lastPathComponent) (系统受限)"
                            entries[i].isSystemInterrupted = true
                        }
                        print("🛑 溯源中断于 [\(parentPath)]")
                        break
            }
            
            var allFoundThisPass = true
            
            // C. 匹配逻辑
            for idx in entries.indices {
                // 只处理【是继承项】且【尚未找对源头】的条目
                if entries[idx].isInherited && entries[idx].inheritanceDepth == -1 {
                    if let _ = findExplicitSource(for: entries[idx], in: parentEntries, grade: grade) {
                        entries[idx].inheritanceDepth = currentDepth
                        entries[idx].sourcePath = parentPath
                        
                        // 逻辑记录：如果是补偿模式找回的，记录下变异状态
                        if grade == .compatible {
                            entries[idx].isHeuristicMatch = true
                            entries[idx].matchStatus = "子集匹配（权限缩减）"
                        } else {
                            entries[idx].matchStatus = "全等匹配"
                        }
                    } else {
                        allFoundThisPass = false
                    }
                }
            }
            
            // 如果本轮涉及的所有孤儿都找齐了，提前退出循环
            if allFoundThisPass { break }
            
            currentPath = parentPath
            currentDepth += 1
        }
    }

    // --- 【重构：带强度选择的匹配函数】 ---
    private static func findExplicitSource(for target: ACEEntry, in parentEntries: [ACEEntry], grade: MatchGrade) -> ACEEntry? {
        parentEntries.first { parent in
            // 身份一致性是所有匹配的底线（Trustee + Type）
            guard !parent.isInherited,
                  parent.uuidString == target.uuidString,
                  parent.type == target.type else { return false }
            
            let childMask = target.rawBitmask
            let parentMask = parent.rawBitmask
            
            switch grade {
            case .strict:
                // 第一阶段：位全等
                return childMask == parentMask
            case .compatible:
                // 第二阶段：子集包含。
                // 逻辑：(childMask & parentMask) == childMask 证明父掩码涵盖了子项所有位
                return (childMask & parentMask) == childMask
            }
        }
    }

    // --- 以下保持原有 fetchRawEntries 及辅助函数逻辑不变，增加 Inode 获取支持 ---

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
                let inherited = checkIsInherited(e)
                results.append(ACEEntry(
                    name: resolveName(e),
                    uuidString: getUUIDString(e),
                    isGroup: checkIsGroup(e),
                    type: getTagType(e),
                    permissions: parsePermissions(e),
                    flags: parseFlags(e),
                    rawBitmask: getSafeRawMask(e),
                    isInherited: inherited,
                    inheritanceDepth: inherited ? -1 : 0,
                    sourcePath: inherited ? "正在溯源..." : path,
                    index: i
                ))
                res = acl_get_entry(aclPtr, ACL_NEXT_ENTRY.rawValue, &entry)
                i += 1
            }
            return results
        }
        
        // 这里的访问检查维持原有的 EPERM/EACCES 精准诊断
        if access(path, R_OK) != 0 {
            let err = errno
            if err == EPERM { throw CustomError.systemRestricted(path) }
            if err == EACCES { throw CustomError.privacyRestricted(path) }
        }
        return []
    }

    private static func getFileSystemIdentifier(for path: String) -> Int? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        // 使用 dev + inode 的组合作为物理唯一标识
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
