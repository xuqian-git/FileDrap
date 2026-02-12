import AppKit
import Foundation

@MainActor
final class FolderStore: ObservableObject {
    static let shared = FolderStore()

    @Published private(set) var folders: [FolderItem] = []
    @Published var selectedFolderID: FolderItem.ID?
    @Published private(set) var allFileItems: [FileItem] = []
    @Published private(set) var fileItems: [FileItem] = []
    @Published private(set) var recentFiles: [URL] = []
    @Published var showHiddenFiles = false
    @Published var sortByNameAscending = true
    @Published var searchQuery = "" {
        didSet { applyFilters() }
    }
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    private let foldersDefaultsKey = "savedFoldersV1"
    private let recentsDefaultsKey = "recentFilesV1"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let folderPicker: @MainActor () -> URL?
    private var loadTask: Task<Void, Never>?
    private var activeSecurityScopeURL: URL?
    private var activeSecurityScopeFolderID: FolderItem.ID?

    init(
        userDefaults: UserDefaults = .standard,
        folderPicker: @escaping @MainActor () -> URL? = FolderStore.defaultFolderPicker
    ) {
        self.userDefaults = userDefaults
        self.folderPicker = folderPicker
        loadFolders()
        loadRecents()
        selectedFolderID = folders.first?.id
        refreshFiles()
    }

    deinit {
        loadTask?.cancel()
    }

    var selectedFolder: FolderItem? {
        folders.first(where: { $0.id == selectedFolderID })
    }

    func addFolder() {
        guard let folderURL = folderPicker() else {
            return
        }
        addFolder(url: folderURL)
    }

    func addFolder(url: URL) {
        let standardizedPath = url.standardizedFileURL.path

        if folders.contains(where: { $0.path == standardizedPath }) {
            selectedFolderID = folders.first(where: { $0.path == standardizedPath })?.id
            refreshFiles()
            return
        }

        let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let folder = FolderItem(
            name: url.lastPathComponent,
            path: standardizedPath,
            bookmarkData: bookmarkData
        )

        folders.append(folder)
        selectedFolderID = folder.id
        persistFolders()
        refreshFiles()
    }

    func removeSelectedFolder() {
        guard let selectedFolderID else { return }
        removeFolder(id: selectedFolderID)
    }

    func removeFolder(id: FolderItem.ID) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else {
            return
        }

        if activeSecurityScopeFolderID == id {
            stopActiveFolderAccess()
        }

