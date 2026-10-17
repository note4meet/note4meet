import SwiftUI

/// Das Fenster, das zum Meetingbeginn aufgeht.
struct BriefingView: View {
    enum Action { case close, edit }

    let meeting: Meeting
    var measuring = false
    let onAction: (Action) -> Void

    @EnvironmentObject private var store: NotesStore

    var body: some View {
        let note = store.note(for: meeting.id)
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 30)
                .padding(.bottom, 14)

            Divider()

            // Zum Messen der natürlichen Höhe ohne Scrollbereich, im Fenster mit
            if measuring {
                content(note)
            } else {
                ScrollView { content(note) }
                    .frame(minHeight: 100, maxHeight: .infinity)
            }

            Divider()

            HStack {
                Button("Bearbeiten") { onAction(.edit) }
                Spacer()
                Button("Schließen") { onAction(.close) }
                    .keyboardShortcut(.cancelAction)
                if let url = meeting.joinURL {
                    Button {
                        NSWorkspace.shared.open(url)
                        onAction(.close)
                    } label: {
                        Label("Beitreten", systemImage: "video.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
        .frame(width: 520)
    }

    private func content(_ note: MeetingNote?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            let sections = note?.filledSections ?? []
            ForEach(sections.filter { $0.label == "Ziel" }, id: \.label, content: sectionView)
            if let note, !note.filledAgenda.isEmpty {
                agendaView(note)
            }
            if let note, !note.attachments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Unterlagen", icon: "paperclip")
                    AttachmentList(attachments: note.attachments)
                        .padding(.horizontal, -6)
                }
            }
            ForEach(sections.filter { $0.label != "Ziel" }, id: \.label, content: sectionView)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
    }

    private func sectionView(_ section: (label: String, icon: String, text: String)) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel(section.label, icon: section.icon)
            LinkedText(Bullets.display(section.text))
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func agendaView(_ note: MeetingNote) -> some View {
        let items = note.filledAgenda
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionLabel("Agenda", icon: "checklist")
                Spacer()
                Text(verbatim: "\(items.filter(\.done).count)/\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                Button {
                    store.toggleAgendaItem(note: note.id, item: item.id)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: item.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.done ? Color.accentColor : Color.secondary)
                        Text(item.text)
                            .strikethrough(item.done, color: .secondary)
                            .foregroundStyle(item.done ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionLabel(_ label: String, icon: String) -> some View {
        Label(L(label), systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(startsText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(meeting.calendarColor)
                .textCase(.uppercase)
            Text(meeting.title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(Fmt.range(meeting))
                Text("·")
                Circle().fill(meeting.calendarColor).frame(width: 8, height: 8)
                Text(meeting.accountTitle)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var startsText: String {
        let minutes = Int((meeting.start.timeIntervalSinceNow / 60).rounded())
        if minutes > 0 { return L("Beginnt in %d Min.", minutes) }
        if minutes == 0 { return L("Beginnt jetzt") }
        return L("Läuft seit %d Min.", -minutes)
    }
}

/// Text, in dem URLs anklickbar sind.
struct LinkedText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return result
        }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url,
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result)
            else { continue }
            result[lower..<upper].link = url
        }
        return result
    }
}
