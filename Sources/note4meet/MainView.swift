import SwiftUI

/// Hauptfenster: Wochenansicht oder Liste (kommende Meetings / alle Notizen), dazu der Editor.
struct MainView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case upcoming = "Kommend"
        case notes = "Alle Notizen"
        var id: String { rawValue }
    }

    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var windows: WindowManager

    enum ViewMode: String, CaseIterable, Identifiable {
        case week = "Woche"
        case list = "Liste"
        var id: String { rawValue }
    }

    @AppStorage("viewMode") private var viewMode: ViewMode = .week
    @State private var mode: Mode = .upcoming
    @State private var query = ""

    var body: some View {
        Group {
            switch viewMode {
            case .week: weekLayout
            case .list: listLayout
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Meetings & Notizen durchsuchen")
        .onChange(of: query) { _, q in
            // Suchergebnisse erscheinen in der Liste, bei Bedarf inkl. vergangener Notizen
            guard !q.isEmpty else { return }
            viewMode = .list
            if mode == .upcoming && filteredUpcoming.isEmpty { mode = .notes }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Ansicht", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { Text(L($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItemGroup {
                Button { calendar.reload() } label: { Label("Aktualisieren", systemImage: "arrow.clockwise") }
                    .help("Kalender neu laden")
                Button { windows.showSettings() } label: { Label("Einstellungen", systemImage: "gearshape") }
                    .help("Einstellungen")
            }
        }
    }

    @ViewBuilder
    private var weekLayout: some View {
        if calendar.hasAccess {
            WeekView()
                .inspector(isPresented: Binding(
                    get: { windows.selection != nil },
                    set: { if !$0 { windows.selection = nil } }
                )) {
                    detail
                        .inspectorColumnWidth(min: 380, ideal: 440, max: 620)
                }
        } else {
            AccessView()
        }
    }

    private var listLayout: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text(L($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                List(selection: $windows.selection) {
                    switch mode {
                    case .upcoming: upcomingList
                    case .notes: notesList
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        } detail: {
            detail
        }
    }

    private func meeting(_ id: String) -> Meeting? {
        calendar.upcoming.first(where: { $0.id == id }) ?? calendar.cachedMeeting(id)
    }

    // MARK: Listen

    private var filteredUpcoming: [Meeting] {
        let now = Date()
        let base = calendar.upcoming.filter { !$0.isAllDay || Calendar.current.isDateInToday($0.start) || $0.start > now }
        guard !query.isEmpty else { return base }
        return base.filter { m in
            m.title.localizedCaseInsensitiveContains(query)
                || (store.note(for: m.id)?.matches(query) ?? false)
        }
    }

    @ViewBuilder
    private var upcomingList: some View {
        if !calendar.hasAccess {
            Text("Kein Kalenderzugriff").foregroundStyle(.secondary)
        } else if filteredUpcoming.isEmpty {
            Text(query.isEmpty ? L("Keine Meetings in den nächsten 3 Wochen") : L("Keine Treffer"))
                .foregroundStyle(.secondary)
        } else {
            let groups = Dictionary(grouping: filteredUpcoming) { Calendar.current.startOfDay(for: $0.start) }
            ForEach(groups.keys.sorted(), id: \.self) { day in
                Section(Fmt.day(day)) {
                    ForEach(groups[day]!) { m in
                        MeetingRow(
                            title: m.title,
                            subtitle: Fmt.range(m),
                            color: m.calendarColor,
                            hasNote: store.hasNote(m.id),
                            isPast: m.end < Date(),
                            dropMeeting: m
                        )
                        .tag(m.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notesList: some View {
        let results = store.search(query)
        if results.isEmpty {
            Text(query.isEmpty ? L("Noch keine Notizen angelegt") : L("Keine Treffer"))
                .foregroundStyle(.secondary)
        } else {
            ForEach(results) { n in
                MeetingRow(
                    title: n.title,
                    subtitle: "\(Fmt.dayShort(n.start)), \(Fmt.time(n.start))",
                    color: .accentColor,
                    hasNote: true,
                    isPast: n.end < Date(),
                    dropMeeting: meeting(n.id) ?? Meeting(note: n)
                )
                .tag(n.id)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if !calendar.hasAccess {
            AccessView()
        } else if let id = windows.selection,
                  let initial = store.note(for: id) ?? meeting(id).map(MeetingNote.init) {
            NoteEditorView(initial: initial, meeting: meeting(id))
            .id(id)
        } else {
            ContentUnavailableView(
                "Kein Meeting ausgewählt",
                systemImage: "calendar",
                description: Text("Wähle links ein Meeting aus, um Infos und Notizen zu hinterlegen.")
            )
        }
    }
}

private struct MeetingRow: View {
    let title: String
    let subtitle: String
    let color: Color
    let hasNote: Bool
    let isPast: Bool
    var dropMeeting: Meeting?
    @EnvironmentObject private var windows: WindowManager

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if hasNote {
                Image(systemName: "note.text").foregroundStyle(Color.accentColor)
                    .help("Notizen vorhanden")
            }
        }
        .opacity(isPast ? 0.55 : 1)
        .padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(-3)
                .opacity(dropMeeting.map { windows.dropTargetID == $0.id } ?? false ? 1 : 0)
        )
        .background { if let dropMeeting { DropFrameReporter(meeting: dropMeeting) } }
    }
}

private struct AccessView: View {
    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Kalenderzugriff benötigt").font(.title2.weight(.semibold))
            Text("note4meet liest deine Termine aus der Kalender-App – auch aus Google-, Exchange- oder iCloud-Konten, die dort eingebunden sind. Die Termine werden nur gelesen, nie verändert.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            if calendar.status == .notDetermined {
                Button("Zugriff erlauben") { Task { await calendar.requestAccess() } }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("Der Zugriff wurde abgelehnt. Erlaube ihn unter Systemeinstellungen → Datenschutz & Sicherheit → Kalender.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                HStack {
                    Button("Systemeinstellungen öffnen") { calendar.openPrivacySettings() }
                        .buttonStyle(.borderedProminent)
                    Button("Erneut prüfen") { calendar.reload() }
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
