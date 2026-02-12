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

        folders.remove(at: idx)
        if folders.isEmpty {
            selectedFolderID = nil
            allFileItems = []
            fileItems = []
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
            return
        }

        let showHidden = showHiddenFiles
        let sortAscending = sortByNameAscending
        let query = searchQuery

        loadTask?.cancel()
        isLoading = true

        loadTask = Task { [weak self] in
            let result = await FolderStore.scanFolder(
                folder: folder,
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
        folder: FolderItem,
        showHiddenFiles: Bool,
        sortAscending: Bool,
        query: String
    ) async -> Result<[FileItem], Error> {
        await Task.detached(priority: .userInitiated) {
            var folderURL = URL(fileURLWithPath: folder.path)
            var accessStarted = false

            if let bookmarkData = folder.bookmarkData {
                var stale = false
                if let securedURL = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) {
                    folderURL = securedURL
                    accessStarted = securedURL.startAccessingSecurityScopedResource()
                }
            }

            defer {
                if accessStarted {
                    folderURL.stopAccessingSecurityScopedResource()
                }
            }

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
}