        folders.remove(at: idx)
        if folders.isEmpty {
            selectedFolderID = nil
            allFileItems = []
            fileItems = []
            stopActiveFolderAccess()
        } else {
            selectedFolderID = folders[max(0, idx - 1)].id
            refreshFiles()
        }
        persistFolders()
    }

    func refreshFiles() {
        guard let folder = selectedFolder else {
            loadTask?.cancel()
            isLoading = false
            allFileItems = []
            fileItems = []
            errorMessage = nil
            stopActiveFolderAccess()
            return
        }

        let folderURL = prepareFolderAccess(for: folder)
        let showHidden = showHiddenFiles
        let sortAscending = sortByNameAscending
        let query = searchQuery

        loadTask?.cancel()
        isLoading = true

        loadTask = Task { [weak self] in
            let result = await FolderStore.scanFolder(
                folderURL: folderURL,
                showHiddenFiles: showHidden,
                sortAscending: sortAscending,
                query: query
            )

            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.selectedFolderID == folder.id else { return }

            switch result {
            case .success(let items):
                self.allFileItems = items
                self.applyFilters()
                self.errorMessage = nil
            case .failure(let error):
                self.allFileItems = []
                self.fileItems = []
                self.errorMessage = "Failed to load files: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }

    func openInFinder(_ fileItem: FileItem) {
        markFileUsed(fileItem.url)
        NSWorkspace.shared.activateFileViewerSelecting([fileItem.url])
    }

    func moveItemToTrash(_ fileItem: FileItem) {
        do {
            try FileManager.default.trashItem(at: fileItem.url, resultingItemURL: nil)
            recentFiles.removeAll(where: { $0.path == fileItem.url.path })
            persistRecents()
            refreshFiles()
            errorMessage = nil
        } catch {
            errorMessage = "移到废纸篓失败：\(error.localizedDescription)"
        }
    }

    func renameItem(_ fileItem: FileItem) {
        guard let nextName = promptRenameName(for: fileItem.url.lastPathComponent) else {
            return
        }

        let trimmed = nextName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "名称不能为空"
            return
        }
        guard trimmed != fileItem.url.lastPathComponent else {
            return
        }

        let parentURL = fileItem.url.deletingLastPathComponent()
        let nextURL = parentURL.appendingPathComponent(trimmed, isDirectory: fileItem.isDirectory)

        if FileManager.default.fileExists(atPath: nextURL.path) {
            errorMessage = "重命名失败：目标名称已存在"
            return
        }

        do {
            try FileManager.default.moveItem(at: fileItem.url, to: nextURL)
            recentFiles = recentFiles.map { $0.path == fileItem.url.path ? nextURL : $0 }
            persistRecents()
            refreshFiles()
            errorMessage = nil
        } catch {
            errorMessage = "重命名失败：\(error.localizedDescription)"
        }
    }

    func revealCurrentFolderInFinder() {
        guard let folder = selectedFolder else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }

    func toggleSortOrder() {
        sortByNameAscending.toggle()
        applyFilters()
    }

    func toggleShowHidden() {
        showHiddenFiles.toggle()
        refreshFiles()
    }

    func markFileUsed(_ url: URL) {
        recentFiles.removeAll(where: { $0.path == url.path })
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 30 {
            recentFiles = Array(recentFiles.prefix(30))
        }
        persistRecents()
    }

    func clearRecentFiles() {
        recentFiles = []
        persistRecents()
    }

    private func applyFilters() {
        fileItems = FolderStore.sortAndFilter(
            items: allFileItems,
            query: searchQuery,
            sortAscending: sortByNameAscending
        )
    }

    private func loadFolders() {
        guard let data = userDefaults.data(forKey: foldersDefaultsKey),
              let decoded = try? decoder.decode([FolderItem].self, from: data) else {
            folders = []
            return
        }
        folders = decoded
    }

    private func persistFolders() {
        guard let data = try? encoder.encode(folders) else { return }
        userDefaults.set(data, forKey: foldersDefaultsKey)
    }

    private func loadRecents() {
        guard let paths = userDefaults.array(forKey: recentsDefaultsKey) as? [String] else {
            recentFiles = []
            return
        }
        recentFiles = paths.map { URL(fileURLWithPath: $0) }
    }

    private func persistRecents() {
        userDefaults.set(recentFiles.map(\.path), forKey: recentsDefaultsKey)
    }

    nonisolated static func sortAndFilter(items: [FileItem], query: String, sortAscending: Bool) -> [FileItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered: [FileItem]
        if trimmed.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { item in
                item.url.lastPathComponent.localizedCaseInsensitiveContains(trimmed)
            }
        }

        return filtered.sorted { lhs, rhs in
            let compare = lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent)
            return sortAscending ? (compare == .orderedAscending) : (compare == .orderedDescending)
        }
    }

    @MainActor
    private static func defaultFolderPicker() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    nonisolated private static func scanFolder(
        folderURL: URL,
        showHiddenFiles: Bool,
        sortAscending: Bool,
        query: String
    ) async -> Result<[FileItem], Error> {
        await Task.detached(priority: .userInitiated) {
            do {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                    options: [.skipsPackageDescendants]
                )

                let items = urls.compactMap { url -> FileItem? in
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
                    let isHidden = values?.isHidden ?? false
                    if !showHiddenFiles && isHidden {
                        return nil
                    }
                    return FileItem(url: url, isDirectory: values?.isDirectory ?? false)
                }

                return .success(sortAndFilter(items: items, query: query, sortAscending: sortAscending))
            } catch {
                return .failure(error)
            }
        }.value
    }

    private func prepareFolderAccess(for folder: FolderItem) -> URL {
        if activeSecurityScopeFolderID == folder.id, let activeSecurityScopeURL {
            return activeSecurityScopeURL
        }

        stopActiveFolderAccess()
        let rawURL = URL(fileURLWithPath: folder.path)

        guard let bookmarkData = folder.bookmarkData else {
            return rawURL
        }

        var stale = false
        guard let securedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return rawURL
        }

        if stale,
           let newData = try? securedURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
           ),
           let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index].bookmarkData = newData
            persistFolders()
        }

        if securedURL.startAccessingSecurityScopedResource() {
            activeSecurityScopeURL = securedURL
            activeSecurityScopeFolderID = folder.id
            return securedURL
        }

        return rawURL
    }

    private func stopActiveFolderAccess() {
        guard let activeSecurityScopeURL else { return }
        activeSecurityScopeURL.stopAccessingSecurityScopedResource()
        self.activeSecurityScopeURL = nil
        activeSecurityScopeFolderID = nil
    }

    private func promptRenameName(for currentName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "重命名"
        alert.informativeText = "请输入新的名称"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = currentName
        alert.accessoryView = textField

        let result = alert.runModal()
        guard result == .alertFirstButtonReturn else {
            return nil
        }
        return textField.stringValue
    }
}
