import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var vm: PanelViewModel
    let onChoose: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onClearAll: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var clearHovering = false

    var body: some View {
        let items = vm.filtered()
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.4)
            if items.isEmpty {
                emptyState
            } else {
                list(items)
            }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 440, height: 540)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
        .onAppear { searchFocused = true }
        .onChange(of: vm.focusPulse) {
            searchFocused = true
        }
        .onChange(of: vm.query) { vm.selectedIndex = 0 }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Pesquisar no histórico…", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - List

    private func list(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipRow(item: item,
                                index: index,
                                selected: index == clampedSelection(items.count),
                                thumbnail: item.kind == .image ? store.thumbnail(for: item) : nil,
                                onChoose: { onChoose(item) },
                                onDelete: { onDelete(item) },
                                onTogglePin: { onTogglePin(item) })
                            .id(item.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: vm.selectedIndex) {
                let idx = clampedSelection(items.count)
                if items.indices.contains(idx) {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(items[idx].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func clampedSelection(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(vm.selectedIndex, 0), count - 1)
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: vm.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(vm.query.isEmpty ? "Sem histórico ainda" : "Sem resultados")
                .foregroundStyle(.secondary)
            if vm.query.isEmpty {
                Text("Copia algo (⌘C) e aparece aqui.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        normalFooter
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }

    private var normalFooter: some View {
        HStack(spacing: 14) {
            hint("↵", "colar")
            hint("⌘⌫", "apagar")
            hint("esc", "fechar")
            Spacer()
            if !store.items.isEmpty {
                Button { onClearAll() } label: {
                    Label("Limpar", systemImage: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(clearHovering ? .red : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            clearHovering ? Color.red.opacity(0.14) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .onHover { clearHovering = $0 }
                .help("Limpar o histórico (mantém os fixados)")
                .animation(.easeInOut(duration: 0.12), value: clearHovering)
            }
            Text("\(store.items.count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(minWidth: 18, alignment: .trailing)
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Row

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let thumbnail: NSImage?
    let onChoose: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

    @State private var hovering = false
    @State private var trashHovering = false

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    content
                    meta
                }
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .contextMenu {
            Button(item.pinned ? "Desafixar" : "Fixar") { onTogglePin() }
            Button("Apagar", role: .destructive) { onDelete() }
        }
    }

    private var rowBackground: Color {
        if selected { return Color.accentColor.opacity(0.22) }
        if hovering { return Color.primary.opacity(0.06) }
        return .clear
    }

    // Trailing controls: pin toggle + (trash on hover / ⌘N otherwise)
    private var trailing: some View {
        HStack(spacing: 6) {
            Button(action: onTogglePin) {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(item.pinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(item.pinned ? "Desafixar" : "Fixar")
            .opacity(item.pinned || hovering ? 1 : 0)
            .allowsHitTesting(item.pinned || hovering)

            ZStack(alignment: .trailing) {
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 0 : 1)
                }
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(trashHovering ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help("Apagar")
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .onHover { trashHovering = $0 }
            }
            .frame(width: 22, alignment: .trailing)
        }
    }

    @ViewBuilder private var icon: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "text.alignleft")
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        if item.kind == .image {
            Text("Imagem").font(.system(size: 13, weight: .medium))
        } else {
            Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13))
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if let src = item.sourceApp {
                Text(src)
                Text("·")
            }
            Text(item.date, format: .relative(presentation: .numeric))
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }
}
