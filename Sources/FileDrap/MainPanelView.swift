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
            Label("FileDrap", systemImage: "shippingbox")
                .font(.headline)

            Spacer()

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
        }
        .padding(12)
    }

    private var content: some View {
        HSplitView {
            folderSidebar
                .frame(minWidth: 220, maxWidth: 280)
            fileList
                .frame(minWidth: 360)
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
            } else if store.fileItems.isEmpty {
                emptyState(
                    title: "No files",
                    detail: "This folder is empty or hidden files are filtered out."
                )
            } else {
                List(store.fileItems) { file in
                    FileRow(file: file, onOpenInFinder: {
                        store.openInFinder(file)
                    })
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
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .lineLimit(1)
                Text(file.url.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if file.isDirectory {
                Text("DIR")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Finder", action: onOpenInFinder)
        }
        .onTapGesture(count: 2, perform: onOpenInFinder)
        .onDrag {
            NSItemProvider(contentsOf: file.url) ?? NSItemProvider(object: file.url as NSURL)
        }
    }
}
