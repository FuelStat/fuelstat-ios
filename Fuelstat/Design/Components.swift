import SwiftUI

// MARK: - CardContainer

/// Card surface: `Card` background, 20 pt continuous corners, 16 pt padding.
struct CardContainer<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .card)
    }
}

// MARK: - StatTile

/// Key figure: big rounded value, small unit, short label, optional trend arrow.
struct StatTile: View {
    enum Trend {
        case better, worse
    }

    let label: LocalizedStringKey
    let value: String?
    var unit: String?
    var trend: Trend?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                Text(value ?? "–")
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(Theme.brandDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let trend {
                    Image(systemName: trend == .better ? "arrow.down.right" : "arrow.up.right")
                        .font(.caption.bold())
                        .foregroundStyle(trend == .better ? Theme.Status.ok : Theme.Status.overdue)
                }
            }
            if let unit {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: Theme.Spacing.xxs)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardTint, in: .tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let value else { return String(localized: "keine Angabe") }
        var text = [value, unit].compactMap { $0 }.joined(separator: " ")
        switch trend {
        case .better: text += ", " + String(localized: "weniger als zuvor")
        case .worse: text += ", " + String(localized: "mehr als zuvor")
        case nil: break
        }
        return text
    }
}

/// Row of stat tiles; switches to a column at accessibility text sizes.
struct StatTileRow<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.xs) { content }
        } else {
            // Same height for all tiles, set by the tallest one.
            HStack(alignment: .top, spacing: Theme.Spacing.xs) { content }
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - SectionHeader

/// Section title with an optional "Alle anzeigen" action.
struct SectionHeader: View {
    let title: LocalizedStringKey
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.brandDeep)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button("Alle anzeigen", action: action)
                    .font(.subheadline)
                    .foregroundStyle(Theme.brand)
            }
        }
    }
}

// MARK: - Chips

/// Capsule chip; selected chips are filled with the brand colour.
struct FilterChip: View {
    let title: Text
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    init(title: LocalizedStringKey, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    /// For user content such as station names, which must not be looked up as localization keys.
    init(verbatim title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                if let systemImage { Image(systemName: systemImage) }
                title
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(minHeight: 36)
            .foregroundStyle(isSelected ? Theme.onBrand : Theme.brandDeep)
            .background(isSelected ? Theme.brand : Theme.cardTint, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Single choice from a set of chips, scrolling horizontally when it does not fit.
struct ChipGroup<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: LocalizedStringKey
        var systemImage: String?
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    FilterChip(title: option.title, systemImage: option.systemImage,
                               isSelected: option.value == selection) {
                        selection = option.value
                    }
                }
            }
        }
        .scrollClipDisabled()
    }
}

// MARK: - StatusBadge

/// Due-date status, always with icon and text, never colour alone.
struct StatusBadge: View {
    enum Status {
        case ok, soon, overdue, unknown

        var title: LocalizedStringKey {
            switch self {
            case .ok: "OK"
            case .soon: "Bald fällig"
            case .overdue: "Überfällig"
            case .unknown: "Unbekannt"
            }
        }

        var symbol: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .soon: "clock.badge.exclamationmark.fill"
            case .overdue: "exclamationmark.triangle.fill"
            case .unknown: "questionmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .ok: Theme.Status.ok
            case .soon: Theme.Status.soon
            case .overdue: Theme.Status.overdue
            case .unknown: .secondary
            }
        }
    }

    let status: Status

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
            Text(status.title)
                .foregroundStyle(.primary)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(status.color.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - EntryRow

/// List row for an entry: icon in a tinted circle, title, subtitle, amount on the right.
struct EntryRow: View {
    let systemImage: String
    var tint: Color = Theme.brand
    let title: String
    let subtitle: String
    let amount: String?
    var detail: String?
    var badge: LocalizedStringKey?

    @ScaledMetric(relativeTo: .body) private var circle = Theme.iconCircle

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: circle, height: circle)
                .background(Theme.cardTint, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(subtitle)
                    if let badge {
                        Text(badge)
                            .padding(.horizontal, 6)
                            .background(Theme.cardTint, in: .capsule)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            VStack(alignment: .trailing, spacing: 2) {
                if let amount {
                    Text(amount)
                        .font(.body.weight(.semibold))
                }
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - PrimaryButton

/// Full-width brand button with a loading state.
struct PrimaryButtonStyle: ButtonStyle {
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label.opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView().tint(Theme.onBrand)
            }
        }
        .font(.headline)
        .foregroundStyle(Theme.onBrand)
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.horizontal, Theme.Spacing.m)
        .background(Theme.brand, in: .tile)
        .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
        .contentShape(.tile)
    }
}

struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle(isLoading: isLoading))
        .disabled(isLoading)
        .accessibilityValue(isLoading ? Text("Wird ausgeführt") : Text(""))
    }
}

/// Secondary action next to a primary button: tinted fill, brand text.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.brandDeep)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Theme.Spacing.m)
            .background(Theme.cardTint, in: .tile)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.tile)
    }
}

// MARK: - Previews

/// Shows a component in light and dark mode and at a large Dynamic Type size.
struct PreviewVariants<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                variant(.light, .large)
                variant(.dark, .large)
                variant(.light, .accessibility3)
            }
        }
    }

    private func variant(_ scheme: ColorScheme, _ size: DynamicTypeSize) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) { content }
            .padding(Theme.Spacing.screen)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .environment(\.colorScheme, scheme)
            .dynamicTypeSize(size)
    }
}

#Preview("Card and tiles") {
    PreviewVariants {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(title: "Kennzahlen") {}
                StatTileRow {
                    StatTile(label: "Ø Verbrauch", value: "6,4", unit: "L/100 km", trend: .better)
                    StatTile(label: "Ø Preis", value: "1,749", unit: "€/L")
                    StatTile(label: "Kilometerstand", value: "68.831", unit: "km")
                }
            }
        }
    }
}

#Preview("Chips and badges") {
    @Previewable @State var selection = 0
    PreviewVariants {
        ChipGroup(options: [
            .init(value: 0, title: "Alle"),
            .init(value: 1, title: "Tanken", systemImage: "fuelpump.fill"),
            .init(value: 2, title: "Laden", systemImage: "bolt.fill"),
        ], selection: $selection)
        HStack {
            StatusBadge(status: .ok)
            StatusBadge(status: .soon)
            StatusBadge(status: .overdue)
        }
    }
}

#Preview("Rows and buttons") {
    PreviewVariants {
        CardContainer {
            EntryRow(systemImage: "fuelpump.fill", tint: Theme.Energy.diesel, title: "Aral, Hauptstraße 1",
                     subtitle: "3. Nov. · 68.831 km", amount: "86,30 €", detail: "47,2 L", badge: "Teil")
        }
        PrimaryButton(title: "Speichern") {}
        PrimaryButton(title: "Speichern", isLoading: true) {}
        Button("Konto erstellen") {}.buttonStyle(SecondaryButtonStyle())
    }
}
