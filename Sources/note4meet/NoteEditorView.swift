import SwiftUI

/// Editor für die Notizen zu einem Meeting. Speichert automatisch bei jeder Änderung.
struct NoteEditorView: View {
    let meeting: Meeting?

    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var windows: WindowManager
    @State private var draft: MeetingNote
    @State private var confirmDelete = false

    init(initial: MeetingNote, meeting: Meeting?) {
        self.meeting = meeting
        _draft = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Field(label: "Ziel", icon: "target", hint: "Was willst du aus dem Meeting mitnehmen?") {
                    TextField("", text: $draft.goal, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                }
                Field(label: "Agenda", icon: "checklist", hint: "Enter = neuer Punkt, Rechtsklick = verschieben") {
                    AgendaChecklist(items: $draft.agenda)
                }
                BulletField(label: "Teilnehmer & Kontext", icon: "person.2",
                            hint: "Wer ist dabei, was ist der Hintergrund?", text: $draft.people, minHeight: 60)
                Field(label: "Links", icon: "link", hint: "Dokumente, Decks, CRM-Eintrag …") {
                    PlainEditor(text: $draft.links, minHeight: 44)
                }
                attachmentsSection

                BulletField(label: "Notizen", icon: "note.text", hint: "Alles Weitere",
                            text: $draft.notes, minHeight: 140)

                Field(label: "Nächste Schritte", icon: "arrow.forward.circle", hint: "Gehen als Aufgaben für „Heute“ an Things") {
                    AgendaChecklist(items: $draft.nextSteps, placeholder: "Nächster Schritt",
                                    addLabel: "Schritt hinzufügen", showsThingsState: true)
                }
                Field(label: "Projekte", icon: "folder", hint: "Werden in Things als Projekte angelegt") {
                    AgendaChecklist(items: $draft.projects, placeholder: "Projekt",
                                    addLabel: "Projekt hinzufügen", showsThingsState: true)
                }
                thingsBar

                footer
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: draft) { _, new in store.save(new) }
        // Änderungen von einem anderen Mac (über den Sync-Ordner) übernehmen
        .onChange(of: store.note(for: draft.id)) { _, synced in
            if let synced, !synced.sameContent(as: draft) { draft = synced }
        }
        .confirmationDialog("Notizen zu diesem Meeting löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) {
                store.delete(draft.id)
                draft.goal = ""; draft.agenda = []; draft.attachments = []; draft.nextSteps = []; draft.projects = []; draft.people = ""; draft.links = ""; draft.notes = ""
                if meeting == nil { windows.selection = nil }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            let start = meeting?.start ?? draft.start
            let end = meeting?.end ?? draft.end
            Text(Fmt.day(start) + (Calendar.current.isDateInToday(start) || Calendar.current.isDateInTomorrow(start) ? ", " + Fmt.dayShort(start) : ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(meeting?.calendarColor ?? .secondary)
                .textCase(.uppercase)
            Text(meeting?.title ?? draft.title)
                .font(.largeTitle.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(meeting.map(Fmt.range) ?? "\(Fmt.time(start)) – \(Fmt.time(end))")
                Text("·")
                Text(meeting?.accountTitle ?? draft.calendarTitle)
                if let loc = meeting?.location, !loc.isEmpty, meeting?.joinURL?.absoluteString != loc {
                    Text("·")
                    Image(systemName: "mappin")
                    Text(loc).lineLimit(1)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if let url = meeting?.joinURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label("Meeting beitreten", systemImage: "video.fill")
                }
                .padding(.top, 4)
            }
            if meeting == nil {
                Text(end < Date() ? L("Vergangenes Meeting") : L("Dieses Meeting ist nicht mehr im ausgewählten Kalenderzeitraum."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var thingsBar: some View {
        let pending = draft.pendingForThings
        let count = pending.steps.count + pending.projects.count
        return HStack(spacing: 10) {
            Button {
                if ThingsExport.send(draft) {
                    let sentIDs = Set((pending.steps + pending.projects).map(\.id))
                    for i in draft.nextSteps.indices where sentIDs.contains(draft.nextSteps[i].id) {
                        draft.nextSteps[i].sentToThings = true
                    }
                    for i in draft.projects.indices where sentIDs.contains(draft.projects[i].id) {
                        draft.projects[i].sentToThings = true
                    }
                }
            } label: {
                Label("An Things senden", systemImage: "paperplane")
            }
            .buttonStyle(.borderedProminent)
            .disabled(count == 0)

            Text(thingsStatus(steps: pending.steps.count, projects: pending.projects.count))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func thingsStatus(steps: Int, projects: Int) -> String {
        if steps + projects == 0 {
            let any = !draft.filledNextSteps.isEmpty || !draft.filledProjects.isEmpty
            return any ? L("Alles übertragen") : L("Noch keine Schritte oder Projekte")
        }
        var parts: [String] = []
        if steps > 0 { parts.append(steps == 1 ? L("1 Schritt") : L("%d Schritte", steps)) }
        if projects > 0 { parts.append(projects == 1 ? L("1 Projekt") : L("%d Projekte", projects)) }
        return L("%@ neu", parts.joined(separator: L(" und ")))
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Dateien & E-Mails", systemImage: "paperclip").font(.headline)
                Text("Klick öffnet, Rechtsklick für mehr").font(.caption).foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                if !draft.attachments.isEmpty {
                    AttachmentList(
                        attachments: draft.attachments,
                        onRemove: { a in draft.attachments.removeAll { $0.id == a.id } },
                        onRename: { a, title in
                            let t = title.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty, let i = draft.attachments.firstIndex(where: { $0.id == a.id }) {
                                draft.attachments[i].title = t
                            }
                        }
                    )
                }
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                    Text("Dateien aus dem Finder, E-Mails aus Mail oder Links hierher ziehen")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                )
                .modifier(DropHighlight(active: windows.dropTargetID == draft.id))
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        }
    }

    private var footer: some View {
        HStack {
            if draft.isEmpty {
                Label("Ohne Notizen gibt es keine Meldung zum Meetingbeginn.", systemImage: "bell.slash")
            } else {
                Label("Gespeichert. Die Meldung kommt zum Meetingbeginn.", systemImage: "bell.badge")
            }
            Spacer()
            if !draft.isEmpty {
                Menu {
                    Button("Als Markdown (.md) …") { store.export(draft, asMarkdown: true) }
                    Button("Als Text (.txt) …") { store.export(draft, asMarkdown: false) }
                } label: {
                    Label("Exportieren", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Diesen Eintrag als Datei speichern")
            }
            if let meeting, !draft.isEmpty {
                Button("Meldung testen") { windows.showBriefing(meeting: meeting) }
            }
            if store.note(for: draft.id) != nil {
                Button("Löschen", role: .destructive) { confirmDelete = true }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

private struct Field<Content: View>: View {
    let label: String
    let icon: String
    let hint: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(L(label), systemImage: icon).font(.headline)
                Text(L(hint)).font(.caption).foregroundStyle(.tertiary)
            }
            content
                .font(.body)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        }
    }
}

/// Textfeld mit Aufzählungen und Knopf „Aufzählung“ in der Überschrift.
private struct BulletField: View {
    let label: String
    let icon: String
    let hint: String
    @Binding var text: String
    let minHeight: CGFloat
    @StateObject private var controller = BulletEditorController()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(L(label), systemImage: icon).font(.headline)
                Text(L(hint)).font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button { controller.toggleBullets() } label: {
                    Label("Aufzählung", systemImage: "list.bullet")
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .help("Aufzählung ein/aus (⌘⇧L) · Tab rückt ein, ⇧Tab rückt aus, „- “ am Zeilenanfang startet eine Aufzählung")
            }
            BulletTextEditor(text: $text, controller: controller)
                .frame(minHeight: minHeight, alignment: .top)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        }
    }
}

private struct PlainEditor: View {
    @Binding var text: String
    let minHeight: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(minHeight: minHeight)
            .fixedSize(horizontal: false, vertical: true)
    }
}
