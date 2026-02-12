import SwiftUI

@main
struct FileDrapApp: App {
    @StateObject private var store = FolderStore()

    var body: some Scene {
        MenuBarExtra {
            MainPanelView()
                .environmentObject(store)
                .frame(minWidth: 720, minHeight: 460)
        } label: {
            Image(systemName: "folder.badge.gearshape")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
