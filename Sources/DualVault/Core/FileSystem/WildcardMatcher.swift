import Foundation

/// 通配符匹配：* 任意长度（含 0），? 单字符。默认大小写不敏感（TC 习惯）。
enum WildcardMatcher {

    static func matches(_ name: String, pattern: String, caseSensitive: Bool = false) -> Bool {
        let n = Array(caseSensitive ? name : name.lowercased())
        let p = Array(caseSensitive ? pattern : pattern.lowercased())
        return match(n, p)
    }

    /// 双指针贪心：* 尽量多吞，回溯。
    private static func match(_ n: [Character], _ p: [Character]) -> Bool {
        var ni = 0, pi = 0, star: Int? = nil, mark = 0
        while ni < n.count {
            if pi < p.count && (p[pi] == "?" || p[pi] == n[ni]) {
                ni += 1; pi += 1
            } else if pi < p.count && p[pi] == "*" {
                star = pi; pi += 1; mark = ni
            } else if let s = star {
                pi = s + 1; mark += 1; ni = mark
            } else {
                return false
            }
        }
        while pi < p.count && p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    /// 从模式提取"必含子串"（用于快速预过滤，非正确性关键）。
    static func literalSegments(of pattern: String) -> [String] {
        pattern.split(separator: "*").map(String.init).filter { !$0.isEmpty }
    }
}
