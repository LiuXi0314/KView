import SwiftUI

struct SidebarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(state.rootFolderURL?.lastPathComponent ?? "目录")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.52))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    state.newEmptyFileInFolder()
                } label: {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(white: 0.52))
                }
                .buttonStyle(.plain)
                .help("在目录中新建空文件 (⇧⌘N)")

                Button {
                    state.openFolderPanel()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(white: 0.52))
                }
                .buttonStyle(.plain)
                .help("打开文件夹 (⇧⌘O)")

                if state.rootFolderURL != nil {
                    Button {
                        state.refreshSidebar()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(white: 0.52))
                    }
                    .buttonStyle(.plain)
                    .help("刷新目录")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if state.sidebarNodes.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color(white: 0.34))
                    Text(state.rootFolderURL == nil ? "拖入文件夹或点击打开" : "暂无可预览文件")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(white: 0.46))
                    Button("打开文件夹") {
                        state.openFolderPanel()
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(Color(white: 0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(state.sidebarNodes) { node in
                            SidebarNodeRow(node: node, state: state, depth: 0)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
            }
        }
        .background(Color(red: 0.075, green: 0.077, blue: 0.086)) // #131316
    }
}

private struct SidebarNodeRow: View {
    let node: FileNode
    @ObservedObject var state: AppState
    let depth: Int

    var isExpanded: Bool {
        !state.collapsedFolders.contains(node.url)
    }

    var isSelected: Bool {
        state.currentFileURL == node.url
    }

    private var iconName: String {
        switch node.fileKind {
        case .markdown: return "doc.richtext"
        case .image: return "photo"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private var iconColor: Color {
        if isSelected {
            return Color(red: 0.478, green: 0.635, blue: 0.969)
        }
        switch node.fileKind {
        case .markdown: return Color(white: 0.48)
        case .image: return Color(red: 0.59, green: 0.76, blue: 0.47).opacity(0.80)
        case .code: return Color(red: 0.88, green: 0.73, blue: 0.48).opacity(0.78)
        }
    }

    var body: some View {
        if node.isDirectory {
            VStack(alignment: .leading, spacing: 1) {
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        if state.collapsedFolders.contains(node.url) {
                            state.collapsedFolders.remove(node.url)
                        } else {
                            state.collapsedFolders.insert(node.url)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(white: 0.44))
                            .frame(width: 10)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97).opacity(0.76))
                        Text(node.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.76))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 12 + 6)
                    .padding(.trailing, 8)
                    .padding(.vertical, 4.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded, let children = node.children {
                    ForEach(children) { child in
                        SidebarNodeRow(node: child, state: state, depth: depth + 1)
                    }
                }
            }
        } else {
            Button {
                state.openFile(url: node.url)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(iconColor)
                        .frame(width: 14)
                    Text(node.name)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color(white: 0.72))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.leading, CGFloat(depth) * 12 + 21)
                .padding(.trailing, 8)
                .padding(.vertical, 4.5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.white.opacity(0.085) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
