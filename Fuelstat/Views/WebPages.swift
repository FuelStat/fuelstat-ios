import FuelstatCore
import SafariServices
import SwiftUI

/// Pages of the web app the app links to. They come from the server the user signs in to, so a self-hosted
/// installation shows its own imprint and privacy policy.
enum WebPage: String, Identifiable {
    case imprint = "pages/impressum.php"
    case privacy = "pages/datenschutz.php"
    case terms = "pages/nutzungsbedingungen.php"
    case news = "pages/neuigkeiten.php"
    case export = "pages/export.php"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .imprint: "Impressum"
        case .privacy: "Datenschutzerklärung"
        case .terms: "Nutzungsbedingungen"
        case .news: "Neuigkeiten des Servers"
        case .export: "Daten exportieren"
        }
    }

    var systemImage: String {
        switch self {
        case .imprint: "building.columns"
        case .privacy: "hand.raised"
        case .terms: "doc.text"
        case .news: "newspaper"
        case .export: "square.and.arrow.down"
        }
    }

    func url(on apiBaseURL: URL) -> URL? {
        ServerAddress.webPageURL(rawValue, apiBaseURL: apiBaseURL)
    }
}

/// A web page in an in-app Safari view (Reader, sharing and "Open in Safari" included).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Theme.brand)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension View {
    /// Shows the chosen web page of the current server in a Safari sheet.
    func webPageSheet(_ page: Binding<WebPage?>, apiBaseURL: URL) -> some View {
        sheet(item: page) { page in
            if let url = page.url(on: apiBaseURL) {
                SafariView(url: url).ignoresSafeArea()
            }
        }
    }
}

/// A list row that opens a web page of the server.
struct WebPageRow: View {
    let page: WebPage
    var detail: String?
    @Binding var selection: WebPage?

    var body: some View {
        Button {
            selection = page
        } label: {
            LabeledContent {
                if let detail { Text(detail) }
            } label: {
                Label(page.title, systemImage: page.systemImage)
            }
        }
        .accessibilityHint(Text("Öffnet die Webseite des Servers"))
    }
}
