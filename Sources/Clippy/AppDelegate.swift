import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = HistoryStore()
    private lazy var clipboard = ClipboardManager(store: store)
    private lazy var panelController = PanelController(store: store, clipboard: clipboard)
    private let onboarding = OnboardingController()
    private let settings = SettingsController()
    private let updater = UpdateController()
    private let menuModel = ClipMenuModel()
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var lastPopoverClose = Date.distantPast
    private var availableUpdate: UpdateInfo? { didSet { menuModel.availableUpdate = availableUpdate } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.load()
        clipboard.start()
        setupStatusItem()

        registerHotKey()
        settings.onShortcutChanged = { [weak self] in self?.registerHotKey() }
        settings.onCheckedUpdate = { [weak self] info in self?.availableUpdate = info }
        settings.onStartUpdate = { [weak self] info in self?.updater.start(info) }
        writeLaunchStatus()

        // Welcome window on first launch.
        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            onboarding.show()
        }

        // Check GitHub for a newer release in the background.
        if Updater.autoCheckEnabled {
            Updater.check { [weak self] info in self?.availableUpdate = info }
        }

        // Debug hooks for verifying flows without clicking the menu.
        switch ProcessInfo.processInfo.environment["CLIPPY_DEBUG_WINDOW"] {
        case "settings":
            settings.show()
        case "panel":
            panelController.show()
        case "update":
            Updater.check { [weak self] info in
                if let info { self?.updater.start(info) }
            }
        default:
            break
        }
    }

    private func registerHotKey() {
        hotKey?.invalidate()
        hotKey = HotKey(keyCode: UInt32(Shortcut.keyCode), modifiers: Shortcut.carbonModifiers)
        hotKey?.onFire = { [weak self] in self?.panelController.toggle() }
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
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        buildPopover()
    }

    /// The menu-bar dropdown is a SwiftUI panel in an `NSPopover`, matching Facet.
    private func buildPopover() {
        let panel = MenuPanel(
            store: store,
            model: menuModel,
            onShowHistory: { [weak self] in self?.dismissPopover(); self?.panelController.show() },
            onPickRecent: { [weak self] item in self?.dismissPopover(); self?.panelController.pasteDirect(item) },
            onClear: { [weak self] in self?.dismissPopover(); self?.store.clearUnpinned() },
            onSettings: { [weak self] in self?.dismissPopover(); self?.settings.show() },
            onOnboarding: { [weak self] in self?.dismissPopover(); self?.onboarding.show() },
            onUpdate: { [weak self] in
                self?.dismissPopover()
                if let update = self?.availableUpdate { self?.updater.start(update) }
            },
            onGrantAccess: { [weak self] in self?.dismissPopover(); self?.grantAccessibility() },
            onQuit: { NSApp.terminate(nil) })

        let hosting = NSHostingController(rootView: panel)
        hosting.sizingOptions = .preferredContentSize

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.delegate = self
        pop.contentViewController = hosting
        popover = pop
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Clicking the icon while the popover is open dismisses it via the
            // transient behaviour first; don't let the same click reopen it.
            if Date().timeIntervalSince(lastPopoverClose) < 0.2 { return }
            // Refresh live state right before presenting.
            menuModel.shortcut = Shortcut.display
            menuModel.hasAccessibility = PasteHelper.hasAccessibility(prompt: false)
            menuModel.availableUpdate = availableUpdate
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverClose = Date()
    }

    private func dismissPopover() { popover?.performClose(nil) }

    private func grantAccessibility() {
        _ = PasteHelper.hasAccessibility(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Launch at login

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    static func toggle() { setEnabled(!isEnabled) }

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Clippy: login item error: \(error.localizedDescription)")
        }
    }
}
