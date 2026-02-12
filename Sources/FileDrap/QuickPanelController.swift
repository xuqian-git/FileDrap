import AppKit
import SwiftUI

@MainActor
final class QuickPanelController {
    private let panel: NSPanel

    init(store: FolderStore) {
        let root = MainPanelView()
            .environmentObject(store)
            .frame(minWidth: 720, minHeight: 460)

        let hostView = NSHostingView(rootView: root)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "FileDrap"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()
        panel.contentView = hostView
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }
}
