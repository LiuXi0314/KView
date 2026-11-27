import AppKit
import Combine
import Foundation
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case editorOnly = "编辑"
    case split = "分栏"
    case previewOnly = "预览"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .editorOnly: return "square.lefthalf.filled"
        case .split: return "rectangle.split.2x1"
        case .previewOnly: return "eye"
        }
    }
}

enum EditorFormatAction: Equatable {
    case bold
    case italic
    case inlineCode
    case link
    case heading
}

enum FileKind: Equatable {
    case markdown
    case code(language: String)
    case image

    var displayLabel: String {
        switch self {
        case .markdown: return "Markdown"
        case .code(let lang): return lang.isEmpty ? "纯文本" : lang.uppercased()
        case .image: return "图片"
        }
    }

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    static func detect(for url: URL?) -> FileKind {
        guard let url = url else { return .markdown }
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()

        if imageExtensions.contains(ext) {
            return .image
        }
        if markdownExtensions.contains(ext) {
            return .markdown
        }
        if ext.isEmpty {
            if name == "dockerfile" { return .code(language: "bash") }
            if name == "makefile" { return .code(language: "bash") }
            return .code(language: "text")
        }
        return .code(language: ext)
    }

    static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mdx"
    ]

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "tif", "heic", "ico"
    ]

    static let codeExtensions: Set<String> = [
        "txt", "log", "json", "yaml", "yml", "toml", "ini", "conf", "env", "plist",
        "swift", "py", "js", "jsx", "ts", "tsx", "mjs", "cjs",
        "html", "htm", "css", "scss", "less", "xml",
        "java", "kt", "kts", "go", "rs", "c", "cc", "cpp", "cxx", "h", "hpp", "m", "mm",
        "rb", "php", "sql", "sh", "bash", "zsh", "fish", "command", "gradle", "cmake", "vue", "svelte"
    ]

    static let allowedExtensionlessNames: Set<String> = [
        "makefile", "dockerfile", "podfile", "gemfile", "rakefile", "license", "readme", "procfile", ".gitignore", ".env"
    ]
}

