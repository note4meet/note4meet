import SwiftUI

/// Liste der verlinkten Dateien, E-Mails und Webseiten. Klick öffnet den Anhang.
/// Mit `items`-Binding (Editor) lassen sich Einträge entfernen und umbenennen.
struct AttachmentList: View {
    let attachments: [Attachment]
    var onRemove: ((Attachment) -> Void)?
    var onRename: ((Attachment, String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(attachments) { a in
                AttachmentRow(attachment: a, onRemove: onRemove, onRename: onRename)
            }
        }
    }
}

private struct AttachmentRow: View {
    let attachment: Attachment
    var onRemove: ((Attachment) -> Void)?
    var onRename: ((Attachment, String) -> Void)?
    @State private var hover = false
    @State private var renaming = false
    @State private var newTitle = ""

    var body: some View {
        let available = attachment.isAvailable
        HStack(spacing: 8) {
            Group {
                if let icon = attachment.fileIcon {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                } else {
                    Image(systemName: attachment.symbol)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22, height: 22)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(available ? Color.primary : Color.secondary)
                Text(attachment.subtitle)
                    .font(.caption)
                    .foregroundStyle(available ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 4)
            if let onRemove {
                Button { onRemove(attachment) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .opacity(hover ? 1 : 0)
                .help("Verknüpfung entfernen (die Datei bleibt erhalten)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { attachment.open() }
        .help(available ? L("Klicken zum Öffnen") : L("Auf diesem Mac nicht gefunden"))
        .contextMenu {
            Button("Öffnen") { attachment.open() }.disabled(!available)
            if attachment.kind == .file {
                Button("Im Finder zeigen") { attachment.revealInFinder() }.disabled(!available)
            }
            Button("Link kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(attachment.exportLink, forType: .string)
            }
            if onRename != nil {
                Button("Umbenennen …") { newTitle = attachment.title; renaming = true }
            }
            if let onRemove {
                Divider()
                Button("Entfernen", role: .destructive) { onRemove(attachment) }
            }
        }
        .alert("Anzeigename", isPresented: $renaming) {
            TextField("Name", text: $newTitle)
            Button("Abbrechen", role: .cancel) {}
            Button("Speichern") { onRename?(attachment, newTitle) }
        }
    }
}

/// Hebt eine Fläche hervor, solange etwas darüber gezogen wird.
struct DropHighlight: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
                .opacity(active ? 1 : 0)
                .allowsHitTesting(false)
        )
    }
}
