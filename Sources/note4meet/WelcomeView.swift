import SwiftUI

/// Erster Start: erklärt kurz die App und fragt erst auf Knopfdruck nach dem Kalenderzugriff.
struct WelcomeView: View {
    let onFinish: () -> Void
    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Willkommen bei note4meet").font(.title.weight(.semibold))
                    Text("Notizen zu deinen Meetings – serviert, wenn es losgeht.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                point("calendar", L("Deine Termine"),
                      L("note4meet liest die Termine aus der Kalender-App, auch aus Google- oder Exchange-Konten. Es wird nichts verändert."))
                point("note.text", L("Notizen & Briefing"),
                      L("Hinterlege Ziel, Agenda und Unterlagen. Zum Meetingbeginn öffnet sich ein Briefing – aber nur, wenn es Notizen gibt."))
                point("icloud", L("Auf all deinen Macs"),
                      L("Notizen liegen in deinem iCloud Drive. Es gibt keinen Server und kein Konto – deine Daten bleiben bei dir."))
                point("menubar.rectangle", L("Immer in der Menüleiste"),
                      L("Das Symbol oben rechts zeigt die nächsten Meetings und öffnet alles Weitere."))
            }

            HStack {
                Spacer()
                if calendar.hasAccess {
                    Button("Los geht’s") { onFinish() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Später") { onFinish() }
                    Button("Kalenderzugriff erlauben") {
                        Task {
                            await calendar.requestAccess()
                            onFinish()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(28)
        .frame(width: 520)
    }

    private func point(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
