import SwiftUI
import AppKit
import Carbon.HIToolbox

final class SettingsModel: ObservableObject {
    @Published var shortcutDisplay = Shortcut.display
    @Published var recording = false
    @Published var launchAtLogin = LoginItem.isEnabled
    @Published var autoCheck = Updater.autoCheckEnabled
    @Published var updateStatus = ""
    @Published var foundUpdate: UpdateInfo?
    let version = Updater.currentVersion
}

/// Preferences window: customise the global shortcut, launch-at-login and updates.
final class SettingsController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = SettingsModel()
    private var recordMonitor: Any?

    /// Called when the shortcut changes so the app can re-register the hotkey.
    var onShortcutChanged: (() -> Void)?
    /// Called after a manual update check so the menu can reflect the result.
    var onCheckedUpdate: ((UpdateInfo?) -> Void)?
    /// Called when the user asks to install an available update.
    var onStartUpdate: ((UpdateInfo) -> Void)?

    func show() {
        if window == nil { build() }
        model.shortcutDisplay = Shortcut.display
        model.launchAtLogin = LoginItem.isEnabled
        model.autoCheck = Updater.autoCheckEnabled
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.center()
            self?.window?.makeKeyAndOrderFront(nil)
            self?.window?.orderFrontRegardless()
        }
    }

    private func build() {
        let view = SettingsView(
            model: model,
            startRecording: { [weak self] in self?.startRecording() },
            resetShortcut: { [weak self] in self?.resetShortcut() },
            setLaunchAtLogin: { LoginItem.setEnabled($0) },
            setAutoCheck: { Updater.autoCheckEnabled = $0 },
            checkNow: { [weak self] in self?.checkNow() },
            startUpdate: { [weak self] info in self?.onStartUpdate?(info) })
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Definições do Clippy"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: view)
        window = w
    }

    private func startRecording() {
        guard recordMonitor == nil else { return }
        model.recording = true
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if Int(event.keyCode) == kVK_Escape && mods.isEmpty {
                self.stopRecording()
                return nil
            }
            guard !mods.isEmpty else {
                NSSound.beep()
                return nil
            }
            let display = Shortcut.displayString(keyCode: Int(event.keyCode),
                                                 modifiers: mods,
                                                 chars: event.charactersIgnoringModifiers)
            Shortcut.save(keyCode: Int(event.keyCode), modifiers: mods, display: display)
            self.model.shortcutDisplay = display
            self.stopRecording()
            self.onShortcutChanged?()
            return nil
        }
    }

    private func stopRecording() {
        if let recordMonitor { NSEvent.removeMonitor(recordMonitor) }
        recordMonitor = nil
        model.recording = false
    }

    private func resetShortcut() {
        Shortcut.resetToDefault()
        model.shortcutDisplay = Shortcut.display
        onShortcutChanged?()
    }

    private func checkNow() {
        model.updateStatus = "A procurar…"
        model.foundUpdate = nil
        Updater.check { [weak self] info in
            guard let self else { return }
            self.model.foundUpdate = info
            if let info {
                self.model.updateStatus = "Atualização disponível: \(info.version)."
            } else {
                self.model.updateStatus = "Estás na versão mais recente (\(self.model.version))."
            }
            self.onCheckedUpdate?(info)
        }
    }

    func windowWillClose(_ notification: Notification) { stopRecording() }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var startRecording: () -> Void
    var resetShortcut: () -> Void
    var setLaunchAtLogin: (Bool) -> Void
    var setAutoCheck: (Bool) -> Void
    var checkNow: () -> Void
    var startUpdate: (UpdateInfo) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                SettingsSection(title: "Atalho global") {
                    SettingsRow(
                        title: "Abrir o histórico",
                        subtitle: model.recording
                            ? "Prime a combinação (inclui ⌘, ⌥, ⌃ ou ⇧). Esc cancela."
                            : "Precisa de pelo menos um modificador."
                    ) {
                        HStack(spacing: 8) {
                            Button(action: startRecording) {
                                Text(model.recording ? "Prime as teclas…" : model.shortcutDisplay)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .frame(minWidth: 92)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.recording)
                            Button("Repor", action: resetShortcut)
                                .buttonStyle(.borderless)
                                .disabled(model.recording)
                        }
                    }
                }

                SettingsSection(title: "Arranque") {
                    ToggleRow(
                        title: "Abrir o Clippy no arranque",
                        subtitle: "Inicia automaticamente quando entras na sessão.",
                        isOn: Binding(
                            get: { model.launchAtLogin },
                            set: { setLaunchAtLogin($0); model.launchAtLogin = LoginItem.isEnabled }))
                }

                SettingsSection(title: "Atualizações") {
                    ToggleRow(
                        title: "Procurar automaticamente",
                        isOn: Binding(
                            get: { model.autoCheck },
                            set: { model.autoCheck = $0; setAutoCheck($0) }))
                    RowDivider()
                    SettingsRow(
                        title: "Versão \(model.version)",
                        subtitle: model.updateStatus.isEmpty ? nil : model.updateStatus
                    ) {
                        if let update = model.foundUpdate {
                            Button("Atualizar para \(update.version)") { startUpdate(update) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        } else {
                            Button("Procurar agora", action: checkNow)
                                .controlSize(.small)
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 440, height: 480)
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppIcon(systemName: "doc.on.clipboard.fill", size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Clippy").font(.title2.weight(.bold))
                Text("O teu histórico de clipboard, sempre à mão.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
