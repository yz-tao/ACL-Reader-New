//
//  Models.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//

import Foundation

// 权限位定义：对应 macOS 系统底层的访问权限
enum ACLPermission: String, CaseIterable, Identifiable, Sendable {
    case readData = "读取数据", writeData = "写入数据", execute = "执行"
    case delete = "删除", appendData = "追加数据", deleteChild = "删除子项"
    case readAttr = "读取属性", writeAttr = "写入属性", readExAttr = "读取扩展属性"
    case writeExAttr = "写入扩展属性", readSecurity = "读取安全设置"
    case writeSecurity = "修改安全设置", changeOwner = "修改所有者"
    
    var bitmask: UInt32 {
        switch self {
        case .readData: return 0x00000002          // ACL_READ_DATA
        case .writeData: return 0x00000004         // ACL_WRITE_DATA
        case .execute: return 0x00000008           // ACL_EXECUTE
        case .delete: return 0x00000010            // ACL_DELETE
        case .appendData: return 0x00000020        // ACL_APPEND_DATA
        case .deleteChild: return 0x00000040       // ACL_DELETE_CHILD
        case .readAttr: return 0x00000080          // ACL_READ_ATTRIBUTES
        case .writeAttr: return 0x00000100         // ACL_WRITE_ATTRIBUTES
        case .readExAttr: return 0x00000200        // ACL_READ_EXTATTRIBUTES
        case .writeExAttr: return 0x00000400       // ACL_WRITE_EXTATTRIBUTES
        case .readSecurity: return 0x00000800      // ACL_READ_SECURITY
        case .writeSecurity: return 0x00001000     // ACL_WRITE_SECURITY
        case .changeOwner: return 0x00002000       // ACL_CHANGE_OWNER
        }
    }
    var id: String { self.rawValue }
}

// 标志位定义：决定权限如何向下遗传（这是之前建议增加的细节）
enum ACEFlag: String, CaseIterable, Identifiable, Sendable {
    case fileInherit = "遗传至文件"
    case dirInherit = "遗传至目录"
    case limitInherit = "不深层遗传"
    case onlyInherit = "仅作为遗产"
    
    var bitmask: UInt32 {
        switch self {
        case .fileInherit: return 0x00000020      // ACL_ENTRY_FILE_INHERIT (原 0x10 是错的，那是 INHERITED)
        case .dirInherit: return 0x00000040       // ACL_ENTRY_DIRECTORY_INHERIT
        case .limitInherit: return 0x00000080     // ACL_ENTRY_LIMIT_INHERIT
        case .onlyInherit: return 0x00000100      // ACL_ENTRY_ONLY_INHERIT
        }
    }
    var id: String { self.rawValue }
}

// ACE 条目模型：每一个权限记录的载体
struct ACEEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let name: String
    let uuidString: String
    let isGroup: Bool
    let type: String            // "Allow" 或 "Deny"
    let permissions: [String]
    let flags: [String]         // 遗传标志位
    let rawBitmask: UInt32
    let isInherited: Bool
    var inheritanceDepth: Int   // 0: 本地定义, 1+: 溯源深度, 999: 未知
    var sourcePath: String
    let index: Int
    
    // --- 【新增插入点】 ---
    var isHeuristicMatch: Bool = false // 标记是否通过“子集匹配”补偿找回
    var matchStatus: String = ""       // 存储匹配状态描述（用于调试或UI展示）
    // --- 【最小化新增：标记是否因拦截而中断】 ---
    var isSystemInterrupted: Bool = false
}

