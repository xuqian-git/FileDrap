import SwiftUI

@main
struct FileDrapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = FolderStore.shared

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
