import SwiftUI

/// Wochenansicht wie im Kalender: Tage als Spalten, Stunden als Zeilen.
struct WeekView: View {
    static let hideWeekendsKey = "hideWeekends"

    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var windows: WindowManager
    @AppStorage(hideWeekendsKey) private var hideWeekends = false

    @State private var weekStart = WeekView.startOfWeek(Date())
    @State private var meetings: [Meeting] = []

    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Montag
        c.minimumDaysInFirstWeek = 4
        c.locale = Fmt.locale
        return c
    }()

    private let hourHeight: CGFloat = 52
    private let gutter: CGFloat = 52

    static func startOfWeek(_ d: Date) -> Date {
        cal.dateInterval(of: .weekOfYear, for: d)!.start
    }

    private var days: [Date] {
        (0..<(hideWeekends ? 5 : 7)).map { Self.cal.date(byAdding: .day, value: $0, to: weekStart)! }
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()
            dayHeader
            allDayRow
            Divider()
            grid
        }
        .onAppear(perform: reload)
        .onChange(of: weekStart) { reload() }
        .onChange(of: calendar.upcoming) { reload() }
        .onChange(of: calendar.hiddenTitles) { reload() }
        .onAppear(perform: jumpToSelection)
        .onChange(of: windows.selection) { jumpToSelection() }
    }

    /// Liegt das ausgewählte Meeting in einer anderen Woche, dorthin springen.
    private func jumpToSelection() {
        guard let id = windows.selection, let m = calendar.cachedMeeting(id) else { return }
        let target = Self.startOfWeek(m.start)
        if target != weekStart { weekStart = target }
    }

    private func reload() {
        let end = Self.cal.date(byAdding: .day, value: 7, to: weekStart)!
        meetings = calendar.meetings(from: weekStart, to: end)
    }

    // MARK: Kopfzeilen

    private var navigationBar: some View {
        HStack(spacing: 10) {
            Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
                .help("Vorherige Woche")
            Button("Heute") { weekStart = Self.startOfWeek(Date()) }
            Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                .help("Nächste Woche")
            Text(title).font(.title3.weight(.semibold)).padding(.leading, 6)
            Spacer()
            Toggle("Sa & So ausblenden", isOn: $hideWeekends)
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var title: String {
        let last = days.last!
        let week = Self.cal.component(.weekOfYear, from: weekStart)
        let from = weekStart.formatted(Date.FormatStyle().day().month(.abbreviated).locale(Fmt.locale))
        let to = last.formatted(Date.FormatStyle().day().month(.abbreviated).year().locale(Fmt.locale))
        return L("KW %d · %@ – %@", week, from, to)
    }

    private func shiftWeek(_ n: Int) {
        weekStart = Self.cal.date(byAdding: .weekOfYear, value: n, to: weekStart)!
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(days, id: \.self) { day in
                let isToday = Self.cal.isDateInToday(day)
                VStack(spacing: 2) {
                    Text(day.formatted(Date.FormatStyle().weekday(.abbreviated).locale(Fmt.locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(day.formatted(Date.FormatStyle().day().locale(Fmt.locale)))
                        .font(.title3.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.white : Color.primary)
                        .frame(minWidth: 30, minHeight: 30)
                        .background(Circle().fill(isToday ? Color.red : .clear))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var allDayRow: some View {
        let allDay = meetings.filter(\.isAllDay)
        if !allDay.isEmpty {
            HStack(alignment: .top, spacing: 0) {
                Text("ganzt.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: gutter, alignment: .trailing)
                    .padding(.trailing, 6)
                ForEach(days, id: \.self) { day in
                    let dayEnd = Self.cal.date(byAdding: .day, value: 1, to: day)!
                    VStack(spacing: 2) {
                        ForEach(allDay.filter { $0.start < dayEnd && $0.end > day }) { m in
                            Text(m.title)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 4).fill(m.calendarColor.opacity(0.25)))
                                .onTapGesture { windows.selection = m.id }
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
        }
    }

    // MARK: Zeitraster

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                GeometryReader { geo in
                    let colWidth = (geo.size.width - gutter) / CGFloat(days.count)
                    ZStack(alignment: .topLeading) {
                        hourLines(width: geo.size.width)
                        ForEach(Array(days.enumerated()), id: \.element) { index, day in
                            dayColumn(day)
                                .frame(width: colWidth, height: hourHeight * 24)
                                .offset(x: gutter + CGFloat(index) * colWidth)
                        }
                    }
                }
                .frame(height: hourHeight * 24)
                .overlay(alignment: .topLeading) {
                    // Unsichtbare Anker zum Scrollen auf eine Uhrzeit
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { h in
                            Color.clear.frame(height: hourHeight).id(h)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear { proxy.scrollTo(7, anchor: .top) }
        }
    }

    private func hourLines(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                HStack(alignment: .top, spacing: 0) {
                    Text(h == 0 ? "" : String(format: "%02d:00", h))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: gutter - 8, alignment: .trailing)
                        .offset(y: -7)
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 8)
                }
                .frame(width: width, height: hourHeight)
            }
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let dayEnd = Self.cal.date(byAdding: .day, value: 1, to: day)!
        let items = Self.layout(meetings.filter { !$0.isAllDay && $0.start < dayEnd && $0.end > day })
        let isToday = Self.cal.isDateInToday(day)

        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(isToday ? Color.accentColor.opacity(0.04) : .clear)
                Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)

                ForEach(items, id: \.meeting.id) { item in
                    let start = max(item.meeting.start, day)
                    let end = min(item.meeting.end, dayEnd)
                    let y = CGFloat(start.timeIntervalSince(day) / 3600) * hourHeight
                    let h = max(CGFloat(end.timeIntervalSince(start) / 3600) * hourHeight, 20)
                    let w = (geo.size.width - 6) / CGFloat(item.columns)
                    EventBlock(
                        meeting: item.meeting,
                        hasNote: store.hasNote(item.meeting.id),
                        isSelected: windows.selection == item.meeting.id,
                        compact: h < 40
                    )
                    .frame(width: max(w - 2, 10), height: h - 2)
                    .offset(x: 3 + CGFloat(item.column) * w, y: y + 1)
                    .onTapGesture { windows.selection = item.meeting.id }
                }

                if isToday {
                    TimelineView(.periodic(from: .now, by: 60)) { ctx in
                        let y = CGFloat(ctx.date.timeIntervalSince(day) / 3600) * hourHeight
                        HStack(spacing: 0) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Rectangle().fill(Color.red).frame(height: 1.5)
                        }
                        .offset(x: -4, y: y - 4)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }

    /// Verteilt sich überschneidende Termine nebeneinander.
    static func layout(_ events: [Meeting]) -> [(meeting: Meeting, column: Int, columns: Int)] {
        var result: [(meeting: Meeting, column: Int, columns: Int)] = []
        var cluster: [(Meeting, Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            for (m, c) in cluster { result.append((m, c, columnEnds.count)) }
            cluster = []
            columnEnds = []
        }

        for m in events.sorted(by: { ($0.start, $1.end) < ($1.start, $0.end) }) {
            if m.start >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= m.start }) {
                columnEnds[free] = m.end
                cluster.append((m, free))
            } else {
                columnEnds.append(m.end)
                cluster.append((m, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, m.end)
        }
        flush()
        return result
    }
}

private struct EventBlock: View {
    let meeting: Meeting
    let hasNote: Bool
    let isSelected: Bool
    let compact: Bool
    @EnvironmentObject private var windows: WindowManager
    @State private var hover = false

    var body: some View {
        let color = meeting.calendarColor
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: 3) {
                    Text(meeting.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(compact ? 1 : 3)
                    Spacer(minLength: 0)
                    if hasNote {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if !compact {
                    Text(Fmt.range(meeting))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(isSelected ? 0.45 : (hover ? 0.32 : 0.22)))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isSelected ? color : .clear, lineWidth: 1.5)
        )
        .opacity(meeting.end < Date() ? 0.6 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(windows.dropTargetID == meeting.id ? 1 : 0)
        )
        .background(DropFrameReporter(meeting: meeting))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .help(Text(verbatim: "\(meeting.title)\n\(Fmt.range(meeting))" + (hasNote ? "\n" + L("Notizen vorhanden") : "")))
    }
}
