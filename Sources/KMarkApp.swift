import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openURLHandler: ((URL) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let first = urls.first {
            openURLHandler?(first)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct KMarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .frame(minWidth: 760, minHeight: 500)
                .onAppear {
                    appDelegate.openURLHandler = { url in
                        state.handleOpen(url: url)
                    }
                    configureWindowAppearance()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建文档") { state.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)

                Button("打开文件...") { state.openFilePanel() }
                    .keyboardShortcut("o", modifiers: .command)

                Button("打开文件夹...") { state.openFolderPanel() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("保存") { state.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)

                Button("另存为...") { state.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandMenu("视图") {
                Button("切换左侧目录") {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        state.isSidebarVisible.toggle()
                    }
                }
                .keyboardShortcut("\\", modifiers: .command)

                Divider()

                Button("仅编辑模式") { state.viewMode = .editorOnly }
                    .keyboardShortcut("1", modifiers: .command)

                Button("双栏预览模式") { state.viewMode = .split }
                    .keyboardShortcut("2", modifiers: .command)

                Button("仅预览模式") { state.viewMode = .previewOnly }
                    .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button("加宽预览行宽") { state.widenPreview() }
                    .keyboardShortcut("]", modifiers: .command)

                Button("收窄预览行宽") { state.narrowPreview() }
                    .keyboardShortcut("[", modifiers: .command)

                Button("切换满宽预览") { state.toggleFullPreviewWidth() }
                    .keyboardShortcut("0", modifiers: .command)
            }

            CommandMenu("格式") {
                Button("加粗") { state.triggerFormat(.bold) }
                    .keyboardShortcut("b", modifiers: .command)

                Button("斜体") { state.triggerFormat(.italic) }
                    .keyboardShortcut("i", modifiers: .command)

                Button("行内代码") { state.triggerFormat(.inlineCode) }
                    .keyboardShortcut("e", modifiers: .command)

                Button("插入链接") { state.triggerFormat(.link) }
                    .keyboardShortcut("k", modifiers: .command)

                Button("二级标题") { state.triggerFormat(.heading) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
    }

    private func configureWindowAppearance() {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                window.appearance = NSAppearance(named: .darkAqua)
                window.titlebarAppearsTransparent = true
                window.backgroundColor = NSColor(red: 0.102, green: 0.104, blue: 0.114, alpha: 1.0)
                window.isMovableByWindowBackground = false
            }
        }
    }
}
