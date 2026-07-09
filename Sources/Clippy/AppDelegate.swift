import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = HistoryStore()
    private lazy var clipboard = ClipboardManager(store: store)
    private lazy var panelController = PanelController(store: store, clipboard: clipboard)
    private let onboarding = OnboardingController()
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.load()
        clipboard.start()
        setupStatusItem()

        // Global shortcut: ⌥V
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey))
        hotKey?.onFire = { [weak self] in self?.panelController.toggle() }
        writeLaunchStatus()

        // Welcome window on first launch.
        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            onboarding.show()
        }
    }

    private func writeLaunchStatus() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clippy", isDirectory: true)
        let line = "hotkey=\(hotKey != nil) accessibility=\(PasteHelper.hasAccessibility(prompt: false)) items=\(store.items.count)\n"
        try? line.data(using: .utf8)?.write(to: base.appendingPathComponent("last-launch.txt"))
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clippy")
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    // Rebuild the menu each time it opens so recent items stay fresh.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Nudge to enable auto-paste while Accessibility isn't granted.
        if !PasteHelper.hasAccessibility(prompt: false) {
            let warn = addItem(to: menu, "⚠︎ Ativar colar automático…", #selector(showOnboarding))
            warn.attributedTitle = NSAttributedString(
                string: warn.title,
                attributes: [.foregroundColor: NSColor.systemOrange])
            menu.addItem(.separator())
        }

        let show = NSMenuItem(title: "Mostrar histórico", action: #selector(showPanel), keyEquivalent: "v")
        show.keyEquivalentModifierMask = [.option]
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())

        let recent = Array(store.orderedItems.prefix(6))
        if recent.isEmpty {
            let empty = NSMenuItem(title: "Sem histórico ainda", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (i, clip) in recent.enumerated() {
                let mi = NSMenuItem(title: clip.menuTitle,
                                    action: #selector(pickRecent(_:)),
                                    keyEquivalent: i < 9 ? "\(i + 1)" : "")
                mi.keyEquivalentModifierMask = [.command]
                mi.target = self
                mi.representedObject = clip.id.uuidString
                if clip.pinned { mi.state = .on }
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        addItem(to: menu, "Limpar histórico", #selector(clearHistory))
        let login = addItem(to: menu, "Abrir no arranque", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        addItem(to: menu, "Bem-vindo ao Clippy", #selector(showOnboarding))
        menu.addItem(.separator())
        let quit = addItem(to: menu, "Sair do Clippy", #selector(quit))
        quit.keyEquivalent = "q"
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func showPanel() { panelController.show() }

    @objc private func showOnboarding() { onboarding.show() }

    @objc private func pickRecent(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let clip = store.orderedItems.first(where: { $0.id.uuidString == idString }) else { return }
        panelController.pasteDirect(clip)
    }

    @objc private func clearHistory() { store.clearUnpinned() }
    @objc private func toggleLogin() { LoginItem.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Launch at login

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    static func toggle() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Clippy: login item error: \(error.localizedDescription)")
        }
    }
}
