//
//  ACLScanner.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//  Refactored by CodeX on 12/30/25.
//

import Foundation
import Darwin

// 遗传资格验证器
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
    
    func canInherit(parent: ACEEntry, depth: Int) -> Bool {
        // [修改] parent.flagMask (短名) & ACEFlag.flagBitmask (长名)
        // 逻辑清晰：用 Entry 的实际值 去匹配 Flag 的定义值
        
        let hasFI = (parent.flagMask & ACEFlag.fileInherit.flagBitmask) != 0
        let hasDI = (parent.flagMask & ACEFlag.dirInherit.flagBitmask) != 0
        
        if isTargetDirectory {
            guard hasDI else { return false }
        } else {
            guard hasFI else { return false }
        }
        
        let hasLI = (parent.flagMask & ACEFlag.limitInherit.flagBitmask) != 0
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
            guard !parent.isInherited,
                  parent.uuidString == target.uuidString,
                  parent.type == target.type else { return false }
            
            guard validator.canInherit(parent: parent, depth: currentDepth) else { return false }
            
            // [修改] 使用 permissionMask (短名)
            let childMask = target.permissionMask
            let parentMask = parent.permissionMask
            
            switch grade {
            case .strict:
                return childMask == parentMask
            case .compatible:
                return (childMask & parentMask) == childMask
            }
        }
    }

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
                    // [修改] 使用函数计算并填入 Mask (短名)
                    permissionMask: getPermissionMask(e),
                    flagMask: getFlagMask(e),
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

    // [修改] 提取函数使用 permissionBitmask (长名)
    private static func getPermissionMask(_ entry: acl_entry_t) -> UInt32 {
        var ps: acl_permset_t? = nil
        acl_get_permset(entry, &ps)
        guard let validPs = ps else { return 0 }
        var mask: UInt32 = 0
        for perm in ACLPermission.allCases {
            if acl_get_perm_np(validPs, acl_perm_t(perm.permissionBitmask)) == 1 {
                mask |= perm.permissionBitmask
            }
        }
        return mask
    }
    
    // [修改] 提取函数使用 flagBitmask (长名)
    private static func getFlagMask(_ entry: acl_entry_t) -> UInt32 {
        var fs: acl_flagset_t? = nil
        acl_get_flagset_np(UnsafeMutableRawPointer(entry), &fs)
        guard let validFs = fs else { return 0 }
        var mask: UInt32 = 0
        for flag in ACEFlag.allCases {
            if acl_get_flag_np(validFs, acl_flag_t(flag.flagBitmask)) == 1 {
                mask |= flag.flagBitmask
            }
        }
        return mask
    }
    
    // --- 辅助函数同步更新 ---

    private static func parsePermissions(_ entry: acl_entry_t) -> [String] {
        var ps: acl_permset_t? = nil
        acl_get_permset(entry, &ps)
        guard let validPs = ps else { return [] }
        return ACLPermission.allCases.compactMap { perm in
            acl_get_perm_np(validPs, acl_perm_t(perm.permissionBitmask)) == 1 ? perm.rawValue : nil
        }
    }

    private static func parseFlags(_ entry: acl_entry_t) -> [String] {
        var fs: acl_flagset_t? = nil
        acl_get_flagset_np(UnsafeMutableRawPointer(entry), &fs)
        guard let validFs = fs else { return [] }
        return ACEFlag.allCases.compactMap { flag in
            acl_get_flag_np(validFs, acl_flag_t(flag.flagBitmask)) == 1 ? flag.rawValue : nil
        }
    }

    // (其他辅助函数保持不变)
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
