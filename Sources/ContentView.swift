import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar

                Rectangle()
                    .fill(Color(white: 0.15))
                    .frame(height: 1)

                HSplitView {
                    if state.isSidebarVisible {
                        SidebarView(state: state)
                            .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
                    }

                    workspaceArea
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }

                Rectangle()
                    .fill(Color(white: 0.15))
                    .frame(height: 1)

                statusBar
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.11))

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
                            Text("松开以打开文件或文件夹")
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

    private var topBar: some View {
        HStack(spacing: 10) {
            // Space for native macOS traffic lights
            Spacer().frame(width: 68)

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    state.isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(state.isSidebarVisible ? Color(white: 0.88) : Color(white: 0.50))
                    .frame(width: 26, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(state.isSidebarVisible ? Color.white.opacity(0.08) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("显示/隐藏目录 (⌘\\)")

            Spacer()

            HStack(spacing: 6) {
                Text(state.displayFileName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color(white: 0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if state.isDirty {
                    Circle()
                        .fill(Color(red: 0.478, green: 0.635, blue: 0.969))
                        .frame(width: 6, height: 6)
                        .help("有未保存的更改")
                }
            }

            Spacer()

            // View mode switcher
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            state.viewMode = mode
                        }
                    } label: {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 12))
                            .foregroundStyle(state.viewMode == mode ? Color.white : Color(white: 0.52))
                            .frame(width: 28, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(state.viewMode == mode ? Color.white.opacity(0.12) : Color.clear)
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
                    .font(.system(size: 11.5))
                    .foregroundStyle(state.isWidthPopoverPresented ? Color(red: 0.478, green: 0.635, blue: 0.969) : Color(white: 0.65))
                    .frame(width: 26, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(state.isWidthPopoverPresented ? Color.white.opacity(0.08) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("调整预览行宽 (⌘[ / ⌘] / ⌘0)")
            .popover(isPresented: $state.isWidthPopoverPresented, arrowEdge: .bottom) {
                widthControlPopover
            }

            Button {
                state.openFilePanel()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(white: 0.65))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help("打开文件 (⌘O)")

            Button {
                state.saveDocument()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12.5))
                    .foregroundStyle(state.isDirty ? Color(red: 0.478, green: 0.635, blue: 0.969) : Color(white: 0.65))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help("保存 (⌘S)")
        }
        .padding(.trailing, 12)
        .frame(height: 38)
        .background(Color(red: 0.102, green: 0.104, blue: 0.114)) // #1A1A1D
    }

    @ViewBuilder
    private var workspaceArea: some View {
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

    private var editorPane: some View {
        DarkTextEditor(
            text: Binding(
                get: { state.text },
                set: { state.updateText($0) }
            ),
            formatAction: state.pendingFormatAction,
            formatRequestID: state.formatRequestID,
            onScroll: { fraction in
                state.scrollFraction = fraction
            },
            onFileDrop: { urls in
                if let first = urls.first {
                    state.handleOpen(url: first)
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
            scrollFraction: state.scrollFraction,
            maxWidth: state.effectivePreviewMaxWidth
        )
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Text(state.currentFileURL?.path ?? "本地草稿（未保存）")
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.48))
                .lineLimit(1)
                .truncationMode(.middle)

            if let toast = state.statusMessage {
                Text("· \(toast)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.478, green: 0.635, blue: 0.969))
                    .transition(.opacity)
            }

            Spacer()

            Button {
                state.isWidthPopoverPresented.toggle()
            } label: {
                Text("宽 \(state.previewWidthLabel)")
                    .foregroundStyle(Color(white: 0.60))
            }
            .buttonStyle(.plain)
            .help("点击调整预览行宽")

            Text("\(state.lineCount) 行")
            Text("\(state.wordCount) 字")
            Text("\(state.characterCount) 字符")
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Color(white: 0.50))
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(Color(red: 0.086, green: 0.088, blue: 0.098))
    }

    private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else {
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url = url {
                DispatchQueue.main.async {
                    state.handleOpen(url: url)
                }
            }
        }
        return true
    }
}
