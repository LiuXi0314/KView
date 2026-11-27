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

struct FileNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?

    var isMarkdown: Bool {
        let ext = url.pathExtension.lowercased()
        return ["md", "markdown", "mdown", "mkd", "mdx"].contains(ext)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var text: String = AppState.welcomeMarkdown
    @Published var currentFileURL: URL?
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

    private var statusClearTask: Task<Void, Never>?

    var displayFileName: String {
        currentFileURL?.lastPathComponent ?? "未命名.md"
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
        guard isDirty else { return true }
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

    func newDocument() {
        guard confirmDiscardIfNeeded() else { return }
        currentFileURL = nil
        text = "# 未命名文档\n\n"
        isDirty = false
        scrollFraction = 0
        showToast("已新建文档")
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择 Markdown 文件或文件夹"
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
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            currentFileURL = url
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
        if let url = currentFileURL {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                isDirty = false
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
        let panel = NSSavePanel()
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "Untitled.md"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            currentFileURL = url
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
        guard depth < 5 else { return [] }
        let fm = FileManager.default
        let ignoredNames: Set<String> = [
            ".git", ".build", ".swiftpm", "node_modules", ".DS_Store", "DerivedData", "Pods"
        ]
        let allowedExtensions: Set<String> = [
            "md", "markdown", "mdown", "mkd", "mdx", "txt",
            "json", "yaml", "yml", "swift", "py", "js", "ts", "html", "css"
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
            if ignoredNames.contains(name) { continue }
            let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = resourceValues?.isDirectory ?? false

            if isDir {
                let sub = buildTree(at: item, depth: depth + 1)
                if !sub.isEmpty {
                    dirs.append(FileNode(id: item, url: item, name: name, isDirectory: true, children: sub))
                }
            } else {
                let ext = item.pathExtension.lowercased()
                if allowedExtensions.contains(ext) {
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

    一款专注、轻量的 **macOS 深色模式 Markdown 编辑器与实时预览工具**。

    ## 常用快捷键

    | 操作 | 快捷键 | 说明 |
    | :--- | :--- | :--- |
    | 切换侧边目录 | `⌘ \\` | 折叠或展开左侧文件树 |
    | 仅编辑 / 双栏 / 仅预览 | `⌘ 1` / `⌘ 2` / `⌘ 3` | 一键切换视图布局 |
    | 打开 / 保存 | `⌘ O` / `⌘ S` | 支持直接拖拽文件或文件夹到窗口 |
    | 加粗 / 斜体 / 行内代码 | `⌘ B` / `⌘ I` / `⌘ E` | 快速包裹选中文本 |

    ## 代码块语法高亮

    ```swift
    import SwiftUI

    struct NoteCard: View {
        let title: String
        let wordCount: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text("\\(wordCount) 字").foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    ```

    ```python
    def render_markdown(source: str) -> str:
        # 轻量实时解析，支持深色排版与同步滚动
        lines = [line.strip() for line in source.splitlines()]
        return "\\n".join(lines)
    ```

    ## 待办与引用

    > 保持界面克制，把注意力留给文字本身。

    - [x] 纯深色护眼配色
    - [x] 左右分栏实时预览与同步滚动
    - [x] 拖拽本地 `.md` 文件或文件夹直接打开
    - [ ] 开始写你的第一篇笔记
    """
}
