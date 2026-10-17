import SwiftUI

/// Das Fenster, das sich beim Klick auf das Menüleisten-Symbol öffnet.
struct MenuBarView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var windows: WindowManager

    private var nextMeetings: [Meeting] {
        let now = Date()
        let cal = Calendar.current
        let endOfTomorrow = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
        return calendar.upcoming.filter { $0.end > now && $0.start < endOfTomorrow && !$0.isAllDay }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("note4meet")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if !calendar.hasAccess {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kein Zugriff auf den Kalender.")
                        .foregroundStyle(.secondary)
                    Button("Zugriff erlauben …") { windows.showMain() }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            } else if nextMeetings.isEmpty {
                Text("Heute und morgen keine Meetings.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        let groups = Dictionary(grouping: nextMeetings) { Calendar.current.startOfDay(for: $0.start) }
                        ForEach(groups.keys.sorted(), id: \.self) { day in
                            Text(Fmt.day(day))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.top, 6)
                            ForEach(groups[day]!) { m in
                                MenuRow(meeting: m, hasNote: store.hasNote(m.id)) {
                                    windows.showMain(select: m.id)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 380)
            }

            Divider()

            VStack(spacing: 0) {
                MenuButton(title: "Alle Meetings & Notizen …", icon: "rectangle.stack") { windows.showMain() }
                MenuButton(title: "Einstellungen …", icon: "gearshape") { windows.showSettings() }
                MenuButton(title: "Beenden", icon: "power") { NSApp.terminate(nil) }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 330)
    }
}

private struct MenuRow: View {
    let meeting: Meeting
    let hasNote: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(meeting.calendarColor)
                    .frame(width: 4, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(meeting.title).lineLimit(1)
                    Text(Fmt.range(meeting) + (meeting.isNow ? " · " + L("läuft") : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: hasNote ? "note.text" : "plus.circle")
                    .foregroundStyle(hasNote ? Color.accentColor : Color.secondary.opacity(hover ? 1 : 0.4))
                    .help(hasNote ? L("Notizen vorhanden") : L("Notizen hinzufügen"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hover = $0 }
    }
}

private struct MenuButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label(L(title), systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hover = $0 }
    }
}
