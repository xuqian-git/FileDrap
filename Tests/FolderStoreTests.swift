import XCTest
@testable import FileDrap

@MainActor
final class FolderStoreTests: XCTestCase {
    func testFolderPersistenceRoundTrip() throws {
        let suiteName = "FileDrapTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)

        let store = FolderStore(userDefaults: defaults, folderPicker: { nil })
        store.addFolder(url: tempFolder)

        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders.first?.path, tempFolder.path)

        let reloaded = FolderStore(userDefaults: defaults, folderPicker: { nil })
        XCTAssertEqual(reloaded.folders.count, 1)
        XCTAssertEqual(reloaded.folders.first?.path, tempFolder.path)
    }

    func testSortAndFilter() {
        let urls = [
            URL(fileURLWithPath: "/tmp/Beta.txt"),
            URL(fileURLWithPath: "/tmp/alpha.txt"),
            URL(fileURLWithPath: "/tmp/Gamma.txt")
        ]
        let items = urls.map { FileItem(url: $0, isDirectory: false) }

        let asc = FolderStore.sortAndFilter(items: items, query: "", sortAscending: true)
        XCTAssertEqual(asc.map { $0.url.lastPathComponent }, ["alpha.txt", "Beta.txt", "Gamma.txt"])

        let desc = FolderStore.sortAndFilter(items: items, query: "", sortAscending: false)
        XCTAssertEqual(desc.map { $0.url.lastPathComponent }, ["Gamma.txt", "Beta.txt", "alpha.txt"])

        let filtered = FolderStore.sortAndFilter(items: items, query: "ga", sortAscending: true)
        XCTAssertEqual(filtered.map { $0.url.lastPathComponent }, ["Gamma.txt"])
    }

    func testDirectoryNavigationState() throws {
        let suiteName = "FileDrapTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let store = FolderStore(userDefaults: defaults, folderPicker: { nil })
        store.addFolder(url: root)

        XCTAssertEqual(store.currentDirectoryPath, root.path)
        XCTAssertFalse(store.canGoToParentDirectory)

        store.enterDirectory(FileItem(url: child, isDirectory: true))
        XCTAssertEqual(store.currentDirectoryPath, child.path)
        XCTAssertTrue(store.canGoToParentDirectory)

        store.goToParentDirectory()
        XCTAssertEqual(store.currentDirectoryPath, root.path)
        XCTAssertFalse(store.canGoToParentDirectory)
    }
}
