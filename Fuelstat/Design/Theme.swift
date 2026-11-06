import SwiftUI
import UIKit

/// Colour, spacing and shape tokens from `docs/design.md`.
///
/// Colours live in the asset catalog with light and dark variants; views use these names, never hex values.
enum Theme {
    // MARK: Colour

    /// Petrol (light) / teal (dark): primary buttons, the "+", selected chips, links.
    static let brand = Color("Brand")
    /// Text and icons on `brand` fills.
    static let onBrand = Color("OnBrand")
    /// Navy anchor: hero headers, welcome screen, headings on tinted areas.
    static let brandDeep = Color("BrandDeep")
    /// Screen background.
    static let background = Color("Background")
    /// Cards and sheets.
    static let card = Color("Card")
    /// Stat tiles, icon circles, unselected chips.
    static let cardTint = Color("CardTint")

    /// The welcome screen is navy in both modes, like the app icon.
    static let welcomeNavy = Color(red: 10 / 255, green: 28 / 255, blue: 51 / 255)
    /// Teal accent on the navy welcome screen.
    static let welcomeTeal = Color(red: 94 / 255, green: 211 / 255, blue: 207 / 255)
    /// Gauge scale of the icon (green → yellow → orange) for the welcome illustration on navy.
    static let welcomeGauge = [
        Color(red: 61 / 255, green: 209 / 255, blue: 122 / 255),
        Color(red: 245 / 255, green: 197 / 255, blue: 66 / 255),
        Color(red: 255 / 255, green: 138 / 255, blue: 91 / 255),
    ]

    enum Status {
        static let ok = Color("StatusOK")
        static let soon = Color("StatusSoon")
        static let overdue = Color("StatusOverdue")
    }

    enum Energy {
        static let electricity = Color("EnergyElectric")
        static let petrol = Color("EnergyPetrol")
        static let diesel = Color("EnergyDiesel")
        static let gas = Color("EnergyGas")
        static let hydrogen = Color("EnergyHydrogen")
    }

    // MARK: Spacing (4, 8, 12, 16, 24, 32)

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32

        /// Screen margin, gap between cards and padding inside cards.
        static let screen: CGFloat = m
        static let cardGap: CGFloat = m
        static let cardPadding: CGFloat = m
    }

    // MARK: Shape

    enum Radius {
        /// Cards and sheets.
        static let card: CGFloat = 20
        /// Tiles, fields and buttons.
        static let tile: CGFloat = 14
    }

    /// Size of the tinted circle behind entry icons.
    static let iconCircle: CGFloat = 36
}

extension RemoteFuelType {
    /// Fixed energy colour for icons and chart series.
    var energyColor: Color {
        switch self {
        case .electric: Theme.Energy.electricity
        case .e5, .e10, .hybrid, .phev, .other: Theme.Energy.petrol
        case .diesel: Theme.Energy.diesel
        case .lpg, .cng: Theme.Energy.gas
        case .hydrogen: Theme.Energy.hydrogen
        }
    }
}

extension Shape where Self == RoundedRectangle {
    static var card: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous) }
    static var tile: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous) }
}

extension InsettableShape where Self == RoundedRectangle {
    static var card: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous) }
    static var tile: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous) }
}

/// Haptic feedback as described in the design: success after saving, warning for plausibility hints.
@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

extension View {
    /// Screen background token behind lists, forms and scroll views.
    func themedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}