struct FileNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?

    var fileKind: FileKind {
        FileKind.detect(for: url)
    }

    var isMarkdown: Bool {
        fileKind == .markdown
    }

    var isImage: Bool {
        fileKind.isImage
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var text: String = AppState.welcomeMarkdown
    @Published var currentFileURL: URL?
    @Published var currentFileKind: FileKind = .markdown
    @Published var rootFolderURL: URL?
    @Published var sidebarNodes: [FileNode] = []
    @Published var isSidebarVisible: Bool = true
    @Published var viewMode: ViewMode = .split
    @Published var isDirty: Bool = false
    @Published var scrollFraction: Double = 0.0
    @Published var formatRequestID: UUID = UUID()
    @Published var pendingFormatAction: EditorFormatAction?
    @Published var statusMessage: String?
    @Published var isDropTargeted: Bool = false
    @Published var collapsedFolders: Set<URL> = []
    @Published var isWidthPopoverPresented: Bool = false
    @Published var imageZoom: Double = 1.0
    @Published var imageFitToWindow: Bool = true
    @Published var isFullPreviewWidth: Bool = true {
        didSet { UserDefaults.standard.set(isFullPreviewWidth, forKey: "kmark.isFullPreviewWidth") }
    }
    @Published var previewMaxWidth: Double = 1120 {
        didSet { UserDefaults.standard.set(previewMaxWidth, forKey: "kmark.previewMaxWidth") }
    }

    private var statusClearTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "kmark.isFullPreviewWidth") != nil {
            self.isFullPreviewWidth = defaults.bool(forKey: "kmark.isFullPreviewWidth")
        }
        let savedWidth = defaults.double(forKey: "kmark.previewMaxWidth")
        if savedWidth >= 600 && savedWidth <= 2400 {
            self.previewMaxWidth = savedWidth
        }
    }

    var effectivePreviewMaxWidth: Double {
        isFullPreviewWidth ? 0 : previewMaxWidth
    }

    var previewWidthLabel: String {
        isFullPreviewWidth ? "满宽" : "\(Int(previewMaxWidth))px"
    }

    func setPreviewWidth(_ px: Double) {
        isFullPreviewWidth = false
        previewMaxWidth = min(max(px, 600), 2000)
    }

    func setFullPreviewWidth(_ enabled: Bool) {
        isFullPreviewWidth = enabled
        showToast(enabled ? "预览已设为满宽" : "预览行宽：\(Int(previewMaxWidth))px")
    }

    func widenPreview() {
        if isFullPreviewWidth {
            showToast("当前已是满宽")
            return
        }
        let next = previewMaxWidth + 120
        if next > 1800 {
            setFullPreviewWidth(true)
        } else {
            previewMaxWidth = next
            showToast("预览行宽：\(Int(previewMaxWidth))px")
        }
    }

    func narrowPreview() {
        if isFullPreviewWidth {
            isFullPreviewWidth = false
            previewMaxWidth = 1440
        } else {
            previewMaxWidth = max(600, previewMaxWidth - 120)
        }
        showToast("预览行宽：\(Int(previewMaxWidth))px")
    }

    func toggleFullPreviewWidth() {
        setFullPreviewWidth(!isFullPreviewWidth)
    }

    var displayFileName: String {
        currentFileURL?.lastPathComponent ?? "未命名"
    }

    var wordCount: Int {
        var count = 0
        var inLatinWord = false
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF {
                count += 1
                inLatinWord = false
            } else if CharacterSet.alphanumerics.contains(scalar) {
                if !inLatinWord {
                    count += 1
                    inLatinWord = true
                }
            } else {
                inLatinWord = false
            }
        }
        return count
    }

    var lineCount: Int {
        if text.isEmpty { return 0 }
        return text.components(separatedBy: .newlines).count
    }

    var characterCount: Int {
        text.count
    }

    func updateText(_ newValue: String) {
        guard newValue != text else { return }
        text = newValue
        isDirty = true
    }

    func triggerFormat(_ action: EditorFormatAction) {
        pendingFormatAction = action
        formatRequestID = UUID()
    }

    func formatCurrentCode() {
        guard !currentFileKind.isImage else { return }
        let lang: String
        switch currentFileKind {
        case .markdown: lang = "md"
        case .code(let l): lang = l
        case .image: return
        }
        let result = CodeFormatter.format(text, language: lang)
        if result.formatted != text {
            text = result.formatted
            isDirty = true
            showToast("已格式化 \(result.label)")
        } else {
            showToast("格式已整齐")
        }
    }

    func showToast(_ message: String) {
        statusMessage = message
        statusClearTask?.cancel()
        statusClearTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled {
                statusMessage = nil
            }
        }
    }

    func confirmDiscardIfNeeded() -> Bool {
        guard isDirty && !currentFileKind.isImage else { return true }
        let alert = NSAlert()
        alert.messageText = "当前文档有未保存的更改"
        alert.informativeText = "是否先保存「\(displayFileName)」再继续？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return saveDocument()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    /// 新建纯空白未命名文件
    func newDocument() {
        guard confirmDiscardIfNeeded() else { return }
        currentFileURL = nil
        currentFileKind = .markdown
        text = ""
        isDirty = false
        scrollFraction = 0
        showToast("已新建空文件")
    }

    /// 在当前目录（或指定位置）新建本地空文件
    func newEmptyFileInFolder() {
        guard confirmDiscardIfNeeded() else { return }
        let panel = NSSavePanel()
        panel.title = "新建空文件"
        panel.message = "输入文件名（支持 .md / .swift / .json / .py 等任意后缀）"
        panel.nameFieldStringValue = "untitled.md"
        panel.canCreateDirectories = true
        if let root = rootFolderURL {
            panel.directoryURL = root
        }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try "".write(to: url, atomically: true, encoding: .utf8)
                currentFileURL = url
                currentFileKind = FileKind.detect(for: url)
                text = ""
                isDirty = false
                scrollFraction = 0
                let parent = url.deletingLastPathComponent()
                if rootFolderURL == nil {
                    rootFolderURL = parent
                }
                refreshSidebar()
                showToast("已创建空文件 \(url.lastPathComponent)")
            } catch {
                showToast("创建失败：\(error.localizedDescription)")
            }
        }
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择 Markdown、代码、图片文件或文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            handleOpen(url: url)
        }
    }

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择要在左侧目录中打开的文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url: url)
        }
    }

    func handleOpen(url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            openFolder(url: url)
        } else {
            openFile(url: url)
        }
    }

    func openFile(url: URL) {
        guard confirmDiscardIfNeeded() else { return }
        let kind = FileKind.detect(for: url)

        if kind.isImage {
            currentFileURL = url
            currentFileKind = .image
            isDirty = false
            imageZoom = 1.0
            imageFitToWindow = true
            let parent = url.deletingLastPathComponent()
            if rootFolderURL == nil || !url.path.hasPrefix(rootFolderURL!.path) {
                rootFolderURL = parent
                refreshSidebar()
            }
            showToast("预览图片 \(url.lastPathComponent)")
            return
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            currentFileURL = url
            currentFileKind = kind
            text = content
            isDirty = false
            scrollFraction = 0
            let parent = url.deletingLastPathComponent()
            if rootFolderURL == nil || !url.path.hasPrefix(rootFolderURL!.path) {
                rootFolderURL = parent
                refreshSidebar()
            }
            showToast("已打开 \(url.lastPathComponent)")
        } catch {
            showToast("无法读取文件：\(error.localizedDescription)")
        }
    }

    func openFolder(url: URL) {
        rootFolderURL = url
        isSidebarVisible = true
        refreshSidebar()
        showToast("已打开目录 \(url.lastPathComponent)")
    }

    @discardableResult
    func saveDocument() -> Bool {
        guard !currentFileKind.isImage else { return true }
        if let url = currentFileURL {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                isDirty = false
                currentFileKind = FileKind.detect(for: url)
                showToast("已保存 \(url.lastPathComponent)")
                return true
            } catch {
                showToast("保存失败：\(error.localizedDescription)")
                return false
            }
        } else {
            return saveDocumentAs()
        }
    }

    @discardableResult
    func saveDocumentAs() -> Bool {
        guard !currentFileKind.isImage else { return true }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "Untitled.md"
        panel.canCreateDirectories = true
        if let root = rootFolderURL {
            panel.directoryURL = root
        }
        if panel.runModal() == .OK, let url = panel.url {
            currentFileURL = url
            currentFileKind = FileKind.detect(for: url)
            let ok = saveDocument()
            if ok {
                let parent = url.deletingLastPathComponent()
                if rootFolderURL == nil {
                    rootFolderURL = parent
                }
                refreshSidebar()
            }
            return ok
        }
        return false
    }

    func refreshSidebar() {
        guard let root = rootFolderURL else {
            sidebarNodes = []
            return
        }
        sidebarNodes = buildTree(at: root, depth: 0)
    }

    private func buildTree(at directory: URL, depth: Int) -> [FileNode] {
        guard depth < 6 else { return [] }
        let fm = FileManager.default
        let ignoredNames: Set<String> = [
            ".git", ".build", ".swiftpm", "node_modules", ".DS_Store", "DerivedData", "Pods", "dist", "build", "__pycache__", ".venv"
        ]

        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var dirs: [FileNode] = []
        var files: [FileNode] = []

        for item in items {
            let name = item.lastPathComponent
            if ignoredNames.contains(name) || name.hasSuffix(".app") { continue }
            let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = resourceValues?.isDirectory ?? false

            if isDir {
                let sub = buildTree(at: item, depth: depth + 1)
                if !sub.isEmpty {
                    dirs.append(FileNode(id: item, url: item, name: name, isDirectory: true, children: sub))
                }
            } else {
                let ext = item.pathExtension.lowercased()
                let lowerName = name.lowercased()
                let isSupported = FileKind.markdownExtensions.contains(ext)
                    || FileKind.codeExtensions.contains(ext)
                    || FileKind.imageExtensions.contains(ext)
                    || FileKind.allowedExtensionlessNames.contains(lowerName)
                if isSupported {
                    files.append(FileNode(id: item, url: item, name: name, isDirectory: false, children: nil))
                }
            }
        }

        dirs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return dirs + files
    }

    static let welcomeMarkdown = """
    # KMark

    极简深色模式 **macOS 原生 Markdown、代码与图片预览编辑器**。

    ## 常用快捷键

    | 操作 | 快捷键 | 说明 |
    | :--- | :--- | :--- |
    | 新建空文件 / 目录中新建 | `⌘ N` / `⇧⌘ N` | 快速创建空白文件 |
    | 代码格式化 | `⇧⌥ F` | 支持 JSON、HTML/XML、Swift、JS/TS、CSS、Markdown 等 |
    | 切换左侧目录 | `⌘ \\` | 支持 Markdown、各类代码与图片文件 |
    | 调节预览行宽 | `⌘ [` / `⌘ ]` / `⌘ 0` | 收窄 / 加宽 / 一键满宽 |

    ## UML 类图预览（离线原生渲染）

    ```mermaid
    classDiagram
        class Document {
            +String title
            +URL filePath
            +open() Bool
            +save() Bool
        }
        class MarkdownDoc {
            +String rawText
            +renderHTML() String
        }
        class CodeDoc {
            +String language
            +format() String
        }
        class ImageDoc {
            +Double zoom
            +fitToWindow() Void
        }
        Document <|-- MarkdownDoc : extends
        Document <|-- CodeDoc : extends
        Document <|-- ImageDoc : extends
    ```

    ## 代码块语法高亮

    ```swift
    import SwiftUI

    struct KMarkPreview: View {
        let title: String
        var body: some View {
            Text(title).font(.headline)
        }
    }
    ```
    """
}
