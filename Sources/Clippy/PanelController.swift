import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Search text + current selection, shared between the key handler and the SwiftUI view.
final class PanelViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedIndex = 0
    @Published var focusPulse = 0
    /// True only after the user clicks the search field. Typing filters only then.
    @Published var searchActive = false
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
        vm.searchActive = false
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
        panel.isMovableByWindowBackground = true   // draggable by empty areas
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
        let vf = screen.visibleFrame
        let size = panel.frame.size
        // Open next to the cursor (cursor just inside the top-left), clamped on-screen.
        var x = mouse.x - 28
        var y = mouse.y - size.height + 28
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
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
            // Typing only filters if the user clicked the search field first.
            // Otherwise close the panel and pass the keystroke to the app underneath.
            if !vm.searchActive {
                forwardKeyToPrevious(keyCode: event.keyCode, flags: event.modifierFlags)
                return nil
            }
            return event
        }
    }

    /// Closes the panel and re-sends a keystroke to the previously focused app.
    private func forwardKeyToPrevious(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        let prev = previousApp
        let cgFlags = PasteHelper.cgFlags(from: flags)
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            prev?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if PasteHelper.hasAccessibility(prompt: false) {
                    PasteHelper.postKey(keyCode: CGKeyCode(keyCode), flags: cgFlags)
                }
            }
        }
    }
}
