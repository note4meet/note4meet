import EventKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var store: NotesStore
    @AppStorage(AlertScheduler.leadMinutesKey) private var leadMinutes = 2
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage(WeekView.hideWeekendsKey) private var hideWeekends = false
    @State private var newHidden = ""

    var body: some View {
        Form {
            Section("Meldung") {
                Picker("Briefing anzeigen", selection: $leadMinutes) {
                    Text("Zum Meetingbeginn").tag(0)
                    ForEach([1, 2, 3, 5, 10, 15], id: \.self) { Text(L("%d Min. vorher", $0)).tag($0) }
                }
                Text("Die Meldung kommt nur für Meetings, zu denen du Infos hinterlegt hast.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Ausblenden") {
                Toggle("Samstag und Sonntag in der Wochenansicht ausblenden", isOn: $hideWeekends)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Termine ausblenden, deren Titel Folgendes enthält:")
                    HStack {
                        TextField("z. B. Blocker", text: $newHidden)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addHidden)
                        Button("Hinzufügen", action: addHidden)
                            .disabled(newHidden.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if calendar.hiddenTitles.isEmpty {
                        Text("Keine Begriffe – alle Termine werden angezeigt.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(calendar.hiddenTitles, id: \.self) { term in
                            HStack {
                                Image(systemName: "eye.slash").foregroundStyle(.secondary)
                                Text(term)
                                Spacer()
                                Button {
                                    calendar.hiddenTitles.removeAll { $0 == term }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Wieder anzeigen")
                            }
                        }
                    }
                    Text("Groß-/Kleinschreibung egal. Gilt für Wochenansicht, Liste, Menüleiste und Meldungen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Kalender") {
                if calendar.hasAccess {
                    let bySource = Dictionary(grouping: calendar.calendars) { $0.source.title }
                    ForEach(bySource.keys.sorted(), id: \.self) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(bySource[source]!, id: \.calendarIdentifier) { cal in
                                Toggle(isOn: binding(for: cal)) {
                                    HStack(spacing: 6) {
                                        Circle().fill(Color(nsColor: cal.color ?? .systemBlue)).frame(width: 9, height: 9)
                                        Text(cal.title)
                                    }
                                }
                            }
                        }
                    }
                    Text("Weitere Kalenderkonten (z. B. Google oder Exchange) fügst du unter Systemeinstellungen → Internetaccounts hinzu. Sie erscheinen dann hier.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Kalenderzugriff erlauben …") { calendar.openPrivacySettings() }
                }
            }

            Section("Allgemein") {
                Toggle("Beim Anmelden automatisch starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Sync zwischen Macs") {
                if store.isICloud {
                    Label("Aktiv über iCloud Drive", systemImage: "icloud")
                        .foregroundStyle(.green)
                    Text("Notizen und Einstellungen liegen in iCloud Drive → note4meet. Auf jedem Mac mit derselben Apple-ID und dieser App erscheinen sie automatisch. Die Kalenderauswahl bleibt pro Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("iCloud Drive nicht verfügbar – Notizen nur auf diesem Mac", systemImage: "icloud.slash")
                        .foregroundStyle(.orange)
                    Text("Aktiviere iCloud Drive unter Systemeinstellungen → Apple-ID → iCloud und starte die App neu.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let last = store.lastSync {
                    LabeledContent("Zuletzt abgeglichen", value: Fmt.time(last))
                }
            }

            Section("Daten") {
                LabeledContent("Notizen gespeichert", value: "\(store.notes.count)")
                HStack {
                    Button("Als Markdown exportieren …") { store.export(asJSON: false) }
                    Button("Als JSON exportieren …") { store.export(asJSON: true) }
                }
                Button("Speicherort im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.notesDir])
                }
                .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 680)
    }

    private func addHidden() {
        let term = newHidden.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        if !calendar.hiddenTitles.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) {
            calendar.hiddenTitles.append(term)
        }
        newHidden = ""
    }

    private func binding(for cal: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { calendar.selectedIDs.contains(cal.calendarIdentifier) },
            set: { on in
                if on { calendar.selectedIDs.insert(cal.calendarIdentifier) }
                else { calendar.selectedIDs.remove(cal.calendarIdentifier) }
            }
        )
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
            if SMAppService.mainApp.status == .requiresApproval {
                loginError = L("Bitte in Systemeinstellungen → Allgemein → Anmeldeobjekte bestätigen.")
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            loginError = L("Autostart konnte nicht geändert werden: %@", error.localizedDescription)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
