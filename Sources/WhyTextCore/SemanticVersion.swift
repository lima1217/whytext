import Foundation

/// Dotted numeric version ("0.2.3", "v1.0"), compared component by component with
/// missing components treated as zero. Pre-release suffixes are not supported.
public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" {
            trimmed.removeFirst()
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var components: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        self.components = components
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
