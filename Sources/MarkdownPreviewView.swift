import AppKit
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
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
        context.coordinator.pendingMaxWidth = maxWidth
        webView.loadHTMLString(Self.htmlTemplate, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateMarkdown(markdown)
        context.coordinator.updateScroll(scrollFraction)
        context.coordinator.updateMaxWidth(maxWidth)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isLoaded = false
        var pendingMarkdown: String = ""
        var pendingMaxWidth: Double = 0
        private var lastRenderedMarkdown: String = ""
        private var lastScrollFraction: Double = -1
        private var lastAppliedMaxWidth: Double = -1
        private var debounceWorkItem: DispatchWorkItem?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            applyMaxWidthNow(pendingMaxWidth)
            renderNow(pendingMarkdown)
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

        func updateMarkdown(_ markdown: String) {
            pendingMarkdown = markdown
            guard isLoaded, markdown != lastRenderedMarkdown else { return }

            debounceWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.renderNow(markdown)
            }
            debounceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: item)
        }

        private func renderNow(_ markdown: String) {
            guard isLoaded, let webView = webView else { return }
            lastRenderedMarkdown = markdown
            let base64 = Data(markdown.utf8).base64EncodedString()
            webView.evaluateJavaScript("window.updateMarkdown('\(base64)');", completionHandler: nil)
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
      /* Syntax highlight palette (Tokyo Night / One Dark inspired) */
      .tok-kw { color: #C678DD; }
      .tok-str { color: #98C379; }
      .tok-com { color: #676E82; font-style: italic; }
      .tok-num { color: #D19A66; }
      .tok-type { color: #E5C07B; }
      .tok-fn { color: #61AFEF; }
      .tok-prop { color: #56B6C2; }
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
        if (!l) return code;

        const tokens = [];
        function stash(html) {
          const id = tokens.length;
          tokens.push(html);
          return `\u0000TOK${id}\u0000`;
        }

        // Comments
        if (["python", "py", "bash", "sh", "shell", "yaml", "yml"].includes(l)) {
          code = code.replace(/(#[^\n]*)/g, m => stash(`<span class="tok-com">${m}</span>`));
        } else if (["html", "xml"].includes(l)) {
          code = code.replace(/(&lt;!--[\s\S]*?--&gt;)/g, m => stash(`<span class="tok-com">${m}</span>`));
        } else {
          code = code.replace(/(\/\*[\s\S]*?\*\/|\/\/[^\n]*)/g, m => stash(`<span class="tok-com">${m}</span>`));
        }

        // Strings
        code = code.replace(/(&quot;(?:\\.|[^&]|&(?!quot;))*?&quot;|'(?:\\.|[^'])*?'|`(?:\\.|[^`])*?`)/g, m => {
          return stash(`<span class="tok-str">${m}</span>`);
        });

        // Keywords by language family
        const kwMap = {
          swift: "import|struct|class|enum|protocol|extension|func|var|let|if|else|guard|return|switch|case|default|for|in|while|do|try|catch|throw|throws|async|await|public|private|internal|fileprivate|final|static|override|init|self|Self|true|false|nil|some|weak|mutating",
          python: "import|from|as|def|class|return|if|elif|else|for|in|while|try|except|finally|with|lambda|yield|pass|break|continue|True|False|None|and|or|not|is|async|await",
          js: "import|export|from|default|const|let|var|function|class|extends|return|if|else|switch|case|for|of|in|while|try|catch|finally|new|this|true|false|null|undefined|async|await|typeof",
          ts: "import|export|from|default|const|let|var|function|class|interface|type|enum|extends|implements|return|if|else|switch|case|for|of|in|while|try|catch|finally|new|this|true|false|null|undefined|async|await|readonly|public|private",
          rust: "use|mod|pub|fn|struct|enum|impl|trait|let|mut|const|if|else|match|for|in|while|loop|return|async|await|true|false|self|Self|where",
          go: "package|import|func|type|struct|interface|var|const|if|else|switch|case|for|range|return|go|defer|chan|map|true|false|nil",
          bash: "if|then|else|fi|for|do|done|while|case|esac|function|export|local|return|echo|cd|ls|rm|cp|mv|mkdir|grep|awk|sed",
          sql: "SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|DROP|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|AS|AND|OR|NOT|NULL|DISTINCT",
          css: "display|position|color|background|margin|padding|border|font-size|font-family|flex|grid|width|height|align-items|justify-content|gap|border-radius"
        };
        const alias = { py: "python", javascript: "js", typescript: "ts", sh: "bash", shell: "bash", rs: "rust" };
        const key = alias[l] || l;

        if (key === "json") {
          code = code.replace(/\b(true|false|null)\b/g, '<span class="tok-kw">$1</span>');
          code = code.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="tok-num">$1</span>');
        } else {
          if (kwMap[key]) {
            const flags = key === "sql" ? "gi" : "g";
            const kwRegex = new RegExp(`\\b(${kwMap[key]})\\b`, flags);
            code = code.replace(kwRegex, '<span class="tok-kw">$1</span>');
          }
          // Numbers
          code = code.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="tok-num">$1</span>');
          // Types (PascalCase)
          code = code.replace(/\b([A-Z][A-Za-z0-9_]+)\b/g, '<span class="tok-type">$1</span>');
          // Function calls
          code = code.replace(/\b([a-z_][A-Za-z0-9_]*)(?=\s*\()/g, '<span class="tok-fn">$1</span>');
        }

        // Restore stashed tokens
        code = code.replace(/\u0000TOK(\d+)\u0000/g, (_, idx) => tokens[Number(idx)]);
        return code;
      }

      function parseInline(text) {
        let s = escapeHtml(text);
        const codeSpans = [];
        s = s.replace(/`([^`]+)`/g, (_, inner) => {
          const id = codeSpans.length;
          codeSpans.push(`<code>${inner}</code>`);
          return `\u0001CODE${id}\u0001`;
        });
        // Images
        s = s.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img alt="$1" src="$2" />');
        // Links
        s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
        // Bold + Italic
        s = s.replace(/\*\*\*([^*]+)\*\*\*/g, '<strong><em>$1</em></strong>');
        s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
        s = s.replace(/__([^_]+)__/g, '<strong>$1</strong>');
        s = s.replace(/\*([^*]+)\*/g, '<em>$1</em>');
        s = s.replace(/(^|\s)_([^_]+)_(?=\s|$|[.,!?;:])/g, '$1<em>$2</em>');
        // Strikethrough
        s = s.replace(/~~([^~]+)~~/g, '<del>$1</del>');
        // Restore inline code
        s = s.replace(/\u0001CODE(\d+)\u0001/g, (_, idx) => codeSpans[Number(idx)]);
        return s;
      }

      function renderMarkdown(md) {
        const lines = md.replace(/\r\n/g, "\n").split("\n");
        let html = [];
        let i = 0;

        while (i < lines.length) {
          const line = lines[i];

          // Blank line
          if (/^\s*$/.test(line)) {
            i++;
            continue;
          }

          // Fenced code block
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
            const badge = lang ? `<span class="lang-badge">${escapeHtml(lang)}</span>` : "";
            const highlighted = highlightCode(codeLines.join("\n"), lang);
            html.push(`<pre>${badge}<code>${highlighted}</code></pre>`);
            continue;
          }

          // Heading
          const hMatch = line.match(/^(#{1,6})\s+(.+)$/);
          if (hMatch) {
            const level = hMatch[1].length;
            html.push(`<h${level}>${parseInline(hMatch[2].trim())}</h${level}>`);
            i++;
            continue;
          }

          // Horizontal rule
          if (/^(\*{3,}|-{3,}|_{3,})\s*$/.test(line.trim())) {
            html.push("<hr />");
            i++;
            continue;
          }

          // Blockquote
          if (/^\s*>\s?/.test(line)) {
            const qLines = [];
            while (i < lines.length && /^\s*>\s?/.test(lines[i])) {
              qLines.push(lines[i].replace(/^\s*>\s?/, ""));
              i++;
            }
            html.push(`<blockquote>${renderMarkdown(qLines.join("\n"))}</blockquote>`);
            continue;
          }

          // Table
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

          // Unordered / Task list
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

          // Ordered list
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

          // Paragraph
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

      window.updateMarkdown = function(base64) {
        try {
          const binary = atob(base64);
          const bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
          const text = new TextDecoder("utf-8").decode(bytes);
          document.getElementById("content").innerHTML = renderMarkdown(text);
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
