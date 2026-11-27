import AppKit
import Foundation

enum SyntaxHighlighter {
    private static let baseColor = NSColor(red: 0.847, green: 0.863, blue: 0.910, alpha: 1.0) // #D8DCE8
    private static let kwColor = NSColor(red: 0.776, green: 0.471, blue: 0.867, alpha: 1.0)   // #C678DD
    private static let strColor = NSColor(red: 0.596, green: 0.765, blue: 0.475, alpha: 1.0)  // #98C379
    private static let comColor = NSColor(red: 0.424, green: 0.451, blue: 0.533, alpha: 1.0)  // #6C7388
    private static let numColor = NSColor(red: 0.820, green: 0.604, blue: 0.400, alpha: 1.0)  // #D19A66
    private static let typeColor = NSColor(red: 0.898, green: 0.753, blue: 0.482, alpha: 1.0) // #E5C07B
    private static let fnColor = NSColor(red: 0.380, green: 0.686, blue: 0.937, alpha: 1.0)   // #61AFEF
    private static let propColor = NSColor(red: 0.337, green: 0.714, blue: 0.761, alpha: 1.0) // #56B6C2
    private static let tagColor = NSColor(red: 0.878, green: 0.424, blue: 0.459, alpha: 1.0)  // #E06C75

    static let editorFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)

    static func defaultParagraphStyle() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.55
        p.paragraphSpacing = 3
        return p
    }

    static func defaultTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: editorFont,
            .foregroundColor: baseColor,
            .paragraphStyle: defaultParagraphStyle()
        ]
    }

    static func apply(to storage: NSTextStorage, fileKind: FileKind) {
        let text = storage.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else { return }

        storage.beginEditing()
        storage.setAttributes(defaultTypingAttributes(), range: fullRange)

        // Skip heavy regex passes on huge files (> 180K chars) to keep typing instantaneous
        guard fullRange.length <= 180_000 else {
            storage.endEditing()
            return
        }

        switch fileKind {
        case .code(let rawLang):
            highlightCode(storage: storage, text: text, fullRange: fullRange, language: rawLang)
        case .markdown, .image:
            break
        }

        storage.endEditing()
    }

    private static func highlightCode(
        storage: NSTextStorage,
        text: String,
        fullRange: NSRange,
        language: String
    ) {
        let l = language.lowercased().trimmingCharacters(in: .whitespaces)
        if l.isEmpty || l == "text" || l == "txt" || l == "log" { return }

        let alias: [String: String] = [
            "py": "python", "javascript": "js", "jsx": "js", "mjs": "js", "cjs": "js",
            "typescript": "ts", "tsx": "ts", "sh": "bash", "zsh": "bash", "shell": "bash",
            "command": "bash", "rs": "rust", "kt": "kotlin", "kts": "kotlin",
            "cpp": "c", "cc": "c", "cxx": "c", "h": "c", "hpp": "c", "m": "c", "mm": "c",
            "rb": "ruby", "scss": "css", "less": "css", "htm": "html"
        ]
        let key = alias[l] ?? l

        if ["html", "xml", "svg", "vue", "svelte", "plist"].contains(key) {
            applyRegex("</?[A-Za-z][A-Za-z0-9:-]*", color: tagColor, storage: storage, text: text, range: fullRange)
            applyRegex("\\b[A-Za-z-:]+(?==)", color: propColor, storage: storage, text: text, range: fullRange)
            applyRegex("\"[^\"\\n]*\"|'[^'\\n]*'", color: strColor, storage: storage, text: text, range: fullRange)
            applyRegex("<!--[\\s\\S]*?-->", color: comColor, storage: storage, text: text, range: fullRange)
            return
        }

        if ["yaml", "yml", "toml", "ini", "conf", "env"].contains(key) {
            applyRegex("(?m)^\\s*[A-Za-z0-9_.-]+(?=\\s*[:=])", color: propColor, storage: storage, text: text, range: fullRange)
            applyRegex("\\b(true|false|null|yes|no)\\b", color: kwColor, options: [.caseInsensitive], storage: storage, text: text, range: fullRange)
            applyRegex("\\b-?\\d+(?:\\.\\d+)?\\b", color: numColor, storage: storage, text: text, range: fullRange)
            applyRegex("\"[^\"\\n]*\"|'[^'\\n]*'", color: strColor, storage: storage, text: text, range: fullRange)
            applyRegex("#[^\\n]*", color: comColor, storage: storage, text: text, range: fullRange)
            return
        }

        if key == "json" {
            applyRegex("\\b(true|false|null)\\b", color: kwColor, storage: storage, text: text, range: fullRange)
            applyRegex("\\b-?\\d+(?:\\.\\d+)?\\b", color: numColor, storage: storage, text: text, range: fullRange)
            applyRegex("\"(?:\\\\.|[^\"\\\\\\n])*\"", color: strColor, storage: storage, text: text, range: fullRange)
            applyRegex("\"(?:\\\\.|[^\"\\\\\\n])*\"(?=\\s*:)", color: propColor, storage: storage, text: text, range: fullRange)
            return
        }

        // General programming languages
        applyRegex("\\b[A-Z][A-Za-z0-9_]+\\b", color: typeColor, storage: storage, text: text, range: fullRange)
        applyRegex("\\b[a-z_][A-Za-z0-9_]*(?=\\s*\\()", color: fnColor, storage: storage, text: text, range: fullRange)
        applyRegex("\\b-?\\d+(?:\\.\\d+)?\\b", color: numColor, storage: storage, text: text, range: fullRange)

        if let kw = keywordPatterns[key] {
            let opts: NSRegularExpression.Options = (key == "sql") ? [.caseInsensitive] : []
            applyRegex("\\b(\(kw))\\b", color: kwColor, options: opts, storage: storage, text: text, range: fullRange)
        }

        // Strings (override keywords/numbers inside strings)
        applyRegex("\"(?:\\\\.|[^\"\\\\\\n])*\"|'(?:\\\\.|[^'\\\\\\n])*'|`(?:\\\\.|[^`\\\\])*`", color: strColor, storage: storage, text: text, range: fullRange)

        // Comments (highest priority)
        if ["python", "bash", "ruby"].contains(key) {
            applyRegex("#[^\\n]*", color: comColor, storage: storage, text: text, range: fullRange)
        } else if key == "sql" {
            applyRegex("--[^\\n]*|/\\*[\\s\\S]*?\\*/", color: comColor, storage: storage, text: text, range: fullRange)
        } else {
            applyRegex("//[^\\n]*|/\\*[\\s\\S]*?\\*/", color: comColor, storage: storage, text: text, range: fullRange)
        }
    }

    private static var regexCache: [String: NSRegularExpression] = [:]

    private static func applyRegex(
        _ pattern: String,
        color: NSColor,
        options: NSRegularExpression.Options = [],
        storage: NSTextStorage,
        text: String,
        range: NSRange
    ) {
        let cacheKey = "\(options.rawValue)::\(pattern)"
        let regex: NSRegularExpression
        if let cached = regexCache[cacheKey] {
            regex = cached
        } else if let compiled = try? NSRegularExpression(pattern: pattern, options: options) {
            regexCache[cacheKey] = compiled
            regex = compiled
        } else {
            return
        }
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let r = match?.range, r.length > 0 {
                storage.addAttribute(.foregroundColor, value: color, range: r)
            }
        }
    }

    private static let keywordPatterns: [String: String] = [
        "swift": "import|struct|class|enum|protocol|extension|func|var|let|if|else|guard|return|switch|case|default|for|in|while|do|try|catch|throw|throws|async|await|public|private|internal|fileprivate|final|static|override|init|self|Self|true|false|nil|some|weak|mutating|actor|typealias",
        "python": "import|from|as|def|class|return|if|elif|else|for|in|while|try|except|finally|with|lambda|yield|pass|break|continue|True|False|None|and|or|not|is|async|await|global|nonlocal",
        "js": "import|export|from|default|const|let|var|function|class|extends|return|if|else|switch|case|for|of|in|while|try|catch|finally|new|this|true|false|null|undefined|async|await|typeof|instanceof",
        "ts": "import|export|from|default|const|let|var|function|class|interface|type|enum|extends|implements|return|if|else|switch|case|for|of|in|while|try|catch|finally|new|this|true|false|null|undefined|async|await|readonly|public|private|protected|keyof|as",
        "java": "package|import|public|private|protected|class|interface|enum|extends|implements|static|final|void|return|if|else|switch|case|default|for|while|do|try|catch|finally|throw|throws|new|this|super|true|false|null|int|long|double|boolean|char",
        "kotlin": "package|import|class|interface|object|data|sealed|enum|fun|val|var|if|else|when|for|in|while|return|try|catch|finally|throw|true|false|null|private|public|internal|override|companion|suspend",
        "c": "include|define|ifdef|endif|struct|union|enum|typedef|const|static|extern|void|int|long|short|char|float|double|unsigned|signed|bool|return|if|else|switch|case|default|for|while|do|break|continue|sizeof|NULL|true|false|class|namespace|template|typename|public|private|protected|virtual|override|auto|nullptr",
        "rust": "use|mod|pub|fn|struct|enum|impl|trait|let|mut|const|if|else|match|for|in|while|loop|return|async|await|true|false|self|Self|where|crate|super",
        "go": "package|import|func|type|struct|interface|var|const|if|else|switch|case|default|for|range|return|go|defer|chan|map|select|true|false|nil",
        "ruby": "def|end|class|module|if|elsif|else|unless|case|when|while|until|for|do|return|yield|begin|rescue|ensure|true|false|nil|require|include|attr_accessor",
        "php": "function|class|interface|trait|extends|implements|public|private|protected|static|return|if|elseif|else|switch|case|foreach|for|while|try|catch|new|true|false|null|echo|use|namespace",
        "bash": "if|then|else|elif|fi|for|do|done|while|case|esac|function|export|local|return|echo|cd|ls|rm|cp|mv|mkdir|grep|awk|sed|set|exit",
        "sql": "SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|BY|ORDER|HAVING|LIMIT|AS|AND|OR|NOT|NULL|DISTINCT|PRIMARY|KEY|INDEX",
        "css": "display|position|color|background|margin|padding|border|font-size|font-family|flex|grid|width|height|align-items|justify-content|gap|border-radius|overflow|z-index|opacity|transition|transform"
    ]
}
