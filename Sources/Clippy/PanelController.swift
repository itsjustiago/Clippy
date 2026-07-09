import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Search text + current selection, shared between the key handler and the SwiftUI view.
final class PanelViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedIndex = 0
    @Published var focusPulse = 0
    unowned let store: HistoryStore

    init(store: HistoryStore) { self.store = store }

    func filtered() -> [ClipItem] {
        let base = store.orderedItems
        guard !query.isEmpty else { return base }
        return base.filter { $0.searchText.localizedCaseInsensitiveContains(query) }
    }
}

/// Borderless panels can't become key by default — allow it so the search field works.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Builds and drives the floating history panel: showing, keyboard control, and paste-back.
final class PanelController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private let clipboard: ClipboardManager
    private let vm: PanelViewModel
    private var panel: FloatingPanel?
    private var monitor: Any?
    private var previousApp: NSRunningApplication?

    init(store: HistoryStore, clipboard: ClipboardManager) {
        self.store = store
        self.clipboard = clipboard
        self.vm = PanelViewModel(store: store)
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        if panel == nil { build() }
        guard let panel else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        vm.query = ""
        vm.selectedIndex = 0
        vm.focusPulse += 1
        position(panel)
        addMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        removeMonitor()
        panel?.orderOut(nil)
    }

    // MARK: - Building

    private func build() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self

        let root = ContentView(
            store: store, vm: vm,
            onChoose: { [weak self] in self?.choose($0) },
            onDelete: { [weak self] in self?.deleteSelected($0) },
            onTogglePin: { [weak self] in self?.store.togglePin($0) },
            onClearAll: { [weak self] in self?.clearAll() })
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.midY - size.height / 2 + screen.frame.height * 0.10
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Actions

    private func choose(_ item: ClipItem) {
        hide()
        clipboard.copyToPasteboard(item)
        pasteToPrevious()
    }

    /// Called from the menu-bar quick list (no panel involved).
    func pasteDirect(_ item: ClipItem) {
        previousApp = NSWorkspace.shared.frontmostApplication
        clipboard.copyToPasteboard(item)
        pasteToPrevious()
    }

    private func deleteSelected(_ item: ClipItem) {
        store.delete(item)
        vm.selectedIndex = min(vm.selectedIndex, max(0, vm.filtered().count - 1))
    }

    private func clearAll() {
        store.clearUnpinned()
        vm.selectedIndex = 0
    }

    private func pasteToPrevious() {
        let prev = previousApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            prev?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                if PasteHelper.hasAccessibility(prompt: true) {
                    PasteHelper.paste()
                }
            }
        }
    }

    // MARK: - Keyboard

    private func addMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let filtered = vm.filtered()
        let cmd = event.modifierFlags.contains(.command)

        switch Int(event.keyCode) {
        case kVK_Escape:
            hide(); return nil
        case kVK_DownArrow:
            if !filtered.isEmpty { vm.selectedIndex = min(vm.selectedIndex + 1, filtered.count - 1) }
            return nil
        case kVK_UpArrow:
            if !filtered.isEmpty { vm.selectedIndex = max(vm.selectedIndex - 1, 0) }
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if filtered.indices.contains(vm.selectedIndex) { choose(filtered[vm.selectedIndex]) }
            return nil
        case kVK_Delete where cmd:
            if filtered.indices.contains(vm.selectedIndex) { deleteSelected(filtered[vm.selectedIndex]) }
            return nil
        case kVK_ANSI_P where cmd:
            if filtered.indices.contains(vm.selectedIndex) { store.togglePin(filtered[vm.selectedIndex]) }
            return nil
        default:
            if cmd, let s = event.charactersIgnoringModifiers, let n = Int(s), (1...9).contains(n) {
                let idx = n - 1
                if filtered.indices.contains(idx) { choose(filtered[idx]) }
                return nil
            }
            return event
        }
    }
}
