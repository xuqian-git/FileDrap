import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyCenter: HotKeyCenter?
    private var quickPanelController: QuickPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = FolderStore.shared
        quickPanelController = QuickPanelController(store: store)

        let hotKeys = HotKeyCenter()
        hotKeys.onHotKeyPressed = { [weak self] in
            Task { @MainActor in
                self?.quickPanelController?.toggle()
            }
        }
        hotKeyCenter = hotKeys
    }
}
