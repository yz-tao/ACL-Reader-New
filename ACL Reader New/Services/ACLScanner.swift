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
            // 该权限必须具备 directory_inherit (DI) 才能穿透中间的目录层级到达这里。
            // 如果没有 DI，这个权限在半路（父目录）就已经断掉了。
            if depth > 1 {
                guard hasDI else { return false }
            }
        }
        
        let hasLI = (parent.flagMask & ACEFlag.limitInherit.flagBitmask) != 0
        if hasLI && depth > 1 { return false }
        
        return true
    }
    
    // [新增] 检查子项的继承标记是否符合父项的遗传逻辑
    func checkFlagConsistency(parent: ACEEntry, child: ACEEntry) -> Bool {
        // 定义遗传相关的位掩码：file_inherit | directory_inherit
        // 注意：only_inherit (0x100) 不参与比对，因为它在遗传时会被剥离，不应出现在子项中
        let inheritMask = ACEFlag.fileInherit.flagBitmask | ACEFlag.dirInherit.flagBitmask
        
        let childGenetics = child.flagMask & inheritMask
        
        if !isTargetDirectory {
            // [逻辑点 1] 目标是文件
            // 文件通常作为叶子节点，系统默认继承规则下不应具备遗传给下一代的能力 (即不应有 FI/DI)。
            // 如果文件上有 FI/DI，说明该文件可能被手动修改过 Flag，不再被视为“纯净”的继承项。
            return childGenetics == 0
        } else {
            // [逻辑点 2] 目标是目录
            let parentGenetics = parent.flagMask & inheritMask
            let parentHasLI = (parent.flagMask & ACEFlag.limitInherit.flagBitmask) != 0
            
            if parentHasLI {
                // 如果父项限制了不深层遗传 (limit_inherit)，子目录应该“绝育”，不再带有遗传标
                return childGenetics == 0
            } else {
                // 正常遗传：子目录的遗传标记 (FI/DI) 必须与父项完全一致（基因复制）
                return childGenetics == parentGenetics
            }
        }
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
            
            // [新增] 这一行是本次修改的核心：在对比权限位之前，先验证继承标记的一致性
            // 只有当“基因”对得上（Flags 演化逻辑正确），才去比对“长相”（Permission Mask）
            guard validator.checkFlagConsistency(parent: parent, child: target) else { return false }
            
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
                // [修改点 1]：获取 UUID 字符串
                let uuidStr = getUUIDString(e)
                                
                // [修改点 2]：一次性解析出名字和是否为组，不再分别调用
                let identity = resolveIdentity(entry: e, uuidString: uuidStr)
                
                let inherited = checkIsInherited(e)
                results.append(ACEEntry(
                    name: identity.name,       // 使用解析出的名字
                    uuidString: uuidStr,
                    isGroup: identity.isGroup, // 使用解析出的正确类型
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
    
    // [修改点 3]：替代原有的 resolveName，同时返回 (name, isGroup)
    private static func resolveIdentity(entry: acl_entry_t, uuidString: String) -> (name: String, isGroup: Bool) {
        // 尝试从 UUID 解析
        guard let uuid = UUID(uuidString: uuidString) else {
            return ("无效 UUID", false)
        }
            
        var uuidBytes = uuid.uuid
        var id: uid_t = 0
        var type: Int32 = 0
        
        // 调用底层 API 查询身份
        let result = withUnsafePointer(to: &uuidBytes) { ptr -> Int32 in
            let rawPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt8.self)
            return mbr_uuid_to_id(rawPtr, &id, &type)
        }
            
        if result == 0 {
            if type == ID_TYPE_GID {
                // 是群组
                if let g = getgrgid(id) {
                    return (String(cString: g.pointee.gr_name), true)
                }
                return ("GID: \(id)", true)
            } else if type == ID_TYPE_UID {
                // 是用户
                if let p = getpwuid(id) {
                    return (String(cString: p.pointee.pw_name), false)
                }
                return ("UID: \(id)", false)
            }
        }
            
        // 如果查不到（比如未知的 UUID），默认当做非组处理，或者你可以根据需求调整
        return ("未知: \(uuidString.prefix(8))", false)
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
