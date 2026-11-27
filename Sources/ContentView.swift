import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

struct ContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                unifiedHeaderBar

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                HSplitView {
                    if state.isSidebarVisible {
                        SidebarView(state: state)
                            .frame(minWidth: 180, idealWidth: 215, maxWidth: 300)
                    }

                    workspaceArea
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)

                statusBar
            }
            .background(Color(red: 0.094, green: 0.096, blue: 0.106))

            if state.isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(red: 0.478, green: 0.635, blue: 0.969), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.62))
                    )
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 30, weight: .light))
                                .foregroundStyle(Color(red: 0.478, green: 0.635, blue: 0.969))
                            Text("松开以在新标签页打开文件或文件夹")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    )
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .onDrop(of: [.fileURL], isTargeted: $state.isDropTargeted) { providers in
            handleDropProviders(providers)
        }
    }

    // MARK: - Single Unified Minimalist Top Bar (Zed / Obsidian style)

    private var unifiedHeaderBar: some View {
        ZStack {
            WindowDragHandle()

            HStack(spacing: 6) {
                // Exact clearance for native traffic lights inside fullSizeContentView
                Spacer().frame(width: 72)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        state.isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12.5))
                        .foregroundStyle(state.isSidebarVisible ? Color(white: 0.85) : Color(white: 0.46))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("显示/隐藏目录 (⌘\\)")

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 2)

                // Inline Multi-Tab Strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(state.tabs) { tab in
                            tabItemView(tab)
                        }

                        Button {
                            state.newDocument()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(white: 0.50))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("新建空标签页 (⌘T)")
                    }
                    .padding(.vertical, 6)
                }

                Spacer(minLength: 8)

                // Right minimalist contextual actions
                HStack(spacing: 4) {
                    if state.currentFileKind.isMarkdown {
                        HStack(spacing: 1) {
                            ForEach(ViewMode.allCases) { mode in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.14)) {
                                        state.viewMode = mode
                                    }
                                } label: {
                                    Image(systemName: mode.symbolName)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(state.viewMode == mode ? Color.white : Color(white: 0.48))
                                        .frame(width: 26, height: 22)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(state.viewMode == mode ? Color.white.opacity(0.11) : Color.clear)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(mode.rawValue)
                            }
                        }
                        .padding(2)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.white.opacity(0.04))
                        )

                        Button {
                            state.isWidthPopoverPresented.toggle()
                        } label: {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 11))
                                .foregroundStyle(state.isWidthPopoverPresented ? Color(red: 0.478, green: 0.635, blue: 0.969) : Color(white: 0.56))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("调整预览行宽 (⌘[ / ⌘] / ⌘0)")
                        .popover(isPresented: $state.isWidthPopoverPresented, arrowEdge: .bottom) {
                            widthControlPopover
                        }
                    }

                    if !state.currentFileKind.isImage {
                        Button {
                            state.formatCurrentCode()
                        } label: {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color(white: 0.58))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("格式化代码 / 文档 (⇧⌥F)")
                    }

                    if state.isDirty && !state.currentFileKind.isImage {
                        Button {
                            state.saveDocument()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color(red: 0.478, green: 0.635, blue: 0.969))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("保存更改 (⌘S)")
                    }
                }
            }
            .padding(.trailing, 10)
        }
        .frame(height: 38)
        .background(Color(red: 0.086, green: 0.088, blue: 0.098)) // #161619
    }

    private func tabItemView(_ tab: DocumentTab) -> some View {
        let isActive = (tab.id == state.activeTabID)
        return HStack(spacing: 5) {
            Image(systemName: tabIconName(for: tab.fileKind))
                .font(.system(size: 10))
                .foregroundStyle(tabIconColor(for: tab.fileKind, active: isActive))

            Text(tab.displayName)
                .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Color(white: 0.95) : Color(white: 0.56))
                .lineLimit(1)

            if tab.isDirty && !tab.fileKind.isImage {
                Circle()
                    .fill(Color(red: 0.478, green: 0.635, blue: 0.969))
                    .frame(width: 5, height: 5)
            }

            Button {
                state.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isActive ? Color(white: 0.56) : Color(white: 0.36))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("关闭标签页 (⌘W)")
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.white.opacity(0.085) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectTab(tab.id)
        }
    }

    private func tabIconName(for kind: FileKind) -> String {
        switch kind {
        case .markdown: return "doc.richtext"
        case .image: return "photo"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private func tabIconColor(for kind: FileKind, active: Bool) -> Color {
        if active {
            return Color(red: 0.478, green: 0.635, blue: 0.969)
        }
        switch kind {
        case .markdown: return Color(white: 0.46)
        case .image: return Color(red: 0.59, green: 0.76, blue: 0.47).opacity(0.75)
        case .code: return Color(red: 0.88, green: 0.73, blue: 0.48).opacity(0.75)
        }
    }

    // MARK: - Workspace Area

    @ViewBuilder
    private var workspaceArea: some View {
        if state.currentFileKind.isImage, let url = state.currentFileURL {
            ImagePreviewView(url: url, state: state)
        } else if state.currentFileKind.isCode {
            editorPane
        } else {
            switch state.viewMode {
            case .editorOnly:
                editorPane
            case .previewOnly:
                previewPane
            case .split:
                HSplitView {
                    editorPane
                        .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
                    previewPane
                        .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var editorPane: some View {
        DarkTextEditor(
            text: Binding(
                get: { state.text },
                set: { state.updateText($0) }
            ),
            tabID: state.activeTabID,
            fileKind: state.currentFileKind,
            formatAction: state.pendingFormatAction,
            formatRequestID: state.formatRequestID,
            onScroll: { fraction in
                state.scrollFraction = fraction
            },
            onFileDrop: { urls in
                for url in urls {
                    state.handleOpen(url: url)
                }
            }
        )
    }

    private var widthControlPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("预览行宽")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(state.previewWidthLabel)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color(red: 0.478, green: 0.635, blue: 0.969))
            }

            Toggle("充满剩余空间", isOn: Binding(
                get: { state.isFullPreviewWidth },
                set: { state.setFullPreviewWidth($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12))

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { state.previewMaxWidth },
                        set: { state.setPreviewWidth($0) }
                    ),
                    in: 600...2000,
                    step: 20
                )
                .tint(Color(red: 0.478, green: 0.635, blue: 0.969))

                HStack {
                    Text("600px")
                    Spacer()
                    Text("2000px")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.48))
            }
            .opacity(state.isFullPreviewWidth ? 0.45 : 1.0)

            HStack(spacing: 6) {
                presetWidthButton(label: "窄", px: 760)
                presetWidthButton(label: "标准", px: 960)
                presetWidthButton(label: "宽", px: 1280)
                Button {
                    state.setFullPreviewWidth(true)
                } label: {
                    Text("满宽")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(state.isFullPreviewWidth ? Color(red: 0.478, green: 0.635, blue: 0.969).opacity(0.25) : Color.white.opacity(0.07))
                        )
                        .foregroundStyle(state.isFullPreviewWidth ? Color(red: 0.65, green: 0.78, blue: 1.0) : Color(white: 0.80))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 248)
        .preferredColorScheme(.dark)
    }

    private func presetWidthButton(label: String, px: Double) -> some View {
        let active = !state.isFullPreviewWidth && abs(state.previewMaxWidth - px) < 1
        return Button {
            state.setPreviewWidth(px)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? Color(red: 0.478, green: 0.635, blue: 0.969).opacity(0.25) : Color.white.opacity(0.07))
                )
                .foregroundStyle(active ? Color(red: 0.65, green: 0.78, blue: 1.0) : Color(white: 0.80))
        }
        .buttonStyle(.plain)
    }

    private var previewPane: some View {
        MarkdownPreviewView(
            markdown: state.text,
            fileKind: state.currentFileKind,
            scrollFraction: state.scrollFraction,
            maxWidth: state.effectivePreviewMaxWidth
        )
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(state.currentFileURL?.path ?? "未保存草稿")
                .font(.system(size: 10.5))
                .foregroundStyle(Color(white: 0.42))
                .lineLimit(1)
                .truncationMode(.middle)

            if let toast = state.statusMessage {
                Text("· \(toast)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(red: 0.478, green: 0.635, blue: 0.969))
                    .transition(.opacity)
            }

            Spacer()

            Text(state.currentFileKind.displayLabel)
                .foregroundStyle(Color(red: 0.478, green: 0.635, blue: 0.969).opacity(0.80))

            if state.currentFileKind.isMarkdown {
                Button {
                    state.isWidthPopoverPresented.toggle()
                } label: {
                    Text("宽 \(state.previewWidthLabel)")
                        .foregroundStyle(Color(white: 0.54))
                }
                .buttonStyle(.plain)
                .help("点击调整预览行宽")
            }

            if !state.currentFileKind.isImage {
                Text("\(state.lineCount) 行")
                Text("\(state.wordCount) 字")
            }
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(Color(white: 0.45))
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(Color(red: 0.075, green: 0.077, blue: 0.086))
    }

    private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !matching.isEmpty else { return false }
        for provider in matching {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async {
                        state.handleOpen(url: url)
                    }
                }
            }
        }
        return true
    }
}
