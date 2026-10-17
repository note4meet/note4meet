import AppKit
import EventKit
import SwiftUI

/// Liest Termine aus dem macOS-Kalender. Die Google-Konten sind dort über
/// Systemeinstellungen → Internetaccounts eingebunden; macOS hält sie synchron.
@MainActor
final class CalendarService: ObservableObject {
    private static let selectionKey = "selectedCalendarIDs"
    private static let knownKey = "knownCalendarIDs"

    let store = EKEventStore()

    @Published private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var upcoming: [Meeting] = []
    @Published var selectedIDs: Set<String> = [] {
        didSet {
            guard !isLoadingSelection else { return }
            UserDefaults.standard.set(Array(selectedIDs), forKey: Self.selectionKey)
            reloadUpcoming()
        }
    }
    private var isLoadingSelection = false

    static let defaultHiddenTitles: [String] = []
    private static let hiddenKey = "hiddenTitles"

    /// Termine, deren Titel einen dieser Begriffe enthält, werden überall ausgeblendet.
    @Published var hiddenTitles: [String] =
        UserDefaults.standard.stringArray(forKey: hiddenKey) ?? defaultHiddenTitles {
        didSet {
            UserDefaults.standard.set(hiddenTitles, forKey: Self.hiddenKey)
            reloadUpcoming()
        }
    }

    /// Zuletzt geladene Termine nach Schlüssel, damit die Wochenansicht auch
    /// Meetings außerhalb der Übersicht öffnen kann.
    private var cache: [String: Meeting] = [:]

    func cachedMeeting(_ id: String) -> Meeting? { cache[id] }

    func isHidden(_ title: String?) -> Bool {
        let t = Self.normalize(title ?? "")
        return hiddenTitles.contains { term in
            let n = Self.normalize(term)
            return !n.isEmpty && t.localizedCaseInsensitiveContains(n)
        }
    }

    /// Emoji-Varianten (U+FE0F) und Leerraum ignorieren, damit „🍽️“ und „🍽“ gleich behandelt werden.
    private static func normalize(_ s: String) -> String {
        String(s.unicodeScalars.filter { $0 != "\u{FE0F}" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAccess: Bool { status == .fullAccess }

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        if hasAccess { reload() }
    }

    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            NSLog("Kalenderzugriff fehlgeschlagen: \(error)")
        }
        status = EKEventStore.authorizationStatus(for: .event)
        reload()
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func reload() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else {
            calendars = []
            upcoming = []
            return
        }
        calendars = store.calendars(for: .event).sorted {
            ($0.source.title, $0.title) < ($1.source.title, $1.title)
        }
        isLoadingSelection = true
        let d = UserDefaults.standard
        let allIDs = Set(calendars.map(\.calendarIdentifier))
        if let saved = d.array(forKey: Self.selectionKey) as? [String] {
            var selection = Set(saved)
            // Seit dem letzten Start neu hinzugekommene Kalender automatisch anzeigen
            if let known = d.array(forKey: Self.knownKey) as? [String] {
                let added = calendars.filter { !known.contains($0.calendarIdentifier) && Self.isDefaultVisible($0) }
                selection.formUnion(added.map(\.calendarIdentifier))
                if !added.isEmpty { d.set(Array(selection), forKey: Self.selectionKey) }
            }
            selectedIDs = selection
        } else {
            selectedIDs = Set(calendars.filter(Self.isDefaultVisible).map(\.calendarIdentifier))
        }
        d.set(Array(allIDs), forKey: Self.knownKey)
        isLoadingSelection = false
        reloadUpcoming()
    }

    /// Standard: alle Kalender der beiden Google-Konten. Falls keiner passt, alle Kalender.
    /// Standardmäßig sichtbar: alle Kalender außer Geburtstagen.
    private static func isDefaultVisible(_ cal: EKCalendar) -> Bool {
        cal.type != .birthday
    }

    func reloadUpcoming() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 21, to: startOfToday)!
        upcoming = meetings(from: startOfToday, to: end)
    }

    func meetings(from start: Date, to end: Date) -> [Meeting] {
        guard hasAccess else { return [] }
        let cals = calendars.filter { selectedIDs.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        let result = store.events(matching: predicate)
            .filter { $0.status != .canceled && !isDeclined($0) && !isHidden($0.title) }
            .sorted { $0.startDate < $1.startDate }
            .map(Self.meeting(from:))
        for m in result { cache[m.id] = m }
        return result
    }

    private func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    /// Schlüssel für die Notiz: Einzeltermine behalten ihn auch beim Verschieben,
    /// Serientermine bekommen pro Vorkommen einen eigenen Schlüssel.
    static func key(for event: EKEvent) -> String {
        let base = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString
        if event.hasRecurrenceRules || event.isDetached {
            let occ = event.occurrenceDate ?? event.startDate!
            return "\(base)@\(Int(occ.timeIntervalSince1970))"
        }
        return base
    }

    private static func meeting(from e: EKEvent) -> Meeting {
        Meeting(
            id: key(for: e),
            title: (e.title?.isEmpty == false ? e.title! : L("Ohne Titel")),
            start: e.startDate,
            end: e.endDate,
            isAllDay: e.isAllDay,
            calendarTitle: e.calendar.title,
            accountTitle: e.calendar.source.title,
            calendarColor: Color(nsColor: e.calendar.color ?? .systemBlue),
            location: e.location,
            eventNotes: e.notes,
            eventURL: e.url
        )
    }
}
