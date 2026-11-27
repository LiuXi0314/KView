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

    var isCode: Bool {
        if case .code = self { return true }
        return false
    }

    var isMarkdown: Bool {
        self == .markdown
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

struct DocumentTab: Identifiable, Equatable {
    let id: UUID
    var fileURL: URL?
    var fileKind: FileKind
    var text: String
    var isDirty: Bool
    var scrollFraction: Double
    var imageZoom: Double
    var imageFitToWindow: Bool

    init(
        id: UUID = UUID(),
        fileURL: URL? = nil,
        fileKind: FileKind = .markdown,
        text: String = "",
        isDirty: Bool = false,
        scrollFraction: Double = 0.0,
        imageZoom: Double = 1.0,
        imageFitToWindow: Bool = true
    ) {
        self.id = id
        self.fileURL = fileURL
        self.fileKind = fileKind
        self.text = text
        self.isDirty = isDirty
        self.scrollFraction = scrollFraction
        self.imageZoom = imageZoom
        self.imageFitToWindow = imageFitToWindow
    }

    var displayName: String {
        fileURL?.lastPathComponent ?? "未命名"
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var tabs: [DocumentTab]
    @Published var activeTabID: UUID
    @Published var rootFolderURL: URL?
    @Published var sidebarNodes: [FileNode] = []
    @Published var isSidebarVisible: Bool = true
    @Published var viewMode: ViewMode = .split
    @Published var formatRequestID: UUID = UUID()
    @Published var pendingFormatAction: EditorFormatAction?
    @Published var statusMessage: String?
    @Published var isDropTargeted: Bool = false
    @Published var collapsedFolders: Set<URL> = []
    @Published var isWidthPopoverPresented: Bool = false
    @Published var isFullPreviewWidth: Bool = true {
        didSet { UserDefaults.standard.set(isFullPreviewWidth, forKey: "kview.isFullPreviewWidth") }
    }
    @Published var previewMaxWidth: Double = 1120 {
        didSet { UserDefaults.standard.set(previewMaxWidth, forKey: "kview.previewMaxWidth") }
    }

    private var statusClearTask: Task<Void, Never>?

    init() {
        let initial = DocumentTab(fileURL: nil, fileKind: .markdown, text: AppState.welcomeMarkdown)
        self.tabs = [initial]
        self.activeTabID = initial.id

        let defaults = UserDefaults.standard
        if defaults.object(forKey: "kview.isFullPreviewWidth") != nil {
            self.isFullPreviewWidth = defaults.bool(forKey: "kview.isFullPreviewWidth")
        }
        let savedWidth = defaults.double(forKey: "kview.previewMaxWidth")
        if savedWidth >= 600 && savedWidth <= 2400 {
            self.previewMaxWidth = savedWidth
        }
    }

    // MARK: - Active Tab Accessors

    var activeTabIndex: Int {
        tabs.firstIndex(where: { $0.id == activeTabID }) ?? 0
    }

    var activeTab: DocumentTab {
        tabs[activeTabIndex]
    }

    var text: String {
        get { activeTab.text }
        set { tabs[activeTabIndex].text = newValue }
    }

    var currentFileURL: URL? {
        get { activeTab.fileURL }
        set { tabs[activeTabIndex].fileURL = newValue }
    }

    var currentFileKind: FileKind {
        get { activeTab.fileKind }
        set { tabs[activeTabIndex].fileKind = newValue }
    }

    var isDirty: Bool {
        get { activeTab.isDirty }
        set { tabs[activeTabIndex].isDirty = newValue }
    }

    var scrollFraction: Double {
        get { activeTab.scrollFraction }
        set { tabs[activeTabIndex].scrollFraction = newValue }
    }

    var imageZoom: Double {
        get { activeTab.imageZoom }
        set { tabs[activeTabIndex].imageZoom = newValue }
    }

    var imageFitToWindow: Bool {
        get { activeTab.imageFitToWindow }
        set { tabs[activeTabIndex].imageFitToWindow = newValue }
    }

    var displayFileName: String {
        activeTab.displayName
    }

    // MARK: - Tab Management

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    func selectNextTab() {
        guard tabs.count > 1 else { return }
        let next = (activeTabIndex + 1) % tabs.count
        activeTabID = tabs[next].id
    }

    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        let prev = (activeTabIndex - 1 + tabs.count) % tabs.count
        activeTabID = tabs[prev].id
    }

    func closeTab(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let target = tabs[idx]
        if !confirmDiscardIfNeeded(for: target) { return }

        if tabs.count == 1 {
            let empty = DocumentTab(fileURL: nil, fileKind: .markdown, text: "")
            tabs = [empty]
            activeTabID = empty.id
            return
        }

        let wasActive = (target.id == activeTabID)
        tabs.remove(at: idx)
        if wasActive {
            let newIndex = min(idx, tabs.count - 1)
            activeTabID = tabs[newIndex].id
        }
    }

    func closeActiveTab() {
        closeTab(activeTabID)
    }

    private func shouldReuseCurrentPlaceholderTab() -> Bool {
        guard tabs.count == 1 else { return false }
        let only = tabs[0]
        return only.fileURL == nil && !only.isDirty && (only.text.isEmpty || only.text == AppState.welcomeMarkdown)
    }

    // MARK: - Preview Width

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

    // MARK: - Counts & Editing

    var wordCount: Int {
        let current = text
        var count = 0
        var inLatinWord = false
        for scalar in current.unicodeScalars {
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
        let idx = activeTabIndex
        guard newValue != tabs[idx].text else { return }
        tabs[idx].text = newValue
        tabs[idx].isDirty = true
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
            let idx = activeTabIndex
            tabs[idx].text = result.formatted
            tabs[idx].isDirty = true
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

    private func confirmDiscardIfNeeded(for tab: DocumentTab) -> Bool {
        guard tab.isDirty && !tab.fileKind.isImage else { return true }
        let alert = NSAlert()
        alert.messageText = "「\(tab.displayName)」有未保存的更改"
        alert.informativeText = "关闭前是否先保存更改？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            activeTabID = tab.id
            return saveDocument()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: - File Operations

    /// 新建纯空白标签页
    func newDocument() {
        let newTab = DocumentTab(fileURL: nil, fileKind: .markdown, text: "")
        tabs.append(newTab)
        activeTabID = newTab.id
        showToast("已新建空标签页")
    }

    /// 在当前目录（或指定位置）新建本地空文件并在新标签页打开
    func newEmptyFileInFolder() {
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
                let newTab = DocumentTab(
                    fileURL: url,
                    fileKind: FileKind.detect(for: url),
                    text: "",
                    isDirty: false
                )
                if shouldReuseCurrentPlaceholderTab() {
                    tabs[0] = newTab
                } else {
                    tabs.append(newTab)
                }
                activeTabID = newTab.id
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
        panel.allowsMultipleSelection = true
        panel.message = "选择 Markdown、代码、图片文件或文件夹"
        if panel.runModal() == .OK {
            for url in panel.urls {
                handleOpen(url: url)
            }
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
        // If already open in a tab, just switch to it
        if let existing = tabs.first(where: { $0.fileURL == url }) {
            activeTabID = existing.id
            return
        }

        let kind = FileKind.detect(for: url)
        let newTab: DocumentTab

        if kind.isImage {
            newTab = DocumentTab(
                fileURL: url,
                fileKind: .image,
                text: "",
                isDirty: false,
                imageZoom: 1.0,
                imageFitToWindow: true
            )
        } else {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                newTab = DocumentTab(
                    fileURL: url,
                    fileKind: kind,
                    text: content,
                    isDirty: false
                )
            } catch {
                showToast("无法读取文件：\(error.localizedDescription)")
                return
            }
        }

        if shouldReuseCurrentPlaceholderTab() {
            tabs[0] = newTab
        } else {
            tabs.append(newTab)
        }
        activeTabID = newTab.id

        let parent = url.deletingLastPathComponent()
        if rootFolderURL == nil || !url.path.hasPrefix(rootFolderURL!.path) {
            rootFolderURL = parent
            refreshSidebar()
        }
        showToast(kind.isImage ? "预览图片 \(url.lastPathComponent)" : "已打开 \(url.lastPathComponent)")
    }

    func openFolder(url: URL) {
        rootFolderURL = url
        isSidebarVisible = true
        refreshSidebar()
        showToast("已打开目录 \(url.lastPathComponent)")
    }

    @discardableResult
    func saveDocument() -> Bool {
        let idx = activeTabIndex
        guard !tabs[idx].fileKind.isImage else { return true }
        if let url = tabs[idx].fileURL {
            do {
                try tabs[idx].text.write(to: url, atomically: true, encoding: .utf8)
                tabs[idx].isDirty = false
                tabs[idx].fileKind = FileKind.detect(for: url)
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
        let idx = activeTabIndex
        guard !tabs[idx].fileKind.isImage else { return true }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tabs[idx].fileURL?.lastPathComponent ?? "Untitled.md"
        panel.canCreateDirectories = true
        if let root = rootFolderURL {
            panel.directoryURL = root
        }
        if panel.runModal() == .OK, let url = panel.url {
            tabs[idx].fileURL = url
            tabs[idx].fileKind = FileKind.detect(for: url)
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
    # KView

    极简深色模式 **macOS 原生 Markdown、代码与图片预览编辑器**。

    ## 常用快捷键

    | 操作 | 快捷键 | 说明 |
    | :--- | :--- | :--- |
    | 新建空标签 / 关闭标签 | `⌘ T` / `⌘ W` | 顶部多标签自由切换（`⇧⌘[` / `⇧⌘]`） |
    | 代码格式化 | `⇧⌥ F` | 代码文件默认单栏语法高亮，支持一键格式化 |
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
    """
}
