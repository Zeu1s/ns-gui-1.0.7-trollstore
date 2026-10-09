//
//  LossyJSONDecoding.swift
//  nodeseek
//

import Foundation

/// 站点接口的字段命名和类型都不稳定（同名不同 key、数字有时是字符串、
/// 布尔有时是 0/1 或 "true"）。这些宽松解码辅助原先在通知记录的两个结构体里
/// 各抄了一份，合并到这里，避免两边继续分叉。
enum LossyJSONDecoding {
    /// 按给定 key 顺序取第一个非空字符串。
    nonisolated static func optionalString<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key),
               value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return value
            }
        }
        return nil
    }

    /// 按给定 key 顺序取第一个正整数；数字以字符串给出时也能识别。
    nonisolated static func optionalInt<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key), value > 0 {
                return value
            }
            if let raw = try? container.decodeIfPresent(String.self, forKey: key),
               let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 {
                return value
            }
        }
        return nil
    }

    /// 按给定 key 顺序取第一个标志位，接受 Int / Bool / "true" / "false" 四种形态。
    /// 与 `optionalInt` 不同，这里 0 是合法值（表示"未读"），所以不做正数过滤。
    nonisolated static func optionalFlag<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
                return value ? 1 : 0
            }
            if let raw = try? container.decodeIfPresent(String.self, forKey: key) {
                if let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return value
                }
                if raw.lowercased() == "true" {
                    return 1
                }
                if raw.lowercased() == "false" {
                    return 0
                }
            }
        }
        return nil
    }
}
