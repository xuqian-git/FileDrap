import AppKit
import SwiftUI

struct MainPanelView: View {
    @EnvironmentObject private var store: FolderStore
    @State private var renamingFileID: String?
    @State private var renamingText = ""
    @State private var selectedFileID: String?
    @State private var isPresentingAddFolderPanel = false

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
                presentAddFolderPanel()
            } label: {
                Label("Add Folder", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPresentingAddFolderPanel)

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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard store.selectedFolderID != folder.id else { return }
                        renamingFileID = nil
                        renamingText = ""
                        selectedFileID = nil
                        store.selectedFolderID = folder.id
                        store.refreshFiles()
                    }
                    .tag(folder.id)
                }
            }
            .onChange(of: store.selectedFolderID) { _ in
                renamingFileID = nil
                renamingText = ""
                selectedFileID = nil
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
                    Section {
                        ForEach(store.fileItems) { file in
                            FileRow(
                                file: file,
                                isSelected: selectedFileID == file.id,
                                isRenaming: renamingFileID == file.id,
                                renameText: $renamingText,
                                onPrimaryAction: {
                                    if file.isDirectory {
                                        renamingFileID = nil
                                        renamingText = ""
                                        selectedFileID = nil
                                        store.enterDirectory(file)
                                    } else {
                                        store.openFile(file)
                                    }
                                },
                                onStartRename: {
                                    renamingFileID = file.id
                                    selectedFileID = file.id
                                    renamingText = file.url.lastPathComponent
                                },
                                onCommitRename: {
                                    if store.renameItem(file, to: renamingText) {
                                        renamingFileID = nil
                                        renamingText = ""
                                    }
                                },
                                onCancelRename: {
                                    renamingFileID = nil
                                    renamingText = ""
                                },
                                onMoveToTrash: {
                                    if renamingFileID == file.id {
                                        renamingFileID = nil
                                        renamingText = ""
                                    }
                                    if selectedFileID == file.id {
                                        selectedFileID = nil
                                    }
                                    store.moveItemToTrash(file)
                                },
                                onEnterDirectory: {
                                    renamingFileID = nil
                                    renamingText = ""
                                    selectedFileID = nil
                                    store.enterDirectory(file)
                                },
                                onShowInFinder: {
                                    store.openInFinder(file)
                                },
                                onSelect: {
                                    selectedFileID = file.id
                                }
                            )
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(store.searchQuery.isEmpty ? "Current Folder" : "Search Results")
                                if store.searchQuery.isEmpty {
                                    Spacer()
                                    Button {
                                        renamingFileID = nil
                                        renamingText = ""
                                        selectedFileID = nil
                                        store.goToParentDirectory()
                                    } label: {
                                        Label("上一级", systemImage: "arrow.up.left")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(!store.canGoToParentDirectory)
                                }
                            }
                            if store.searchQuery.isEmpty {
                                Text(store.currentDirectoryPath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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

    private func presentAddFolderPanel() {
        guard !isPresentingAddFolderPanel else { return }
        isPresentingAddFolderPanel = true
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "选择文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "添加"
        panel.begin { response in
            defer { isPresentingAddFolderPanel = false }
            guard response == .OK, let url = panel.url else { return }
            store.addFolder(url: url)
        }
    }
}

private struct FileRow: View {
    let file: FileItem
    let isSelected: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    let onPrimaryAction: () -> Void
    let onStartRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onMoveToTrash: () -> Void
    let onEnterDirectory: () -> Void
    let onShowInFinder: () -> Void
    let onSelect: () -> Void

    var body: some View {
        QuickFileRow(
            url: file.url,
            isDirectory: file.isDirectory,
            isRenaming: isRenaming,
            renameText: $renameText,
            onPrimaryAction: onPrimaryAction,
            onRename: onStartRename,
            onCommitRename: onCommitRename,
            onCancelRename: onCancelRename,
            onMoveToTrash: onMoveToTrash,
            onEnterDirectory: onEnterDirectory,
            onShowInFinder: onShowInFinder,
            onSelect: onSelect
        ) {
            if file.isDirectory {
                Text("DIR")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .padding(.vertical, 1)
        )
    }
}

private struct QuickFileRow<Trailing: View>: View {
    let url: URL
    let isDirectory: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    let onPrimaryAction: () -> Void
    let onRename: (() -> Void)?
    let onCommitRename: (() -> Void)?
    let onCancelRename: (() -> Void)?
    let onMoveToTrash: (() -> Void)?
    let onEnterDirectory: (() -> Void)?
    let onShowInFinder: (() -> Void)?
    let onSelect: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @FocusState private var renameFieldFocused: Bool

    init(
        url: URL,
        isDirectory: Bool = false,
        isRenaming: Bool = false,
        renameText: Binding<String> = .constant(""),
        onPrimaryAction: @escaping () -> Void,
        onRename: (() -> Void)? = nil,
        onCommitRename: (() -> Void)? = nil,
        onCancelRename: (() -> Void)? = nil,
        onMoveToTrash: (() -> Void)? = nil,
        onEnterDirectory: (() -> Void)? = nil,
        onShowInFinder: (() -> Void)? = nil,
        onSelect: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.url = url
        self.isDirectory = isDirectory
        self.isRenaming = isRenaming
        self._renameText = renameText
        self.onPrimaryAction = onPrimaryAction
        self.onRename = onRename
        self.onCommitRename = onCommitRename
        self.onCancelRename = onCancelRename
        self.onMoveToTrash = onMoveToTrash
        self.onEnterDirectory = onEnterDirectory
        self.onShowInFinder = onShowInFinder
        self.onSelect = onSelect
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .focused($renameFieldFocused)
                        .onSubmit {
                            onCommitRename?()
                        }
                        .onExitCommand {
                            onCancelRename?()
                        }
                        .onAppear {
                            DispatchQueue.main.async {
                                renameFieldFocused = true
                            }
                        }
                } else {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                }
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
            if isDirectory, let onEnterDirectory {
                Button("进入文件夹", action: onEnterDirectory)
            }
            if isDirectory, (onRename != nil || onMoveToTrash != nil) {
                Divider()
            }
            if let onRename {
                Button("重命名", action: onRename)
            }
            if let onMoveToTrash {
                Button("移到废纸篓", role: .destructive, action: onMoveToTrash)
            }
            if onRename != nil || onMoveToTrash != nil {
                Divider()
            }
            if let onShowInFinder {
                Button("在 Finder 中显示", action: onShowInFinder)
            }
        }
        .overlay {
            if !isRenaming {
                MouseDownCaptureView(
                    onMouseDown: { onSelect?() },
                    onDoubleClick: { onPrimaryAction() }
                )
                .allowsHitTesting(true)
            }
        }
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

private struct MouseDownCaptureView: NSViewRepresentable {
    let onMouseDown: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onMouseDown = onMouseDown
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onMouseDown = onMouseDown
        nsView.onDoubleClick = onDoubleClick
    }

    final class CaptureView: NSView {
        var onMouseDown: (() -> Void)?
        var onDoubleClick: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            onMouseDown?()
            if event.clickCount == 2 {
                onDoubleClick?()
            }
            super.mouseDown(with: event)
        }
    }
}
