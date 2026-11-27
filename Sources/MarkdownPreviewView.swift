import AppKit
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let fileKind: FileKind
    let scrollFraction: Double
    let maxWidth: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.webView = webView
        context.coordinator.pendingMarkdown = markdown
        context.coordinator.pendingFileKind = fileKind
        context.coordinator.pendingMaxWidth = maxWidth
        webView.loadHTMLString(Self.htmlTemplate, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateContent(markdown, kind: fileKind)
        context.coordinator.updateScroll(scrollFraction)
        context.coordinator.updateMaxWidth(maxWidth)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isLoaded = false
        var pendingMarkdown: String = ""
        var pendingFileKind: FileKind = .markdown
        var pendingMaxWidth: Double = 0
        private var lastRenderedMarkdown: String = ""
        private var lastRenderedKind: FileKind?
        private var lastScrollFraction: Double = -1
        private var lastAppliedMaxWidth: Double = -1
        private var debounceWorkItem: DispatchWorkItem?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            applyMaxWidthNow(pendingMaxWidth)
            renderNow(pendingMarkdown, kind: pendingFileKind)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func updateContent(_ text: String, kind: FileKind) {
            pendingMarkdown = text
            pendingFileKind = kind
            guard isLoaded else { return }
            if text == lastRenderedMarkdown && kind == lastRenderedKind { return }

            debounceWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.renderNow(text, kind: kind)
            }
            debounceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
        }

        private func renderNow(_ text: String, kind: FileKind) {
            guard isLoaded, let webView = webView else { return }
            lastRenderedMarkdown = text
            lastRenderedKind = kind
            let base64 = Data(text.utf8).base64EncodedString()
            switch kind {
            case .markdown:
                webView.evaluateJavaScript("window.updateContent('\(base64)', 'markdown', '');", completionHandler: nil)
            case .code(let lang):
                let escapedLang = lang.replacingOccurrences(of: "'", with: "")
                webView.evaluateJavaScript("window.updateContent('\(base64)', 'code', '\(escapedLang)');", completionHandler: nil)
            case .image:
                break
            }
        }

        func updateScroll(_ fraction: Double) {
            guard isLoaded, let webView = webView else { return }
            if abs(fraction - lastScrollFraction) < 0.004 { return }
            lastScrollFraction = fraction
            webView.evaluateJavaScript("window.syncScroll(\(fraction));", completionHandler: nil)
        }

        func updateMaxWidth(_ width: Double) {
            pendingMaxWidth = width
            guard isLoaded else { return }
            if abs(width - lastAppliedMaxWidth) < 0.5 { return }
            applyMaxWidthNow(width)
        }

        private func applyMaxWidthNow(_ width: Double) {
            guard isLoaded, let webView = webView else { return }
            lastAppliedMaxWidth = width
            webView.evaluateJavaScript("window.setPreviewWidth(\(width));", completionHandler: nil)
        }
    }

    private static let htmlTemplate: String = #"""
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <style>
      :root {
        color-scheme: dark;
        --bg: #17171A;
        --surface: #202127;
        --border: #2C2E37;
        --text: #D6D8E0;
        --muted: #8B90A0;
        --accent: #7AA2F7;
        --code-bg: #111216;
      }
      * { box-sizing: border-box; }
      html, body {
        margin: 0;
        padding: 0;
        background: var(--bg);
        color: var(--text);
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Hiragino Sans GB", sans-serif;
        font-size: 14.5px;
        line-height: 1.75;
        -webkit-font-smoothing: antialiased;
      }
      #content {
        max-width: none;
        margin: 0 auto;
        padding: 28px 36px 72px;
        word-wrap: break-word;
      }
      h1, h2, h3, h4, h5, h6 {
        color: #EEF0F6;
        font-weight: 600;
        line-height: 1.35;
        margin: 1.4em 0 0.65em;
      }
      h1 { font-size: 1.85em; padding-bottom: 0.35em; border-bottom: 1px solid var(--border); margin-top: 0.2em; }
      h2 { font-size: 1.42em; padding-bottom: 0.25em; border-bottom: 1px solid rgba(255,255,255,0.06); }
      h3 { font-size: 1.18em; }
      p { margin: 0.75em 0; }
      a { color: var(--accent); text-decoration: none; }
      a:hover { text-decoration: underline; }
      strong { color: #F2F4FA; font-weight: 600; }
      em { color: #E2E5F0; }
      del { color: var(--muted); }
      hr { border: none; border-top: 1px solid var(--border); margin: 1.8em 0; }
      blockquote {
        margin: 1em 0;
        padding: 10px 16px;
        border-left: 3px solid var(--accent);
        background: rgba(122, 162, 247, 0.07);
        border-radius: 0 8px 8px 0;
        color: #B7BDD0;
      }
      blockquote p { margin: 0.25em 0; }
      ul, ol { padding-left: 1.6em; margin: 0.7em 0; }
      li { margin: 0.32em 0; }
      li.task-item { list-style: none; margin-left: -1.3em; display: flex; align-items: baseline; gap: 8px; }
      li.task-item input[type="checkbox"] { accent-color: var(--accent); transform: translateY(1px); pointer-events: none; }
      code {
        font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
        font-size: 0.88em;
        background: rgba(255, 255, 255, 0.08);
        color: #E6B87A;
        padding: 2px 6px;
        border-radius: 5px;
      }
      pre {
        position: relative;
        background: var(--code-bg);
        border: 1px solid var(--border);
        border-radius: 10px;
        padding: 14px 16px;
        overflow-x: auto;
        margin: 1.1em 0;
        line-height: 1.6;
      }
      pre .lang-badge {
        position: absolute;
        top: 8px;
        right: 12px;
        font-family: "SF Mono", Menlo, monospace;
        font-size: 11px;
        color: var(--muted);
        text-transform: lowercase;
        user-select: none;
      }
      pre code {
        background: transparent;
        color: #D8DCE8;
        padding: 0;
        border-radius: 0;
        font-size: 13px;
      }
      /* Full code file preview with line numbers */
      .code-file-view {
        background: var(--code-bg);
        border: 1px solid var(--border);
        border-radius: 10px;
        overflow: hidden;
      }
      .code-file-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 8px 14px;
        background: #1A1B21;
        border-bottom: 1px solid var(--border);
        font-family: "SF Mono", Menlo, monospace;
        font-size: 11.5px;
        color: var(--muted);
      }
      .code-file-body {
        overflow-x: auto;
        padding: 12px 0;
        font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
        font-size: 13px;
        line-height: 1.65;
      }
      .code-line {
        display: flex;
        padding: 0 16px 0 0;
      }
      .code-line:hover {
        background: rgba(255, 255, 255, 0.03);
      }
      .line-num {
        width: 52px;
        min-width: 52px;
        padding-right: 14px;
        text-align: right;
        color: #52576A;
        user-select: none;
      }
      .line-code {
        white-space: pre;
        color: #D8DCE8;
      }
      /* UML Class Diagram Container */
      .uml-box {
        background: #13141A;
        border: 1px solid var(--border);
        border-radius: 12px;
        padding: 18px;
        margin: 1.2em 0;
        overflow-x: auto;
        text-align: center;
      }
      .uml-box svg {
        max-width: 100%;
        height: auto;
        display: block;
        margin: 0 auto;
      }
      .uml-badge {
        display: inline-block;
        font-family: "SF Mono", Menlo, monospace;
        font-size: 10.5px;
        color: var(--muted);
        margin-bottom: 8px;
        letter-spacing: 0.04em;
      }
      table {
        width: 100%;
        border-collapse: collapse;
        margin: 1.2em 0;
        font-size: 0.94em;
        border-radius: 8px;
        overflow: hidden;
      }
      th, td {
        border: 1px solid var(--border);
        padding: 8px 12px;
        text-align: left;
      }
      th {
        background: var(--surface);
        color: #ECEFF6;
        font-weight: 600;
      }
      tr:nth-child(even) td {
        background: rgba(255, 255, 255, 0.02);
      }
      img {
        max-width: 100%;
        border-radius: 8px;
        margin: 0.6em 0;
      }
      .empty-hint {
        color: #585D70;
        font-size: 13.5px;
        text-align: center;
        padding: 64px 0;
      }
      /* Syntax highlight palette (Tokyo Night / One Dark inspired) */
      .tok-kw { color: #C678DD; }
      .tok-str { color: #98C379; }
      .tok-com { color: #676E82; font-style: italic; }
      .tok-num { color: #D19A66; }
      .tok-type { color: #E5C07B; }
      .tok-fn { color: #61AFEF; }
      .tok-prop { color: #56B6C2; }
      .tok-tag { color: #E06C75; }
    </style>
    </head>
    <body>
    <article id="content"></article>
    <script>
      function escapeHtml(str) {
        return str
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")
          .replace(/"/g, "&quot;");
      }

      function highlightCode(rawCode, lang) {
        const l = (lang || "").toLowerCase().trim();
        let code = escapeHtml(rawCode);
        if (!l || l === "text" || l === "txt" || l === "log") return code;

        const tokens = [];
        function stash(html) {
          const id = tokens.length;
          tokens.push(html);
          return `\u0000TOK${id}\u0000`;
        }

        // Comments
        if (["python", "py", "bash", "sh", "zsh", "shell", "command", "yaml", "yml", "toml", "ini", "conf", "env", "rb", "ruby"].includes(l)) {
          code = code.replace(/(#[^\n]*)/g, m => stash(`<span class="tok-com">${m}</span>`));
        } else if (["html", "htm", "xml", "svg"].includes(l)) {
          code = code.replace(/(&lt;!--[\s\S]*?--&gt;)/g, m => stash(`<span class="tok-com">${m}</span>`));
        } else if (l === "sql") {
          code = code.replace(/(--[^\n]*|\/\*[\s\S]*?\*\/)/g, m => stash(`<span class="tok-com">${m}</span>`));
        } else {
          code = code.replace(/(\/\*[\s\S]*?\*\/|\/\/[^\n]*)/g, m => stash(`<span class="tok-com">${m}</span>`));
        }

        // Strings
        code = code.replace(/(&quot;(?:\\.|[^&]|&(?!quot;))*?&quot;|'(?:\\.|[^'])*?'|`(?:\\.|[^`])*?`)/g, m => {
          return stash(`<span class="tok-str">${m}</span>`);
        });

        // HTML / XML tags
        if (["html", "htm", "xml", "svg", "vue", "svelte"].includes(l)) {
          code = code.replace(/(&lt;\/?)([A-Za-z][A-Za-z0-9:-]*)/g, '$1<span class="tok-tag">$2</span>');
          code = code.replace(/\b([a-zA-Z-:]+)(?==)/g, '<span class="tok-prop">$1</span>');
          return code.replace(/\u0000TOK(\d+)\u0000/g, (_, idx) => tokens[Number(idx)]);
        }

        // YAML / TOML keys
        if (["yaml", "yml", "toml", "ini", "conf", "env"].includes(l)) {
          code = code.replace(/^(\s*)([A-Za-z0-9_.-]+)(\s*[:=])/gm, '$1<span class="tok-prop">$2</span>$3');
          code = code.replace(/\b(true|false|null|yes|no)\b/gi, '<span class="tok-kw">$1</span>');
          code = code.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="tok-num">$1</span>');
          return code.replace(/\u0000TOK(\d+)\u0000/g, (_, idx) => tokens[Number(idx)]);
        }

        const kwMap = {
          swift: "import|struct|class|enum|protocol|extension|func|var|let|if|else|guard|return|switch|case|default|for|in|while|do|try|catch|throw|throws|async|await|public|private|internal|fileprivate|final|static|override|init|self|Self|true|false|nil|some|weak|mutating|actor|typealias",
          python: "import|from|as|def|class|return|if|elif|else|for|in|while|try|except|finally|with|lambda|yield|pass|break|continue|True|False|None|and|or|not|is|async|await|global|nonlocal",
          js: "import|export|from|default|const|let|var|function|class|extends|return|if|else|switch|case|for|of|in|while|try|catch|finally|new|this|true|false|null|undefined|async|await|typeof|instanceof",
          ts: "import|export|from|default|const|let|var|function|class|interface|type|enum|extends|implements|return|if|else|switch|case|for|of|in|while|try|catch|finally|new|this|true|false|null|undefined|async|await|readonly|public|private|protected|keyof|as",
          java: "package|import|public|private|protected|class|interface|enum|extends|implements|static|final|void|return|if|else|switch|case|default|for|while|do|try|catch|finally|throw|throws|new|this|super|true|false|null|int|long|double|boolean|char",
          kotlin: "package|import|class|interface|object|data|sealed|enum|fun|val|var|if|else|when|for|in|while|return|try|catch|finally|throw|true|false|null|private|public|internal|override|companion|suspend",
          c: "include|define|ifdef|endif|struct|union|enum|typedef|const|static|extern|void|int|long|short|char|float|double|unsigned|signed|bool|return|if|else|switch|case|default|for|while|do|break|continue|sizeof|NULL|true|false|class|namespace|template|typename|public|private|protected|virtual|override|auto|nullptr",
          rust: "use|mod|pub|fn|struct|enum|impl|trait|let|mut|const|if|else|match|for|in|while|loop|return|async|await|true|false|self|Self|where|crate|super",
          go: "package|import|func|type|struct|interface|var|const|if|else|switch|case|default|for|range|return|go|defer|chan|map|select|true|false|nil",
          ruby: "def|end|class|module|if|elsif|else|unless|case|when|while|until|for|do|return|yield|begin|rescue|ensure|true|false|nil|require|include|attr_accessor",
          php: "function|class|interface|trait|extends|implements|public|private|protected|static|return|if|elseif|else|switch|case|foreach|for|while|try|catch|new|true|false|null|echo|use|namespace",
          bash: "if|then|else|elif|fi|for|do|done|while|case|esac|function|export|local|return|echo|cd|ls|rm|cp|mv|mkdir|grep|awk|sed|set|exit",
          sql: "SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|BY|ORDER|HAVING|LIMIT|AS|AND|OR|NOT|NULL|DISTINCT|PRIMARY|KEY|INDEX",
          css: "display|position|color|background|margin|padding|border|font-size|font-family|flex|grid|width|height|align-items|justify-content|gap|border-radius|overflow|z-index|opacity|transition|transform"
        };
        const alias = {
          py: "python", javascript: "js", jsx: "js", mjs: "js", cjs: "js",
          typescript: "ts", tsx: "ts", sh: "bash", zsh: "bash", shell: "bash", command: "bash",
          rs: "rust", kt: "kotlin", kts: "kotlin", cpp: "c", cc: "c", cxx: "c", h: "c", hpp: "c", m: "c", mm: "c",
          rb: "ruby", scss: "css", less: "css"
        };
        const key = alias[l] || l;

        if (key === "json") {
          code = code.replace(/(\u0000TOK\d+\u0000)(\s*:)/g, (m, tok, colon) => {
            const idx = Number(tok.replace(/\u0000TOK|\u0000/g, ""));
            tokens[idx] = tokens[idx].replace('tok-str', 'tok-prop');
            return tok + colon;
          });
          code = code.replace(/\b(true|false|null)\b/g, '<span class="tok-kw">$1</span>');
          code = code.replace(/\b(-?\d+(?:\.\d+)?)\b/g, '<span class="tok-num">$1</span>');
        } else {
          if (kwMap[key]) {
            const flags = key === "sql" ? "gi" : "g";
            const kwRegex = new RegExp(`\\b(${kwMap[key]})\\b`, flags);
            code = code.replace(kwRegex, '<span class="tok-kw">$1</span>');
          }
          code = code.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="tok-num">$1</span>');
          code = code.replace(/\b([A-Z][A-Za-z0-9_]+)\b/g, '<span class="tok-type">$1</span>');
          code = code.replace(/\b([a-z_][A-Za-z0-9_]*)(?=\s*\()/g, '<span class="tok-fn">$1</span>');
        }

        return code.replace(/\u0000TOK(\d+)\u0000/g, (_, idx) => tokens[Number(idx)]);
      }

      // ===== Offline UML Class Diagram SVG Renderer =====
      function isUMLClassDiagram(lang, rawCode) {
        const l = (lang || "").toLowerCase().trim();
        if (["uml", "plantuml", "classdiagram", "class-diagram"].includes(l)) return true;
        if (l === "mermaid" && /^\s*classDiagram\b/m.test(rawCode)) return true;
        return false;
      }

      function renderUMLClassDiagram(rawCode) {
        const lines = rawCode.replace(/\r\n/g, "\n").split("\n");
        const classes = new Map();
        const edges = [];

        function ensureClass(name) {
          const clean = name.trim().replace(/^["`]|["`]$/g, "");
          if (!clean) return null;
          if (!classes.has(clean)) {
            classes.set(clean, { name: clean, stereotype: "", attrs: [], methods: [] });
          }
          return classes.get(clean);
        }

        function addMember(cls, rawMember) {
          const m = rawMember.trim();
          if (!m || m.startsWith("%%") || m.startsWith("'")) return;
          const stMatch = m.match(/^<<([^>]+)>>$/);
          if (stMatch) {
            cls.stereotype = stMatch[1].trim();
            return;
          }
          if (m.includes("(") && m.includes(")")) {
            cls.methods.push(m);
          } else {
            cls.attrs.push(m);
          }
        }

        let currentClass = null;
        for (const rawLine of lines) {
          const line = rawLine.trim();
          if (!line || line === "classDiagram" || line === "@startuml" || line === "@enduml" || line.startsWith("%%") || line.startsWith("'")) {
            continue;
          }
          if (currentClass) {
            if (line === "}") {
              currentClass = null;
            } else {
              addMember(currentClass, line);
            }
            continue;
          }

          // class / interface / abstract class / enum block
          const blockMatch = line.match(/^(?:(abstract\s+class|interface|enum|class)\s+)([A-Za-z0-9_.\u4e00-\u9fff]+)(?:\s*<<([^>]+)>>)?\s*(\{)?\s*$/);
          if (blockMatch) {
            const kind = blockMatch[1];
            const cls = ensureClass(blockMatch[2]);
            if (blockMatch[3]) cls.stereotype = blockMatch[3].trim();
            else if (kind === "interface") cls.stereotype = "interface";
            else if (kind === "abstract class") cls.stereotype = "abstract";
            else if (kind === "enum") cls.stereotype = "enum";
            if (blockMatch[4] === "{") {
              currentClass = cls;
            }
            continue;
          }

          // Relationship line: A <|-- B : label
          const relMatch = line.match(/^([A-Za-z0-9_.\u4e00-\u9fff]+)\s*(?:"([^"]*)"\s*)?(<\|--|--\|>|<\|\.\.|\.\.\|>|\*--|--\*|o--|--o|<--|-->|<\.\.|\.\.>|--) \s*(?:"([^"]*)"\s*)?([A-Za-z0-9_.\u4e00-\u9fff]+)(?:\s*:\s*(.+))?$/);
          if (relMatch) {
            const left = relMatch[1];
            const cardLeft = relMatch[2] || "";
            const op = relMatch[3];
            const cardRight = relMatch[4] || "";
            const right = relMatch[5];
            const label = (relMatch[6] || "").trim();
            ensureClass(left);
            ensureClass(right);
            edges.push({ left, right, op, label, cardLeft, cardRight });
            continue;
          }

          // Single-line member: ClassName : +String title
          const memberMatch = line.match(/^([A-Za-z0-9_.\u4e00-\u9fff]+)\s*:\s*(.+)$/);
          if (memberMatch) {
            const cls = ensureClass(memberMatch[1]);
            if (cls) addMember(cls, memberMatch[2]);
            continue;
          }
        }

        const nodes = Array.from(classes.values());
        if (nodes.length === 0) {
          return `<pre><span class="lang-badge">uml</span><code>${escapeHtml(rawCode)}</code></pre>`;
        }

        // Measure each class box
        const charW = 7.6;
        for (const n of nodes) {
          const allLines = [n.name, n.stereotype ? `«${n.stereotype}»` : "", ...n.attrs, ...n.methods];
          const maxChars = Math.max(12, ...allLines.map(s => {
            let len = 0;
            for (const ch of s) len += ch.charCodeAt(0) > 255 ? 1.8 : 1;
            return len;
          }));
          n.w = Math.max(176, Math.ceil(maxChars * charW) + 34);
          const headerH = n.stereotype ? 50 : 36;
          const attrH = n.attrs.length > 0 ? n.attrs.length * 20 + 14 : 10;
          const methH = n.methods.length > 0 ? n.methods.length * 20 + 14 : 10;
          n.headerH = headerH;
          n.attrH = attrH;
          n.methH = methH;
          n.h = headerH + attrH + methH;
        }

        // Assign hierarchical ranks (parents on top for inheritance/realization/composition/aggregation)
        const rank = new Map(nodes.map(n => [n.name, 0]));
        for (let iter = 0; iter < nodes.length; iter++) {
          for (const e of edges) {
            let parent = null, child = null;
            if (["<|--", "<|..", "*--", "o--"].includes(e.op)) {
              parent = e.left; child = e.right;
            } else if (["--|>", "..|>", "--*", "--o"].includes(e.op)) {
              parent = e.right; child = e.left;
            } else if (["-->", "..>"].includes(e.op)) {
              parent = e.left; child = e.right;
            } else if (["<--", "<.."].includes(e.op)) {
              parent = e.right; child = e.left;
            }
            if (parent && child && parent !== child) {
              const nextRank = (rank.get(parent) || 0) + 1;
              if (nextRank > (rank.get(child) || 0) && nextRank < nodes.length) {
                rank.set(child, nextRank);
              }
            }
          }
        }

        // Group into rows; if all rank 0 and >3 nodes, wrap into 3-col grid
        const rowMap = new Map();
        const maxRank = Math.max(...rank.values());
        if (maxRank === 0 && nodes.length > 3) {
          nodes.forEach((n, idx) => {
            const r = Math.floor(idx / 3);
            if (!rowMap.has(r)) rowMap.set(r, []);
            rowMap.get(r).push(n);
          });
        } else {
          for (const n of nodes) {
            const r = rank.get(n.name) || 0;
            if (!rowMap.has(r)) rowMap.set(r, []);
            rowMap.get(r).push(n);
          }
        }

        const rowKeys = Array.from(rowMap.keys()).sort((a, b) => a - b);
        const hGap = 44;
        const vGap = 64;
        const padX = 28;
        const padY = 26;

        const rowWidths = rowKeys.map(r => {
          const list = rowMap.get(r);
          return list.reduce((acc, n) => acc + n.w, 0) + Math.max(0, list.length - 1) * hGap;
        });
        const totalW = Math.max(360, ...rowWidths) + padX * 2;

        let curY = padY;
        for (let idx = 0; idx < rowKeys.length; idx++) {
          const list = rowMap.get(rowKeys[idx]);
          const rowW = rowWidths[idx];
          let curX = (totalW - rowW) / 2;
          const rowH = Math.max(...list.map(n => n.h));
          for (const n of list) {
            n.x = curX;
            n.y = curY;
            curX += n.w + hGap;
          }
          curY += rowH + vGap;
        }
        const totalH = Math.max(160, curY - vGap + padY);

        function colorMember(m) {
          const esc = escapeHtml(m);
          if (m.startsWith("+")) return `<tspan fill="#98C379">+</tspan>${esc.slice(1)}`;
          if (m.startsWith("-")) return `<tspan fill="#F7768E">-</tspan>${esc.slice(1)}`;
          if (m.startsWith("#")) return `<tspan fill="#E0AF68">#</tspan>${esc.slice(1)}`;
          if (m.startsWith("~")) return `<tspan fill="#7DCFFF">~</tspan>${esc.slice(1)}`;
          return esc;
        }

        // Build SVG
        let svgParts = [];
        svgParts.push(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${Math.ceil(totalW)} ${Math.ceil(totalH)}" width="${Math.ceil(totalW)}" height="${Math.ceil(totalH)}">`);
        svgParts.push(`<defs>
          <marker id="uml-inherit" viewBox="0 0 12 12" refX="11" refY="6" markerWidth="11" markerHeight="11" orient="auto-start-reverse">
            <path d="M 1 1.5 L 11 6 L 1 10.5 Z" fill="#13141A" stroke="#7AA2F7" stroke-width="1.4"/>
          </marker>
          <marker id="uml-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" orient="auto-start-reverse">
            <path d="M 1.5 1.5 L 9 5 L 1.5 8.5" fill="none" stroke="#8E96B0" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
          </marker>
          <marker id="uml-comp" viewBox="0 0 14 10" refX="13" refY="5" markerWidth="13" markerHeight="10" orient="auto-start-reverse">
            <path d="M 1 5 L 7 1.2 L 13 5 L 7 8.8 Z" fill="#7AA2F7" stroke="#7AA2F7" stroke-width="1.2"/>
          </marker>
          <marker id="uml-agg" viewBox="0 0 14 10" refX="13" refY="5" markerWidth="13" markerHeight="10" orient="auto-start-reverse">
            <path d="M 1 5 L 7 1.2 L 13 5 L 7 8.8 Z" fill="#13141A" stroke="#7AA2F7" stroke-width="1.3"/>
          </marker>
        </defs>`);

        // Render edges first
        for (const e of edges) {
          const a = classes.get(e.left);
          const b = classes.get(e.right);
          if (!a || !b) continue;

          // Normalize direction so marker sits on target end
          let from = a, to = b, markerEnd = "", markerStart = "", dashed = false, stroke = "#8E96B0";
          switch (e.op) {
            case "<|--": from = b; to = a; markerEnd = "url(#uml-inherit)"; stroke = "#7AA2F7"; break;
            case "--|>": from = a; to = b; markerEnd = "url(#uml-inherit)"; stroke = "#7AA2F7"; break;
            case "<|..": from = b; to = a; markerEnd = "url(#uml-inherit)"; dashed = true; stroke = "#7AA2F7"; break;
            case "..|>": from = a; to = b; markerEnd = "url(#uml-inherit)"; dashed = true; stroke = "#7AA2F7"; break;
            case "*--":  from = b; to = a; markerEnd = "url(#uml-comp)"; stroke = "#7AA2F7"; break;
            case "--*":  from = a; to = b; markerEnd = "url(#uml-comp)"; stroke = "#7AA2F7"; break;
            case "o--":  from = b; to = a; markerEnd = "url(#uml-agg)"; stroke = "#7AA2F7"; break;
            case "--o":  from = a; to = b; markerEnd = "url(#uml-agg)"; stroke = "#7AA2F7"; break;
            case "..>":  from = a; to = b; markerEnd = "url(#uml-arrow)"; dashed = true; break;
            case "<..":  from = b; to = a; markerEnd = "url(#uml-arrow)"; dashed = true; break;
            case "-->":  from = a; to = b; markerEnd = "url(#uml-arrow)"; break;
            case "<--":  from = b; to = a; markerEnd = "url(#uml-arrow)"; break;
            default:     from = a; to = b; break;
          }

          const ax = from.x + from.w / 2, ay = from.y + from.h / 2;
          const bx = to.x + to.w / 2, by = to.y + to.h / 2;
          let x1, y1, x2, y2, pathD;

          if (Math.abs(ay - by) > 20) {
            // Vertical connection
            if (ay > by) {
              x1 = ax; y1 = from.y;
              x2 = bx; y2 = to.y + to.h;
            } else {
              x1 = ax; y1 = from.y + from.h;
              x2 = bx; y2 = to.y;
            }
            const midY = (y1 + y2) / 2;
            pathD = `M ${x1} ${y1} C ${x1} ${midY}, ${x2} ${midY}, ${x2} ${y2}`;
          } else {
            // Horizontal connection
            if (ax < bx) {
              x1 = from.x + from.w; y1 = ay;
              x2 = to.x; y2 = by;
            } else {
              x1 = from.x; y1 = ay;
              x2 = to.x + to.w; y2 = by;
            }
            const midX = (x1 + x2) / 2;
            pathD = `M ${x1} ${y1} C ${midX} ${y1}, ${midX} ${y2}, ${x2} ${y2}`;
          }

          const dashAttr = dashed ? ` stroke-dasharray="5 4"` : "";
          const mEndAttr = markerEnd ? ` marker-end="${markerEnd}"` : "";
          const mStartAttr = markerStart ? ` marker-start="${markerStart}"` : "";
          svgParts.push(`<path d="${pathD}" fill="none" stroke="${stroke}" stroke-width="1.4"${dashAttr}${mEndAttr}${mStartAttr}/>`);

          if (e.label) {
            const lx = (x1 + x2) / 2;
            const ly = (y1 + y2) / 2 - 6;
            const pillW = Math.max(40, e.label.length * 7.2 + 14);
            svgParts.push(`<rect x="${lx - pillW / 2}" y="${ly - 10}" width="${pillW}" height="18" rx="9" fill="#1C1E28" stroke="#2F3344" stroke-width="1"/>`);
            svgParts.push(`<text x="${lx}" y="${ly + 3}" text-anchor="middle" fill="#A9B1D6" font-family="SF Mono, Menlo, monospace" font-size="11">${escapeHtml(e.label)}</text>`);
          }
        }

        // Render class cards
        for (const n of nodes) {
          svgParts.push(`<g transform="translate(${n.x}, ${n.y})">`);
          svgParts.push(`<rect x="0" y="0" width="${n.w}" height="${n.h}" rx="10" fill="#1B1D26" stroke="#34384A" stroke-width="1.2"/>`);
          svgParts.push(`<path d="M 10 0 H ${n.w - 10} Q ${n.w} 0 ${n.w} 10 V ${n.headerH} H 0 V 10 Q 0 0 10 0 Z" fill="#232736"/>`);

          if (n.stereotype) {
            svgParts.push(`<text x="${n.w / 2}" y="18" text-anchor="middle" fill="#7AA2F7" font-family="SF Mono, Menlo, monospace" font-size="11">«${escapeHtml(n.stereotype)}»</text>`);
            svgParts.push(`<text x="${n.w / 2}" y="38" text-anchor="middle" fill="#EEF0F8" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="13.5" font-weight="600">${escapeHtml(n.name)}</text>`);
          } else {
            svgParts.push(`<text x="${n.w / 2}" y="23" text-anchor="middle" fill="#EEF0F8" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="13.5" font-weight="600">${escapeHtml(n.name)}</text>`);
          }

          // Divider 1
          svgParts.push(`<line x1="0" y1="${n.headerH}" x2="${n.w}" y2="${n.headerH}" stroke="#34384A" stroke-width="1"/>`);

          // Attributes
          n.attrs.forEach((attr, idx) => {
            const y = n.headerH + 18 + idx * 20;
            svgParts.push(`<text x="12" y="${y}" fill="#C8CDD9" font-family="SF Mono, Menlo, monospace" font-size="12">${colorMember(attr)}</text>`);
          });

          // Divider 2
          const div2Y = n.headerH + n.attrH;
          svgParts.push(`<line x1="0" y1="${div2Y}" x2="${n.w}" y2="${div2Y}" stroke="#2A2E3D" stroke-width="1"/>`);

          // Methods
          n.methods.forEach((meth, idx) => {
            const y = div2Y + 18 + idx * 20;
            svgParts.push(`<text x="12" y="${y}" fill="#B7C5E8" font-family="SF Mono, Menlo, monospace" font-size="12">${colorMember(meth)}</text>`);
          });

          svgParts.push(`</g>`);
        }

        svgParts.push(`</svg>`);
        return `<div class="uml-box"><div class="uml-badge">UML CLASS DIAGRAM</div>${svgParts.join("")}</div>`;
      }

      function parseInline(text) {
        let s = escapeHtml(text);
        const codeSpans = [];
        s = s.replace(/`([^`]+)`/g, (_, inner) => {
          const id = codeSpans.length;
          codeSpans.push(`<code>${inner}</code>`);
          return `\u0001CODE${id}\u0001`;
        });
        s = s.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img alt="$1" src="$2" />');
        s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
        s = s.replace(/\*\*\*([^*]+)\*\*\*/g, '<strong><em>$1</em></strong>');
        s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
        s = s.replace(/__([^_]+)__/g, '<strong>$1</strong>');
        s = s.replace(/\*([^*]+)\*/g, '<em>$1</em>');
        s = s.replace(/(^|\s)_([^_]+)_(?=\s|$|[.,!?;:])/g, '$1<em>$2</em>');
        s = s.replace(/~~([^~]+)~~/g, '<del>$1</del>');
        s = s.replace(/\u0001CODE(\d+)\u0001/g, (_, idx) => codeSpans[Number(idx)]);
        return s;
      }

      function renderMarkdown(md) {
        if (!md.trim()) {
          return `<div class="empty-hint">空白文档 — 开始输入 Markdown 或拖入任意文件</div>`;
        }
        const lines = md.replace(/\r\n/g, "\n").split("\n");
        let html = [];
        let i = 0;

        while (i < lines.length) {
          const line = lines[i];

          if (/^\s*$/.test(line)) {
            i++;
            continue;
          }

          const fenceMatch = line.match(/^```([^\s`]*)\s*$/);
          if (fenceMatch) {
            const lang = fenceMatch[1] || "";
            const codeLines = [];
            i++;
            while (i < lines.length && !/^```\s*$/.test(lines[i])) {
              codeLines.push(lines[i]);
              i++;
            }
            if (i < lines.length) i++;
            const rawBlock = codeLines.join("\n");
            if (isUMLClassDiagram(lang, rawBlock)) {
              html.push(renderUMLClassDiagram(rawBlock));
            } else {
              const badge = lang ? `<span class="lang-badge">${escapeHtml(lang)}</span>` : "";
              const highlighted = highlightCode(rawBlock, lang);
              html.push(`<pre>${badge}<code>${highlighted}</code></pre>`);
            }
            continue;
          }

          const hMatch = line.match(/^(#{1,6})\s+(.+)$/);
          if (hMatch) {
            const level = hMatch[1].length;
            html.push(`<h${level}>${parseInline(hMatch[2].trim())}</h${level}>`);
            i++;
            continue;
          }

          if (/^(\*{3,}|-{3,}|_{3,})\s*$/.test(line.trim())) {
            html.push("<hr />");
            i++;
            continue;
          }

          if (/^\s*>\s?/.test(line)) {
            const qLines = [];
            while (i < lines.length && /^\s*>\s?/.test(lines[i])) {
              qLines.push(lines[i].replace(/^\s*>\s?/, ""));
              i++;
            }
            html.push(`<blockquote>${renderMarkdown(qLines.join("\n"))}</blockquote>`);
            continue;
          }

          if (line.includes("|") && i + 1 < lines.length && /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$/.test(lines[i + 1])) {
            const splitRow = r => r.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map(c => c.trim());
            const headers = splitRow(line);
            i += 2;
            const rows = [];
            while (i < lines.length && lines[i].includes("|") && !/^\s*$/.test(lines[i])) {
              rows.push(splitRow(lines[i]));
              i++;
            }
            let tbl = "<table><thead><tr>" + headers.map(h => `<th>${parseInline(h)}</th>`).join("") + "</tr></thead><tbody>";
            for (const row of rows) {
              tbl += "<tr>" + headers.map((_, idx) => `<td>${parseInline(row[idx] || "")}</td>`).join("") + "</tr>";
            }
            tbl += "</tbody></table>";
            html.push(tbl);
            continue;
          }

          if (/^\s*[-*+]\s+/.test(line)) {
            const items = [];
            while (i < lines.length && /^\s*[-*+]\s+/.test(lines[i])) {
              const rawItem = lines[i].replace(/^\s*[-*+]\s+/, "");
              const taskMatch = rawItem.match(/^\[( |x|X)\]\s+(.*)$/);
              if (taskMatch) {
                const checked = taskMatch[1].toLowerCase() === "x" ? "checked" : "";
                items.push(`<li class="task-item"><input type="checkbox" ${checked} /><span>${parseInline(taskMatch[2])}</span></li>`);
              } else {
                items.push(`<li>${parseInline(rawItem)}</li>`);
              }
              i++;
            }
            html.push(`<ul>${items.join("")}</ul>`);
            continue;
          }

          if (/^\s*\d+\.\s+/.test(line)) {
            const items = [];
            while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
              const rawItem = lines[i].replace(/^\s*\d+\.\s+/, "");
              items.push(`<li>${parseInline(rawItem)}</li>`);
              i++;
            }
            html.push(`<ol>${items.join("")}</ol>`);
            continue;
          }

          const pLines = [];
          while (
            i < lines.length &&
            !/^\s*$/.test(lines[i]) &&
            !/^```/.test(lines[i]) &&
            !/^#{1,6}\s+/.test(lines[i]) &&
            !/^\s*>\s?/.test(lines[i]) &&
            !/^\s*[-*+]\s+/.test(lines[i]) &&
            !/^\s*\d+\.\s+/.test(lines[i])
          ) {
            pLines.push(lines[i]);
            i++;
          }
          html.push(`<p>${parseInline(pLines.join("<br />"))}</p>`);
        }

        return html.join("\n");
      }

      function renderCodeFile(rawCode, lang) {
        if (!rawCode) {
          return `<div class="empty-hint">空白代码文件</div>`;
        }
        const highlighted = highlightCode(rawCode, lang);
        const lines = highlighted.replace(/\r\n/g, "\n").split("\n");
        const rows = lines.map((lineHtml, idx) =>
          `<div class="code-line"><span class="line-num">${idx + 1}</span><span class="line-code">${lineHtml || " "}</span></div>`
        ).join("");
        const label = (lang || "text").toUpperCase();
        return `
          <div class="code-file-view">
            <div class="code-file-header">
              <span>${escapeHtml(label)}</span>
              <span>${lines.length} 行</span>
            </div>
            <div class="code-file-body">${rows}</div>
          </div>
        `;
      }

      window.updateContent = function(base64, mode, lang) {
        try {
          const binary = atob(base64);
          const bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
          const text = new TextDecoder("utf-8").decode(bytes);
          const container = document.getElementById("content");
          if (mode === "code") {
            container.innerHTML = renderCodeFile(text, lang);
          } else {
            container.innerHTML = renderMarkdown(text);
          }
        } catch (e) {
          document.getElementById("content").textContent = "预览渲染失败: " + e.message;
        }
      };

      window.syncScroll = function(fraction) {
        const maxScroll = Math.max(document.documentElement.scrollHeight - window.innerHeight, 0);
        window.scrollTo({ top: maxScroll * fraction, behavior: "auto" });
      };

      window.setPreviewWidth = function(px) {
        const el = document.getElementById("content");
        if (!el) return;
        el.style.maxWidth = (px && px > 0) ? (px + "px") : "none";
      };
    </script>
    </body>
    </html>
    """#
}
