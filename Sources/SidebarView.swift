import SwiftUI

struct SidebarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(state.rootFolderURL?.lastPathComponent ?? "文件目录")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color(white: 0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    state.openFolderPanel()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.62))
                }
                .buttonStyle(.plain)
                .help("打开文件夹 (⇧⌘O)")

                if state.rootFolderURL != nil {
                    Button {
                        state.refreshSidebar()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(white: 0.62))
                    }
                    .buttonStyle(.plain)
                    .help("刷新目录")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()
                .background(Color(white: 0.16))

            if state.sidebarNodes.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color(white: 0.38))
                    Text(state.rootFolderURL == nil ? "未打开文件夹" : "暂无可预览文本文件")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.52))
                    Button("选择文件夹") {
                        state.openFolderPanel()
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(white: 0.18))
                    .foregroundStyle(Color(white: 0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(state.sidebarNodes) { node in
                            SidebarNodeRow(node: node, state: state, depth: 0)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }
            }
        }
        .background(Color(red: 0.082, green: 0.084, blue: 0.094)) // #151518
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

    var body: some View {
        if node.isDirectory {
            VStack(alignment: .leading, spacing: 2) {
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
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color(white: 0.48))
                            .frame(width: 10)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97).opacity(0.82))
                        Text(node.name)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color(white: 0.80))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 12 + 6)
                    .padding(.trailing, 8)
                    .padding(.vertical, 5)
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
                    Image(systemName: node.isMarkdown ? "doc.richtext" : "doc.text")
                        .font(.system(size: 11.5))
                        .foregroundStyle(
                            isSelected
                                ? Color(red: 0.478, green: 0.635, blue: 0.969)
                                : Color(white: 0.52)
                        )
                    Text(node.name)
                        .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color(white: 0.76))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.leading, CGFloat(depth) * 12 + 21)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color(red: 0.16, green: 0.19, blue: 0.25) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
