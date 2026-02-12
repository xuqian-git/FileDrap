import AppKit
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
                .contextMenu {
                    Button("退出文件拖拖") {
                        NSApp.terminate(nil)
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
