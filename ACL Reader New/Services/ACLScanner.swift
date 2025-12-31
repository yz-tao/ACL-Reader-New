//
//  ACLScanner.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//  Fixed by CodeX on 12/30/25.
//

import Foundation
import Darwin

// --- 【核心修复】遗传资格验证器 ---
private struct InheritanceValidator {
    let isTargetDirectory: Bool
    
    init(at path: String) {
        var st = stat()
        if stat(path, &st) == 0 {
            self.isTargetDirectory = (st.st_mode & S_IFMT) == S_IFDIR
        } else {
            self.isTargetDirectory = false
        }
    }
    
    // 判断父项是否有资格遗传
    func canInherit(parent: ACEEntry, depth: Int) -> Bool {
        // 【修复逻辑】
        // 不再使用 rawBitmask 检查标志，因为 0x20 既是 FileInherit 又是 AppendData (AddSubdirectory)。
        // 使用已经解析好的 flags 字符串数组是绝对安全的。
        
        // 注意：这里的字符串必须与 Models.swift 中 ACEFlag 的 rawValue 保持一致
        let flags = Set(parent.flags)
        
        let hasFI = flags.contains("遗传至文件") // 对应 ACEFlag.fileInherit
        let hasDI = flags.contains("遗传至目录") // 对应 ACEFlag.dirInherit
        
        if isTargetDirectory {
            // 目标是目录，父项必须有 DI
            guard hasDI else { return false }
        } else {
            // 目标是文件，父项必须有 FI
            guard hasFI else { return false }
        }
        
        // 深度检查
        let hasLI = flags.contains("不深层遗传") // 对应 ACEFlag.limitInherit
        if hasLI && depth > 1 { return false }
        
        return true
    }
}

enum MatchGrade {
    case strict
    case compatible
}

actor ACLScanner {
    
    private class ManagedACL {
        let pointer: acl_t
        init(_ p: acl_t) { self.pointer = p }
        deinit { acl_free(UnsafeMutableRawPointer(pointer)) }
    }

    static func scanWithAncestry(at path: String) async throws -> [ACEEntry] {
        var finalEntries = try fetchRawEntries(at: path, depth: 0)
        let inheritedIndices = finalEntries.indices.filter { finalEntries[$0].isInherited }
        if inheritedIndices.isEmpty { return finalEntries }
        
        let validator = InheritanceValidator(at: path)
        
        await performClimb(for: &finalEntries, startPath: path, grade: .strict, validator: validator)
        
        let orphansExist = finalEntries.contains { $0.isInherited && $0.inheritanceDepth == -1 }
        if orphansExist {
            print("💡 发现权限缩减项，启动第二阶段补偿扫描...")
            await performClimb(for: &finalEntries, startPath: path, grade: .compatible, validator: validator)
        }
        
        for i in finalEntries.indices where finalEntries[i].isInherited && finalEntries[i].inheritanceDepth == -1 {
            finalEntries[i].inheritanceDepth = 999
            finalEntries[i].sourcePath = "系统受限或未知源头"
        }
        
        return finalEntries
    }

    private static func performClimb(for entries: inout [ACEEntry], startPath: String, grade: MatchGrade, validator: InheritanceValidator) async {
        var currentPath = startPath
        var currentDepth = 1
        var visitedNodeHashes = Set<Int>()

        if let rootID = getFileSystemIdentifier(for: startPath) {
            visitedNodeHashes.insert(rootID)
        }

        while let parentPath = getParentDirectory(of: currentPath), parentPath != "/", currentDepth <= 64 {
            guard let currentNodeID = getFileSystemIdentifier(for: parentPath) else { break }
            if visitedNodeHashes.contains(currentNodeID) { break }
            visitedNodeHashes.insert(currentNodeID)
            
            let parentEntries: [ACEEntry]
            do {
                parentEntries = try fetchRawEntries(at: parentPath, depth: currentDepth)
            } catch {
                for i in entries.indices where entries[i].isInherited && entries[i].inheritanceDepth == -1 {
                    entries[i].sourcePath = "中断于: \(URL(fileURLWithPath: parentPath).lastPathComponent) (系统受限)"
                    entries[i].isSystemInterrupted = true
                }
                break
            }
            
            var allFoundThisPass = true
            
            for idx in entries.indices {
                if entries[idx].isInherited && entries[idx].inheritanceDepth == -1 {
                    if let _ = findExplicitSource(for: entries[idx], in: parentEntries, grade: grade, validator: validator, currentDepth: currentDepth) {
                        entries[idx].inheritanceDepth = currentDepth
                        entries[idx].sourcePath = parentPath
                        
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
            
            if allFoundThisPass { break }
            currentPath = parentPath
            currentDepth += 1
        }
    }

    private static func findExplicitSource(for target: ACEEntry, in parentEntries: [ACEEntry], grade: MatchGrade, validator: InheritanceValidator, currentDepth: Int) -> ACEEntry? {
        parentEntries.first { parent in
            // 1. 身份一致性
            guard !parent.isInherited,
                  parent.uuidString == target.uuidString,
                  parent.type == target.type else { return false }
            
            // 2. 遗传资格验证 (使用 Flags 字符串)
            // 这里会正确识别 B 没有 "遗传至文件" 字符串，从而跳过 B
            guard validator.canInherit(parent: parent, depth: currentDepth) else { return false }
            
            // 3. 权限内容比对 (使用 RawMask，仅代表权限)
            let childMask = target.rawBitmask
            let parentMask = parent.rawBitmask
            
            switch grade {
            case .strict:
                return childMask == parentMask
            case .compatible:
                return (childMask & parentMask) == childMask
            }
        }
    }

    // --- 底层封装 (回滚到最初的稳健版本) ---

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
                    // 【关键回滚】: 这里的 Mask 只包含 Permission，不再混入 Flags
                    // 这样 MatchGrade 的比对就是纯粹的权限比对，不会受 Flags 干扰
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
        if access(path, R_OK) != 0 {
            let err = errno
            if err == EPERM { throw CustomError.systemRestricted(path) }
            if err == EACCES { throw CustomError.privacyRestricted(path) }
        }
        return []
    }

    // 此函数只收集权限位，保证了 findExplicitSource 中比较的是纯粹的“访问权限”
    private static func getSafeRawMask(_ entry: acl_entry_t) -> UInt32 {
        var ps: acl_permset_t? = nil
        acl_get_permset(entry, &ps)
        guard let validPs = ps else { return 0 }
        var fullMask: UInt32 = 0
        for perm in ACLPermission.allCases {
            // 注意：这里依赖 Models.swift 中的 bitmask，即使它是错的也没关系
            // 只要 Parent 和 Child 都是用同一套错误的 bitmask 生成的，它们依然相等 (Consistent)
            if acl_get_perm_np(validPs, acl_perm_t(perm.bitmask)) == 1 {
                fullMask |= perm.bitmask
            }
        }
        return fullMask
    }

    // --- 以下辅助函数保持不变 ---
    
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
