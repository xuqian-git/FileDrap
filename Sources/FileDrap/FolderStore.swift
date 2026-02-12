import AppKit
import Foundation

@MainActor
final class FolderStore: ObservableObject {
    @Published private(set) var folders: [FolderItem] = []
    @Published var selectedFolderID: FolderItem.ID?
    @Published var fileItems: [FileItem] = []
    @Published var showHiddenFiles = false
    @Published var sortByNameAscending = true
    @Published var errorMessage: String?

    private let defaultsKey = "savedFoldersV1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        loadFolders()
        selectedFolderID = folders.first?.id
        refreshFiles()
    }

    var selectedFolder: FolderItem? {
        folders.first(where: { $0.id == selectedFolderID })
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        if folders.contains(where: { $0.path == folderURL.path }) {
            selectedFolderID = folders.first(where: { $0.path == folderURL.path })?.id
            refreshFiles()
            return
        }

        let bookmarkData = try? folderURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let folder = FolderItem(
            name: folderURL.lastPathComponent,
            path: folderURL.path,
            bookmarkData: bookmarkData
        )

        folders.append(folder)
        selectedFolderID = folder.id
        persistFolders()
        refreshFiles()
    }

    func removeSelectedFolder() {
        guard let selectedFolderID,
              let idx = folders.firstIndex(where: { $0.id == selectedFolderID }) else {
            return
        }

        folders.remove(at: idx)
        if folders.isEmpty {
            self.selectedFolderID = nil
            fileItems = []
        } else {
            self.selectedFolderID = folders[max(0, idx - 1)].id
            refreshFiles()
        }
        persistFolders()
    }

    func refreshFiles() {
        guard let folder = selectedFolder else {
            fileItems = []
            return
        }

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
                if stale,
                   let newData = try? securedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                   ),
                   let currentIndex = folders.firstIndex(where: { $0.id == folder.id }) {
                    folders[currentIndex].bookmarkData = newData
                    persistFolders()
                }
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
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .isHiddenKey],
                options: [.skipsPackageDescendants]
            )

            var nextItems = urls.compactMap { url -> FileItem? in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
                let isHidden = values?.isHidden ?? false
                if !showHiddenFiles && isHidden {
                    return nil
                }
                return FileItem(url: url, isDirectory: values?.isDirectory ?? false)
            }

            nextItems.sort { lhs, rhs in
                let l = lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent)
                return sortByNameAscending ? (l == .orderedAscending) : (l == .orderedDescending)
            }

            fileItems = nextItems
            errorMessage = nil
        } catch {
            fileItems = []
            errorMessage = "Failed to load files: \(error.localizedDescription)"
        }
    }

    func openInFinder(_ fileItem: FileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([fileItem.url])
    }

    func revealCurrentFolderInFinder() {
        guard let folder = selectedFolder else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }

    func toggleSortOrder() {
        sortByNameAscending.toggle()
        refreshFiles()
    }

    func toggleShowHidden() {
        showHiddenFiles.toggle()
        refreshFiles()
    }

    private func loadFolders() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? decoder.decode([FolderItem].self, from: data) else {
            folders = []
            return
        }
        folders = decoded
    }

    private func persistFolders() {
        guard let data = try? encoder.encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
