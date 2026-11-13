import SwiftUI

/// What changed in each app version. Add an entry with every release (see the release process in CLAUDE.md).
struct ReleaseNote: Identifiable {
    let version: String
    let date: String
    let items: [LocalizedStringKey]

    var id: String { version }

    static let all: [ReleaseNote] = [
        ReleaseNote(version: "0.2.0", date: "November 2026", items: [
            "Alle Einträge in einer Liste: Tanken, Laden, Ausgaben, Kilometerstände und Fahrten, mit Monatssummen, Filtern und Suche",
            "Jeder Eintrag lässt sich öffnen, bearbeiten und löschen; fehlende Kilometerstände trägst du jederzeit nach",
            "Ausgaben erfassen wie Versicherung, Werkstatt oder TÜV, auch mit eigenen Kategorien",
            "Fahrtenbuch mit Zweck, Auswertung je Monat und Export als CSV",
            "Fahrzeuge mit anderen teilen: einladen, Rollen vergeben, Einladungen annehmen",
            "Alle Termine auf einen Blick und Erinnerungen auf dem iPhone, ganz ohne Mitteilungsdienst",
            "Länger angemeldet bleiben: Solange du die App mindestens alle 180 Tage öffnest, musst du dich nicht neu anmelden",
            "Angemeldete Geräte ansehen und einzeln abmelden",
            "Widget „Fahrzeug im Auto“ für CarPlay: Durchschnittsverbrauch auf dem Display des Autos (ab iOS 26)",
            "Hinweis, wenn der Server eine neuere App-Version braucht",
        ]),
        ReleaseNote(version: "0.1.0", date: "November 2026", items: [
            "Erste Version für das iPhone: Start, Einträge, Statistik und Profil",
            "Anmelden und Registrieren, auch mit Zwei-Faktor-Code und eigenem Server",
            "Fahrzeuge anlegen, ändern und löschen, mit Foto aus Kamera oder Mediathek",
            "Tank- und Ladevorgänge erfassen, mit Preisen der Tankstellen in der Nähe",
            "Fällige Termine wie TÜV, Wartung und Versicherung auf einen Blick",
        ]),
    ]
}

/// Profil → Neuigkeiten: the app's own release notes and a link to the server's news page.
struct ReleaseNotesView: View {
    @Environment(AuthSession.self) private var auth
    @State private var webPage: WebPage?

    var body: some View {
        List {
            ForEach(ReleaseNote.all) { note in
                Section {
                    ForEach(note.items.indices, id: \.self) { index in
                        Label {
                            Text(note.items[index])
                        } icon: {
                            Image(systemName: "sparkle")
                                .foregroundStyle(Theme.brand)
                                .accessibilityHidden(true)
                        }
                    }
                } header: {
                    HStack {
                        Text("Version \(note.version)")
                        Spacer()
                        Text(note.date)
                    }
                    .accessibilityElement(children: .combine)
                }
                .listRowBackground(Theme.card)
            }

            Section {
                WebPageRow(page: .news, selection: $webPage)
            } footer: {
                Text("Neue Funktionen der Web-App und des Servers.")
            }
            .listRowBackground(Theme.card)
        }
        .themedBackground()
        .navigationTitle("Neuigkeiten")
        .webPageSheet($webPage, apiBaseURL: auth.api.baseURL)
    }
}

#Preview {
    NavigationStack { ReleaseNotesView() }
        .environment(AuthSession())
}
