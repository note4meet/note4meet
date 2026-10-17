import AppKit
import Foundation

/// Prüft regelmäßig, ob ein Meeting mit hinterlegten Notizen beginnt, und öffnet
/// dann das Briefing-Fenster. Meetings ohne Notizen lösen keine Meldung aus.
@MainActor
final class AlertScheduler {
    static let leadMinutesKey = "leadMinutes"
    private static let shownKey = "shownAlerts"
    /// Wird die App erst nach Meetingbeginn gestartet, kommt die Meldung noch bis zu so viele Minuten danach.
    private static let graceMinutes = 10.0

    private let calendar: CalendarService
    private let store: NotesStore
    private let windows: WindowManager
    private var timer: Timer?
    private var shown: [String: Date]

    init(calendar: CalendarService, store: NotesStore, windows: WindowManager) {
        self.calendar = calendar
        self.store = store
        self.windows = windows
        let raw = UserDefaults.standard.dictionary(forKey: Self.shownKey) as? [String: Date] ?? [:]
        shown = raw.filter { $0.value > Date().addingTimeInterval(-7 * 86400) }
    }

    var leadMinutes: Int {
        UserDefaults.standard.object(forKey: Self.leadMinutesKey) as? Int ?? 2
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 3
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.calendar.reload()
                self?.tick()
            }
        }
        tick()
    }

    func tick() {
        guard calendar.hasAccess else { return }
        let now = Date()
        let lead = TimeInterval(leadMinutes * 60)
        let meetings = calendar.meetings(
            from: now.addingTimeInterval(-Self.graceMinutes * 60),
            to: now.addingTimeInterval(lead + 60)
        )
        store.refreshSnapshots(from: meetings)

        for m in meetings where !m.isAllDay {
            guard let note = store.note(for: m.id), !note.isEmpty else { continue }
            let alertID = "\(m.id)|\(Int(m.start.timeIntervalSince1970))"
            guard shown[alertID] == nil else { continue }

            let trigger = m.start.addingTimeInterval(-lead)
            let latest = min(m.end, m.start.addingTimeInterval(Self.graceMinutes * 60))
            if now >= trigger && now < latest {
                shown[alertID] = now
                UserDefaults.standard.set(shown, forKey: Self.shownKey)
                windows.showBriefing(meeting: m)
            }
        }
    }
}
