import SwiftUI
import AppKit
import Carbon.HIToolbox

final class SettingsModel: ObservableObject {
    @Published var shortcutDisplay = Shortcut.display
    @Published var recording = false
    @Published var launchAtLogin = LoginItem.isEnabled
    @Published var autoCheck = Updater.autoCheckEnabled
    @Published var updateStatus = ""
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
            checkNow: { [weak self] in self?.checkNow() })
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Definições do Clippy"
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
        Updater.check { [weak self] info in
            guard let self else { return }
            if let info {
                self.model.updateStatus = "Atualização disponível: \(info.version) — abre o menu 📋 para transferir."
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Shortcut
            VStack(alignment: .leading, spacing: 8) {
                Text("Atalho global").font(.headline)
                HStack(spacing: 10) {
                    Text("Abrir o histórico").foregroundStyle(.secondary)
                    Spacer()
                    Button(action: startRecording) {
                        Text(model.recording ? "Prime as teclas…" : model.shortcutDisplay)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .frame(minWidth: 96)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.recording)
                    Button("Repor", action: resetShortcut)
                        .buttonStyle(.borderless)
                        .disabled(model.recording)
                }
                Text(model.recording
                     ? "Prime a combinação (inclui ⌘, ⌥, ⌃ ou ⇧). Esc cancela."
                     : "Precisa de pelo menos um modificador (⌘, ⌥, ⌃ ou ⇧).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            Toggle("Abrir o Clippy no arranque", isOn: Binding(
                get: { model.launchAtLogin },
                set: { setLaunchAtLogin($0); model.launchAtLogin = LoginItem.isEnabled }))

            Divider()

            // Updates
            VStack(alignment: .leading, spacing: 8) {
                Text("Atualizações").font(.headline)
                Toggle("Procurar atualizações automaticamente", isOn: Binding(
                    get: { model.autoCheck },
                    set: { model.autoCheck = $0; setAutoCheck($0) }))
                HStack {
                    Text("Versão \(model.version)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Procurar agora", action: checkNow)
                }
                if !model.updateStatus.isEmpty {
                    Text(model.updateStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 430, height: 400)
    }
}
