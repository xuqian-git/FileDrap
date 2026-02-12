import AppKit
import SwiftUI

struct MainPanelView: View {
    @EnvironmentObject private var store: FolderStore

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Label("文件拖拖", systemImage: "shippingbox")
                .font(.headline)

            Spacer()

            TextField("Search files", text: $store.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Button {
                store.addFolder()
            } label: {
                Label("Add Folder", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Button {
                store.revealCurrentFolderInFinder()
            } label: {
                Label("Finder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(store.selectedFolder == nil)

            Button {
                store.toggleShowHidden()
            } label: {
                Image(systemName: store.showHiddenFiles ? "eye.fill" : "eye")
            }
            .help("Show or hide hidden files")

            Button {
                store.toggleSortOrder()
            } label: {
                Image(systemName: store.sortByNameAscending ? "arrow.down" : "arrow.up")
            }
            .help("Toggle sort order")

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    private var content: some View {
        HSplitView {
            folderSidebar
                .frame(minWidth: 220, maxWidth: 280)
            fileList
                .frame(minWidth: 420)
        }
    }

    private var folderSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $store.selectedFolderID) {
                ForEach(store.folders) { folder in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(folder.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(folder.path)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                    .tag(folder.id)
                }
            }
            .onChange(of: store.selectedFolderID) { _ in
                store.refreshFiles()
            }

            Divider()

            HStack {
                Text("Folders")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    store.removeSelectedFolder()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(store.selectedFolder == nil)
                .help("Remove selected folder")
            }
            .padding(10)
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }

            if store.selectedFolder == nil {
                emptyState(
                    title: "No folder selected",
                    detail: "Click Add Folder to add your frequently used paths."
                )
            } else if store.isLoading {
                ProgressView("Loading files...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.fileItems.isEmpty && store.searchQuery.isEmpty {
                emptyState(
                    title: "No files",
                    detail: "This folder is empty or hidden files are filtered out."
                )
            } else {
                List {
                    if store.searchQuery.isEmpty && !store.recentFiles.isEmpty {
                        Section {
                            ForEach(store.recentFiles, id: \.path) { url in
                                QuickFileRow(url: url) {
                                    store.markFileUsed(url)
                                    store.openInFinder(FileItem(url: url, isDirectory: false))
                                }
                            }
                        } header: {
                            HStack {
                                Text("Recent")
                                Spacer()
                                Button("Clear") {
                                    store.clearRecentFiles()
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }

                    Section(store.searchQuery.isEmpty ? "Current Folder" : "Search Results") {
                        ForEach(store.fileItems) { file in
                            FileRow(file: file, onOpenInFinder: {
                                store.openInFinder(file)
                            })
                        }
                    }
                }
                .listStyle(.inset)
                .padding(.top, 4)
            }
        }
    }

    private func emptyState(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct FileRow: View {
    let file: FileItem
    let onOpenInFinder: () -> Void

    var body: some View {
        QuickFileRow(url: file.url, onOpenInFinder: onOpenInFinder) {
            if file.isDirectory {
                Text("DIR")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct QuickFileRow<Trailing: View>: View {
    let url: URL
    let onOpenInFinder: () -> Void
    @ViewBuilder var trailing: Trailing

    init(
        url: URL,
        onOpenInFinder: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.url = url
        self.onOpenInFinder = onOpenInFinder
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                Text(url.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            trailing
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Finder", action: onOpenInFinder)
        }
        .onTapGesture(count: 2, perform: onOpenInFinder)
        .onDrag {
            let suggestedName = dragSuggestedName(for: url)
            if let provider = NSItemProvider(contentsOf: url) {
                provider.suggestedName = suggestedName
                return provider
            }
            let fallback = NSItemProvider(object: url as NSURL)
            fallback.suggestedName = suggestedName
            return fallback
        }
    }

    private func dragSuggestedName(for url: URL) -> String {
        if url.hasDirectoryPath {
            return url.lastPathComponent
        }
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? url.lastPathComponent : stem
    }
}
