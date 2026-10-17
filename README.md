# note4meet

**Notes for your meetings – served when they start.**

note4meet is a small, free macOS menu bar app. Add a goal, an agenda, files and notes to an upcoming meeting – and when the meeting starts, a briefing window pops up with everything you prepared. No notes, no popup.

*[Deutsch weiter unten](#deutsch)*

## Features

- **Week view and list** of your meetings from the macOS Calendar app – including Google, Exchange and iCloud accounts added there. Events are only read, never changed.
- **Briefing at meeting start** (or 1–15 minutes before), with a *Join* button for Zoom, Google Meet, Teams and Webex links.
- **Per-meeting notes:** goal, agenda checklist, attendees & context, links, free notes – with bullet lists, next steps and projects.
- **Drag & drop** files from Finder, emails from Apple Mail and web links onto a meeting. A click opens them again.
- **Send to Things:** next steps become to-dos for *Today*, projects become Things projects.
- **Sync between your Macs** via your own iCloud Drive. No server, no account.
- **Search** across all notes, **export** as Markdown, text or JSON.
- **Hide events** by title (e.g. “Focus time”) and hide weekends.
- English and German.

## Privacy

note4meet has no server, no analytics and no account. Your notes are plain JSON files in `iCloud Drive/note4meet` (or `~/Library/Application Support/note4meet` without iCloud Drive). Calendar data never leaves your Mac – the app only reads it locally.

## Install

note4meet is free and not notarized by Apple (notarization requires a paid developer account). macOS therefore asks you to confirm the first launch.

**Option 1 – Download**

1. Download `note4meet.zip` from the [latest release](https://github.com/note4meet/note4meet/releases/latest) and unzip it.
2. Move `note4meet.app` to your *Applications* folder and double-click it.
3. macOS says it can’t verify the app. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to note4meet. Confirm with your password or Touch ID.

You need to do this once per version.

**Option 2 – Terminal (no warning)**

```bash
curl -fsSL https://raw.githubusercontent.com/note4meet/note4meet/main/install.sh | bash
```

Files downloaded with `curl` aren’t flagged as coming from the internet, so the app opens right away. [Read the script](install.sh) first – it only downloads the release ZIP and copies the app.

**Option 3 – Build it yourself**

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`); the full Xcode app is not needed.

```bash
git clone https://github.com/note4meet/note4meet.git
cd note4meet
./build.sh --install
```

This builds a universal app (Intel + Apple silicon) and installs it to `~/Applications`.

## Requirements

- macOS 14 Sonoma or later
- Your calendars added to the Calendar app
- Optional: iCloud Drive (sync), Things 3 (task export), Apple Mail (email links)

## Development

- Swift / SwiftUI, built with Swift Package Manager – see `build.sh`.
- `./build.sh --release` creates `dist/note4meet.zip` for a GitHub release.
- UI texts are written in German in the code; English translations live in `Support/en.lproj/Localizable.strings`. `python3 Support/tools/check_strings.py` lists any text that is missing a translation.
- Code comments are in German.
- Diagnostics for drag & drop: `defaults write io.github.note4meet debugLog -bool true` writes to `~/Library/Logs/note4meet.log`.

## License

[MIT](LICENSE) © 2026 Dennis Wittrock

---

## Deutsch

**Notizen zu deinen Meetings – serviert, wenn es losgeht.**

note4meet ist eine kleine, kostenlose Mac-App für die Menüleiste. Du hinterlegst zu einem anstehenden Meeting Ziel, Agenda, Unterlagen und Notizen – und zum Meetingbeginn öffnet sich ein Briefing mit allem, was du vorbereitet hast. Ohne Notizen keine Meldung.

**Funktionen:** Wochenansicht und Liste deiner Termine aus der Kalender-App (auch Google, Exchange, iCloud) · Briefing zum Start mit „Beitreten“-Knopf · Agenda als Checkliste, Aufzählungen, nächste Schritte und Projekte · Dateien, Mails aus Apple Mail und Links per Drag & Drop · Übergabe an Things · Sync über dein eigenes iCloud Drive · Suche und Export · Termine nach Titel und Wochenenden ausblenden.

**Datenschutz:** Kein Server, keine Analyse, kein Konto. Notizen liegen als JSON-Dateien in deinem iCloud Drive, Kalenderdaten verlassen deinen Mac nicht.

**Installation:** `note4meet.zip` aus dem [neuesten Release](https://github.com/note4meet/note4meet/releases/latest) laden, entpacken, nach *Programme* ziehen und öffnen. Weil die App nicht von Apple notarisiert ist, einmalig unter **Systemeinstellungen → Datenschutz & Sicherheit → Trotzdem öffnen** freigeben. Alternativ ohne Warnung im Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/note4meet/note4meet/main/install.sh | bash
```

Selbst bauen: siehe *Option 3* oben.
