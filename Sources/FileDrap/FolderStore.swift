import AppKit
import Foundation

@MainActor
final class FolderStore: ObservableObject {
    static let shared = FolderStore()

    @Published private(set) var folders: [FolderItem] = []
    @Published var selectedFolderID: FolderItem.ID?
    @Published private(set) var allFileItems: [FileItem] = []
    @Published private(set) var fileItems: [FileItem] = []
    @Published private(set) var currentDirectoryPath = ""
    @Published var showHiddenFiles = false
    @Published var sortByNameAscending = true
    @Published var searchQuery = "" {
        didSet { applyFilters() }
    }
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    private let foldersDefaultsKey = "savedFoldersV1"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let folderPicker: @MainActor () -> URL?
    private var loadTask: Task<Void, Never>?
    private var activeSecurityScopeURL: URL?
    private var activeSecurityScopeFolderID: FolderItem.ID?
    private var browsingFolderID: FolderItem.ID?
    private var browsingDirectoryURL: URL?

    init(
        userDefaults: UserDefaults = .standard,
        folderPicker: @escaping @MainActor () -> URL? = FolderStore.defaultFolderPicker
    ) {
        self.userDefaults = userDefaults
        self.folderPicker = folderPicker
        loadFolders()
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
        if browsingFolderID == id {
            browsingFolderID = nil
            browsingDirectoryURL = nil
            currentDirectoryPath = ""
        }

        folders.remove(at: idx)
        if folders.isEmpty {
            selectedFolderID = nil
            allFileItems = []
            fileItems = []
            currentDirectoryPath = ""
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
            currentDirectoryPath = ""
            errorMessage = nil
            stopActiveFolderAccess()
            return
        }

        let rootURL = prepareFolderAccess(for: folder)
        if browsingFolderID != folder.id {
            browsingFolderID = folder.id
            browsingDirectoryURL = rootURL
        }

        guard let browsingURL = normalizeBrowsingDirectory(rootURL: rootURL) else {
            browsingDirectoryURL = rootURL
            currentDirectoryPath = rootURL.path
            errorMessage = "当前目录不可访问，已回到根目录"
            refreshFiles()
            return
        }

        currentDirectoryPath = browsingURL.path
        let showHidden = showHiddenFiles
        let sortAscending = sortByNameAscending
        let query = searchQuery

        loadTask?.cancel()
        isLoading = true

        loadTask = Task { [weak self] in
            let result = await FolderStore.scanFolder(
                folderURL: browsingURL,
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
        NSWorkspace.shared.activateFileViewerSelecting([fileItem.url])
    }

    var canGoToParentDirectory: Bool {
        guard let root = activeSecurityScopeURL ?? selectedFolder.map({ URL(fileURLWithPath: $0.path) }),
              let current = browsingDirectoryURL else {
            return false
        }
        return current.standardizedFileURL.path != root.standardizedFileURL.path
    }

    func enterDirectory(_ fileItem: FileItem) {
        guard fileItem.isDirectory else { return }
        browsingDirectoryURL = fileItem.url
        refreshFiles()
    }

    func goToParentDirectory() {
        guard canGoToParentDirectory, let current = browsingDirectoryURL else { return }
        browsingDirectoryURL = current.deletingLastPathComponent()
        refreshFiles()
    }

    func moveItemToTrash(_ fileItem: FileItem) {
        do {
            try FileManager.default.trashItem(at: fileItem.url, resultingItemURL: nil)
            refreshFiles()
            errorMessage = nil
        } catch {
            errorMessage = "移到废纸篓失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func renameItem(_ fileItem: FileItem, to nextName: String) -> Bool {
        let trimmed = nextName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "名称不能为空"
            return false
        }
        guard trimmed != fileItem.url.lastPathComponent else {
            return true
        }

        let parentURL = fileItem.url.deletingLastPathComponent()
        let nextURL = parentURL.appendingPathComponent(trimmed, isDirectory: fileItem.isDirectory)

        if FileManager.default.fileExists(atPath: nextURL.path) {
            errorMessage = "重命名失败：目标名称已存在"
            return false
        }

        do {
            try FileManager.default.moveItem(at: fileItem.url, to: nextURL)
            refreshFiles()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "重命名失败：\(error.localizedDescription)"
            return false
        }
    }

    func revealCurrentFolderInFinder() {
        let path = browsingDirectoryURL?.path ?? selectedFolder?.path
        guard let path else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    func toggleSortOrder() {
        sortByNameAscending.toggle()
        applyFilters()
    }

    func toggleShowHidden() {
        showHiddenFiles.toggle()
        refreshFiles()
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

    private func normalizeBrowsingDirectory(rootURL: URL) -> URL? {
        let rootPath = rootURL.standardizedFileURL.path
        guard let candidate = browsingDirectoryURL else {
            browsingDirectoryURL = rootURL
            return rootURL
        }

        let candidatePath = candidate.standardizedFileURL.path
        guard candidatePath.hasPrefix(rootPath),
              FileManager.default.fileExists(atPath: candidatePath) else {
            return nil
        }
        return candidate
    }

}
