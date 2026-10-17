import SwiftUI

import UniformTypeIdentifiers

/// Abhakbare Agenda. Zeilen wachsen mit dem Text, mit „+“ oder Enter kommt ein neuer Punkt dazu,
/// Löschtaste in einer leeren Zeile entfernt sie. Sortieren per Drag & Drop am Griff,
/// mit den Pfeilen oder mit ⌥⌘↑ / ⌥⌘↓.
struct AgendaChecklist: View {
    @Binding var items: [AgendaItem]
    var placeholder = "Agendapunkt"
    var addLabel = "Punkt hinzufügen"
    /// Zeigt, welche Punkte schon an Things übertragen wurden.
    var showsThingsState = false
    @FocusState private var focused: UUID?
    @State private var hovered: UUID?
    @State private var dragging: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($items) { $item in
                row($item)
            }

            HStack {
                Button(action: { add(after: nil) }) {
                    Label(L(addLabel), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Neuen Agendapunkt hinzufügen")

                Spacer()

                let filled = items.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                if !filled.isEmpty {
                    Text(L("%d von %d erledigt", filled.filter(\.done).count, filled.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, items.isEmpty ? 0 : 4)
        }
    }

    private func row(_ item: Binding<AgendaItem>) -> some View {
        let id = item.wrappedValue.id
        let index = items.firstIndex(where: { $0.id == id }) ?? 0
        let active = hovered == id || focused == id
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 14)
                .opacity(active ? 1 : 0.35)
                .contentShape(Rectangle())
                .onDrag {
                    dragging = id
                    // Eigenes Format statt Text, damit die Sortierung keine Drags
                    // aus Finder oder Mail abfängt
                    let p = NSItemProvider()
                    p.registerDataRepresentation(forTypeIdentifier: UTType.agendaItem.identifier, visibility: .ownProcess) { done in
                        done(Data(id.uuidString.utf8), nil)
                        return nil
                    }
                    return p
                }
                .help("Ziehen zum Verschieben")

            Button {
                item.wrappedValue.done.toggle()
            } label: {
                Image(systemName: item.wrappedValue.done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(item.wrappedValue.done ? Color.accentColor : Color.secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help(item.wrappedValue.done ? L("Als offen markieren") : L("Abhaken"))

            TextField(L(placeholder), text: item.text, axis: .vertical)
                .textFieldStyle(.plain)
                .strikethrough(item.wrappedValue.done, color: .secondary)
                .foregroundStyle(item.wrappedValue.done ? .secondary : .primary)
                .focused($focused, equals: id)
                .onSubmit { add(after: id) }
                .onKeyPress(.delete) {
                    guard item.wrappedValue.text.isEmpty else { return .ignored }
                    remove(id, focusPrevious: true)
                    return .handled
                }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    guard press.modifiers.contains(.command), press.modifiers.contains(.option) else { return .ignored }
                    move(id, by: press.key == .upArrow ? -1 : 1)
                    return .handled
                }

            if showsThingsState && item.wrappedValue.sentToThings {
                Image(systemName: "paperplane.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("An Things übertragen")
            }

            HStack(spacing: 2) {
                Button { move(id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                    .help("Nach oben (⌥⌘↑)")
                Button { move(id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == items.count - 1)
                    .help("Nach unten (⌥⌘↓)")
                Button { remove(id, focusPrevious: false) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .help("Punkt entfernen")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .opacity(active ? 1 : 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(active ? Color.primary.opacity(0.05) : .clear))
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
        .onDrop(of: [.agendaItem], delegate: AgendaDropDelegate(target: id, items: $items, dragging: $dragging))
        .contextMenu {
            Button("Darunter einfügen") { add(after: id) }
            Button("Nach oben") { move(id, by: -1) }
            Button("Nach unten") { move(id, by: 1) }
            if showsThingsState {
                Divider()
                if item.wrappedValue.sentToThings {
                    Button("Beim nächsten Senden erneut übertragen") { item.wrappedValue.sentToThings = false }
                } else {
                    Button("Als übertragen markieren") { item.wrappedValue.sentToThings = true }
                }
            }
            Divider()
            Button("Entfernen", role: .destructive) { remove(id, focusPrevious: false) }
        }
    }

    private func add(after id: UUID?) {
        let new = AgendaItem()
        if let id, let i = items.firstIndex(where: { $0.id == id }) {
            items.insert(new, at: i + 1)
        } else {
            items.append(new)
        }
        DispatchQueue.main.async { focused = new.id }
    }

    private func remove(_ id: UUID, focusPrevious: Bool) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: i)
        if focusPrevious, i > 0 {
            let prev = items[i - 1].id
            DispatchQueue.main.async { focused = prev }
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard items.indices.contains(j) else { return }
        withAnimation(.snappy(duration: 0.2)) { items.swapAt(i, j) }
    }
}

extension UTType {
    /// Interner Typ für das Verschieben von Agendapunkten (in Info.plist deklariert).
    static let agendaItem = UTType(exportedAs: "io.github.note4meet.agenda-item")
}

/// Verschiebt den gezogenen Punkt live an die Position, über der er gerade schwebt.
private struct AgendaDropDelegate: DropDelegate {
    let target: UUID
    @Binding var items: [AgendaItem]
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = items.firstIndex(where: { $0.id == dragging }),
              let to = items.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
