//
//  Models.swift
//  ACL Reader New
//
//  Created by tyz on 12/27/25.
//  Refactored by CodeX on 12/30/25.
//

import Foundation

// 权限位定义
enum ACLPermission: String, CaseIterable, Identifiable, Sendable {
    case readData = "读取数据", writeData = "写入数据", execute = "执行"
    case delete = "删除", appendData = "追加数据", deleteChild = "删除子项"
    case readAttr = "读取属性", writeAttr = "写入属性", readExAttr = "读取扩展属性"
    case writeExAttr = "写入扩展属性", readSecurity = "读取安全设置"
    case writeSecurity = "修改安全设置", changeOwner = "修改所有者"
    
    // [修改] 枚举里叫 permissionBitmask，明确这是定义的源头
    var permissionBitmask: UInt32 {
        switch self {
        case .readData: return 0x00000002
        case .writeData: return 0x00000004
        case .execute: return 0x00000008
        case .delete: return 0x00000010
        case .appendData: return 0x00000020
        case .deleteChild: return 0x00000040
        case .readAttr: return 0x00000080
        case .writeAttr: return 0x00000100
        case .readExAttr: return 0x00000200
        case .writeExAttr: return 0x00000400
        case .readSecurity: return 0x00000800
        case .writeSecurity: return 0x00001000
        case .changeOwner: return 0x00002000
        }
    }
    var id: String { self.rawValue }
}

// 标志位定义
enum ACEFlag: String, CaseIterable, Identifiable, Sendable {
    case fileInherit = "遗传至文件"
    case dirInherit = "遗传至目录"
    case limitInherit = "不深层遗传"
    case onlyInherit = "仅作为遗产"
    
    // [修改] 枚举里叫 flagBitmask
    var flagBitmask: UInt32 {
        switch self {
        case .fileInherit: return 0x00000020
        case .dirInherit: return 0x00000040
        case .limitInherit: return 0x00000080
        case .onlyInherit: return 0x00000100
        }
    }
    var id: String { self.rawValue }
}

// ACE 条目模型
struct ACEEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let name: String
    let uuidString: String
    let isGroup: Bool
    let type: String
    let permissions: [String]
    let flags: [String]
    
    // [修改] 这里按你的要求，去掉了 "Bit"，名字更清爽
    let permissionMask: UInt32
    let flagMask: UInt32
    
    let isInherited: Bool
    var inheritanceDepth: Int
    var sourcePath: String
    let index: Int
    
    var isHeuristicMatch: Bool = false
    var matchStatus: String = ""
    var isSystemInterrupted: Bool = false
}
