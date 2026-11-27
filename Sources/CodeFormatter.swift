import Foundation

enum CodeFormatter {
    static func format(_ input: String, language: String) -> (formatted: String, label: String) {
        let lang = language.lowercased()
        switch lang {
        case "json":
            if let pretty = formatJSON(input) {
                return (pretty, "JSON")
            }
            return (formatBraceCode(input), "JSON")
        case "html", "htm", "xml", "svg":
            return (formatXML(input), lang.uppercased())
        case "swift", "js", "javascript", "ts", "typescript", "jsx", "tsx",
             "java", "kt", "kotlin", "c", "cpp", "cc", "h", "hpp", "m", "mm",
             "go", "rs", "rust", "css", "scss", "less", "php":
            return (formatBraceCode(input), lang.uppercased())
        case "md", "markdown", "mdx":
            return (formatMarkdown(input), "Markdown")
        default:
            return (normalizeWhitespace(input), lang.isEmpty ? "文本" : lang.uppercased())
        }
    }

    private static func formatJSON(_ input: String) -> String? {
        guard let data = input.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        guard JSONSerialization.isValidJSONObject(obj),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: obj,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let str = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return str + "\n"
    }

    private static func formatBraceCode(_ input: String) -> String {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var result: [String] = []
        var indentLevel = 0
        var inBlockComment = false
        let indentUnit = "    "

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if result.last != "" {
                    result.append("")
                }
                continue
            }

            // Adjust leading closing braces/brackets
            var leadingClose = 0
            for ch in trimmed {
                if ch == "}" || ch == "]" || ch == ")" {
                    leadingClose += 1
                } else {
                    break
                }
            }

            let effectiveIndent = max(0, indentLevel - leadingClose)
            result.append(String(repeating: indentUnit, count: effectiveIndent) + trimmed)

            // Count net brace delta ignoring strings and comments
            let delta = netBraceDelta(in: trimmed, inBlockComment: &inBlockComment)
            indentLevel = max(0, indentLevel + delta)
        }

        while result.last == "" {
            result.removeLast()
        }
        return result.joined(separator: "\n") + (result.isEmpty ? "" : "\n")
    }

    private static func netBraceDelta(in line: String, inBlockComment: inout Bool) -> Int {
        let chars = Array(line)
        var i = 0
        var delta = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var inBacktick = false

        while i < chars.count {
            let c = chars[i]
            let next: Character? = (i + 1 < chars.count) ? chars[i + 1] : nil

            if inBlockComment {
                if c == "*" && next == "/" {
                    inBlockComment = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }

            if inSingleQuote {
                if c == "\\" { i += 2; continue }
                if c == "'" { inSingleQuote = false }
                i += 1
                continue
            }

            if inDoubleQuote {
                if c == "\\" { i += 2; continue }
                if c == "\"" { inDoubleQuote = false }
                i += 1
                continue
            }

            if inBacktick {
                if c == "\\" { i += 2; continue }
                if c == "`" { inBacktick = false }
                i += 1
                continue
            }

            if c == "/" && next == "/" {
                break
            }
            if c == "/" && next == "*" {
                inBlockComment = true
                i += 2
                continue
            }
            if c == "'" { inSingleQuote = true; i += 1; continue }
            if c == "\"" { inDoubleQuote = true; i += 1; continue }
            if c == "`" { inBacktick = true; i += 1; continue }

            if c == "{" || c == "[" {
                delta += 1
            } else if c == "}" || c == "]" {
                delta -= 1
            }
            i += 1
        }
        return delta
    }

    private static func formatXML(_ input: String) -> String {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        // Split adjacent tags onto separate lines while preserving content
        let spaced = normalized.replacingOccurrences(
            of: ">\\s*<",
            with: ">\n<",
            options: .regularExpression
        )
        let lines = spaced.components(separatedBy: "\n")
        var result: [String] = []
        var indentLevel = 0
        let indentUnit = "  "
        let voidTags: Set<String> = [
            "area", "base", "br", "col", "embed", "hr", "img", "input",
            "link", "meta", "param", "source", "track", "wbr"
        ]

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let isClosing = trimmed.hasPrefix("</")
            if isClosing {
                indentLevel = max(0, indentLevel - 1)
            }

            result.append(String(repeating: indentUnit, count: indentLevel) + trimmed)

            let isCommentOrDecl = trimmed.hasPrefix("<!--") || trimmed.hasPrefix("<?") || trimmed.hasPrefix("<!")
            let isSelfClosing = trimmed.hasSuffix("/>")
            let hasInlineClosing = !isClosing && trimmed.contains("</")

            if !isClosing && !isCommentOrDecl && !isSelfClosing && !hasInlineClosing && trimmed.hasPrefix("<") {
                let tagName = trimmed.dropFirst()
                    .prefix { $0.isLetter || $0.isNumber || $0 == "-" }
                    .lowercased()
                if !tagName.isEmpty && !voidTags.contains(tagName) {
                    indentLevel += 1
                }
            }
        }
        return result.joined(separator: "\n") + (result.isEmpty ? "" : "\n")
    }

    private static func formatMarkdown(_ input: String) -> String {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var result: [String] = []
        var inCodeBlock = false
        var consecutiveBlanks = 0

        for rawLine in lines {
            let trimmedTrailing = rawLine.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
            if trimmedTrailing.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                consecutiveBlanks = 0
                result.append(trimmedTrailing)
                continue
            }
            if inCodeBlock {
                result.append(trimmedTrailing)
                continue
            }
            if trimmedTrailing.isEmpty {
                consecutiveBlanks += 1
                if consecutiveBlanks <= 1 {
                    result.append("")
                }
                continue
            }
            consecutiveBlanks = 0
            // Ensure space after ATX heading hashes
            if let range = trimmedTrailing.range(of: "^(#{1,6})([^#\\s])", options: .regularExpression) {
                let prefix = String(trimmedTrailing[range])
                let hashes = prefix.dropLast()
                let firstChar = prefix.last!
                let rest = trimmedTrailing[range.upperBound...]
                result.append("\(hashes) \(firstChar)\(rest)")
            } else {
                result.append(trimmedTrailing)
            }
        }
        while result.last == "" { result.removeLast() }
        return result.joined(separator: "\n") + (result.isEmpty ? "" : "\n")
    }

    private static func normalizeWhitespace(_ input: String) -> String {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(of: "\t", with: "    ")
                .replacingOccurrences(of: "[ ]+$", with: "", options: .regularExpression)
        }
        var trimmed = lines
        while trimmed.last == "" { trimmed.removeLast() }
        return trimmed.joined(separator: "\n") + (trimmed.isEmpty ? "" : "\n")
    }
}
