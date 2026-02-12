import Foundation

struct FolderItem: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var bookmarkData: Data?

    init(id: UUID = UUID(), name: String, path: String, bookmarkData: Data? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
    }
}

struct FileItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let isDirectory: Bool

    init(url: URL, isDirectory: Bool) {
        self.id = url.path
        self.url = url
        self.isDirectory = isDirectory
    }
}
