import Foundation

/// Renders reading memory as a folder of plain Markdown, so it outlives the app.
/// Pure: returns relative path → file contents; the app writes them to disk.
public enum MemoryMarkdownExporter {
    /// Marks a folder as WhyText's own, so a re-export may replace it.
    public static let markerFileName = ".whytext-export"

    public static var folderName: String { L10n.t("WhyText 阅读记忆") }

    public static func render(
        records: [LookupRecord],
        exportedAt: Date,
        timeZone: TimeZone = .current
    ) -> [String: String] {
        let dates = DateFormats(timeZone: timeZone)
        var files: [String: String] = [:]
        files[markerFileName] = ""
        files["README.md"] = readme(recordCount: records.count, exportedAt: exportedAt, dates: dates)

        let termsFolder = L10n.t("词条")
        for (name, group) in termFiles(records) {
            files["\(termsFolder)/\(name).md"] = termPage(group, dates: dates)
        }

        let logFolder = L10n.t("日志")
        let byMonth = Dictionary(grouping: records) { dates.month.string(from: $0.date) }
        for (month, monthRecords) in byMonth {
            files["\(logFolder)/\(month).md"] = monthPage(month, records: monthRecords, dates: dates)
        }
        return files
    }

    /// Safe for any file system WhyText runs on, and never a hidden file.
    public static func fileName(for term: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?*\"<>|").union(.newlines).union(.controlCharacters)
        let spaced = term.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
        var name = spaced
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        while name.hasPrefix(".") { name.removeFirst() }
        name = String(name.prefix(80)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "untitled" : name
    }

    // MARK: - Files

    private static func readme(recordCount: Int, exportedAt: Date, dates: DateFormats) -> String {
        """
        # \(folderName)

        \(L10n.t("这是 WhyText 导出的阅读记录：查过的词、出处和结果。"))

        - \(L10n.f("导出时间：%@", dates.minute.string(from: exportedAt)))
        - \(L10n.f("记录总数：%@", String(recordCount)))
        - \(L10n.t("「词条」按词归类短的查询；「日志」按月列出全部记录。"))

        """
    }

    /// Short lookups grouped by term key, each under a unique file name.
    private static func termFiles(_ records: [LookupRecord]) -> [(String, [LookupRecord])] {
        let groups = Dictionary(grouping: records.filter { $0.termKey != nil }) { $0.termKey! }
        var taken = Set<String>()
        var result: [(String, [LookupRecord])] = []
        // Sorted so the same records always get the same names.
        for key in groups.keys.sorted() {
            let group = groups[key]!.sorted { $0.date > $1.date }
            let base = fileName(for: displayTerm(group))
            var name = base
            var suffix = 2
            // Case-insensitive: the default macOS file system is.
            while taken.contains(name.lowercased()) {
                name = "\(base) (\(suffix))"
                suffix += 1
            }
            taken.insert(name.lowercased())
            result.append((name, group))
        }
        return result
    }

    /// The most recent spelling, trimmed the way the term key was.
    private static func displayTerm(_ newestFirst: [LookupRecord]) -> String {
        newestFirst[0].sourceText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
    }

    private static func termPage(_ newestFirst: [LookupRecord], dates: DateFormats) -> String {
        let term = displayTerm(newestFirst)
        let sessions = Set(newestFirst.map(\.sessionID)).count
        var lines = [
            "---",
            "term: \(yamlString(term))",
            "count: \(sessions)",
            "first_seen: \(dates.day.string(from: newestFirst.last!.date))",
            "last_seen: \(dates.day.string(from: newestFirst[0].date))",
            "---",
            "",
            "# \(term)",
            "",
        ]
        for record in newestFirst {
            lines.append("## \(headingParts(record, date: dates.day.string(from: record.date)))")
            lines.append("")
            lines.append(contentsOf: sourceLines(record, highlight: record.sourceText))
            lines.append(record.resultText.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func monthPage(_ month: String, records: [LookupRecord], dates: DateFormats) -> String {
        var lines = ["# \(month)", ""]
        for record in records.sorted(by: { $0.date < $1.date }) {
            lines.append("### \(headingParts(record, date: dates.dayTime.string(from: record.date)))")
            lines.append("")
            lines.append(contentsOf: sourceLines(record, highlight: nil))
            lines.append(quote(record.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)))
            lines.append("")
            lines.append(record.resultText.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
            lines.append("---")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Pieces

    private static func headingParts(_ record: LookupRecord, date: String) -> String {
        var parts = [date, record.action == "explain" ? L10n.t("解释") : L10n.t("翻译")]
        if let app = nonEmpty(record.source.appName) { parts.append(app) }
        return parts.joined(separator: " · ")
    }

    /// The "from" line and, when known, the quoted sentence; each block ends with a blank line.
    private static func sourceLines(_ record: LookupRecord, highlight: String?) -> [String] {
        var lines: [String] = []
        let title = nonEmpty(record.source.windowTitle)
        let location = nonEmpty(record.source.documentURL).map(displayLocation)
        let from: String? = switch (title, location) {
        case let (title?, location?) where title == location: title
        case let (title?, location?): "\(title) — \(location)"
        case let (title?, nil): title
        case let (nil, location?): location
        case (nil, nil): nil
        }
        if let from {
            lines.append(L10n.f("**来源**：%@", from))
            lines.append("")
        }
        if let sentence = nonEmpty(record.source.sentence) {
            lines.append(quote(highlight.map { bold($0, in: sentence) } ?? sentence))
            lines.append("")
        }
        return lines
    }

    /// Web addresses as-is; local documents by file name only.
    private static func displayLocation(_ url: String) -> String {
        guard let parsed = URL(string: url), parsed.isFileURL else { return url }
        return parsed.lastPathComponent
    }

    /// Bolds the first case-insensitive occurrence of `term` in `sentence`.
    private static func bold(_ term: String, in sentence: String) -> String {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let range = sentence.range(of: trimmed, options: .caseInsensitive) else { return sentence }
        return sentence.replacingCharacters(in: range, with: "**\(sentence[range])**")
    }

    private static func quote(_ text: String) -> String {
        text.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
    }

    private static func yamlString(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private struct DateFormats {
        let day: DateFormatter
        let dayTime: DateFormatter
        let minute: DateFormatter
        let month: DateFormatter

        init(timeZone: TimeZone) {
            func make(_ format: String) -> DateFormatter {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone
                formatter.dateFormat = format
                return formatter
            }
            day = make("yyyy-MM-dd")
            dayTime = make("MM-dd HH:mm")
            minute = make("yyyy-MM-dd HH:mm")
            month = make("yyyy-MM")
        }
    }
}
