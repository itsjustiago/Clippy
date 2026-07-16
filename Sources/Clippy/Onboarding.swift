import SwiftUI
import AppKit

/// Tracks whether Accessibility is granted, refreshing live while the window is open.
final class OnboardingModel: ObservableObject {
    @Published var trusted = PasteHelper.hasAccessibility(prompt: false)
    private var timer: Timer?

    func startWatching() {
        trusted = PasteHelper.hasAccessibility(prompt: false)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.trusted = PasteHelper.hasAccessibility(prompt: false)
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
}

/// First-run welcome window: explains ⌥V and offers a button to enable auto-paste.
final class OnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = OnboardingModel()

    func show() {
        if window == nil { build() }
        model.startWatching()
        // Defer to the next runloop and force the window front — an accessory
        // (LSUIElement) app won't present a window reliably during launch otherwise.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.title = "Clippy"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(
            rootView: OnboardingView(model: model, onClose: { [weak self] in self?.window?.close() }))
        window = w
    }

    func windowWillClose(_ notification: Notification) {
        model.stopWatching()
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                AppIcon(systemName: "doc.on.clipboard.fill", size: 64)
                Text("Bem-vindo ao Clippy")
                    .font(.system(size: 22, weight: .bold))
                Text("O teu histórico de clipboard, tipo Win + V.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 14) {
                infoRow(icon: "keyboard",
                        title: "Abre com ⌥V",
                        text: "Carrega em Option + V em qualquer app para ver e colar do histórico.")
                infoRow(icon: "menubar.rectangle",
                        title: "Vive na barra de menus",
                        text: "Clica no ícone no topo do ecrã para opções e itens recentes.")
                accessibilityCard
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            Button(action: onClose) {
                Text("Começar").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Brand.tint)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
        }
        .frame(width: 460, height: 480)
    }

    private var accessibilityCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.trusted ? "checkmark.circle.fill" : "hand.raised.fill")
                .font(.system(size: 20))
                .foregroundStyle(model.trusted ? .green : .orange)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.trusted ? "Colar automático ativo" : "Ativar colar automático")
                    .font(.system(size: 14, weight: .semibold))
                Text(model.trusted
                     ? "Está tudo pronto — o item escolhido é colado sozinho."
                     : "Para o Clippy colar por ti, dá-lhe permissão de Acessibilidade.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.trusted {
                    Button("Conceder acesso…") { grantAccess() }
                        .controlSize(.small)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            (model.trusted ? Color.green : Color.orange).opacity(0.10),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder((model.trusted ? Color.green : Color.orange).opacity(0.22))
        )
        .animation(.easeInOut(duration: 0.2), value: model.trusted)
    }

    private func grantAccess() {
        // Triggers the system prompt, then opens the exact Settings pane.
        _ = PasteHelper.hasAccessibility(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func infoRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AppIcon(systemName: icon, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
