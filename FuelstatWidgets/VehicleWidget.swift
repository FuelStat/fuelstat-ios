import FuelstatCore
import SwiftUI
import WidgetKit

@main
struct FuelstatWidgets: WidgetBundle {
    var body: some Widget {
        VehicleWidget()
        CarPlayVehicleWidget()
    }
}

/// Selected vehicle at a glance: average consumption, the most urgent due date and, on the medium widget,
/// buttons that open the entry sheet (#22).
struct VehicleWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VehicleWidget", intent: SelectVehicleIntent.self,
                               provider: VehicleProvider()) { entry in
            VehicleWidgetView(entry: entry)
        }
        .configurationDisplayName("Fahrzeug")
        .description("Verbrauch und nächste Fälligkeit deines Fahrzeugs. Tanken und Laden mit einem Tipp.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular,
                            .accessoryInline])
    }
}

private enum WidgetColor {
    static let brand = Color("Brand")
    static let onBrand = Color("OnBrand")
    static let brandDeep = Color("BrandDeep")
    static let tint = Color("CardTint")
    static let background = Color("WidgetBackground")

    static func status(_ status: RemoteReminder.Status) -> Color {
        switch status {
        case .ok: Color("StatusOK")
        case .soon: Color("StatusSoon")
        case .overdue: Color("StatusOverdue")
        case .unknown: .secondary
        }
    }
}

struct VehicleWidgetView: View {
    let entry: VehicleWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var isAccessory: Bool {
        [.accessoryRectangular, .accessoryCircular, .accessoryInline].contains(family)
    }

    var body: some View {
        Group {
            switch entry.state {
            case .data(let vehicle):
                content(vehicle)
                    .widgetURL(AppLink.vehicle(vehicle.id).url)
            case .signedOut:
                message("In Fuelstat anmelden", systemImage: "person.crop.circle.badge.exclamationmark")
            case .noVehicle:
                message("Noch kein Fahrzeug", systemImage: "car.side")
            case .offline:
                message("Keine Verbindung", systemImage: "wifi.exclamationmark")
            }
        }
        .containerBackground(for: .widget) {
            if isAccessory { Color.clear } else { WidgetColor.background }
        }
    }

    @ViewBuilder
    private func content(_ vehicle: VehicleSnapshot) -> some View {
        switch family {
        case .systemMedium: MediumView(vehicle: vehicle)
        case .accessoryRectangular: RectangularView(vehicle: vehicle)
        case .accessoryCircular: CircularView(vehicle: vehicle)
        case .accessoryInline: InlineView(vehicle: vehicle)
        default: SmallView(vehicle: vehicle)
        }
    }

    @ViewBuilder
    private func message(_ text: LocalizedStringKey, systemImage: String) -> some View {
        if family == .accessoryInline {
            Label(text, systemImage: systemImage)
        } else {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(isAccessory ? .body : .title2)
                    .foregroundStyle(isAccessory ? .primary : WidgetColor.brand)
                if family != .accessoryCircular {
                    Text(text)
                        .font(isAccessory ? .caption : .subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(text))
        }
    }
}

// MARK: - Text helpers

private extension VehicleSnapshot {
    var consumptionValue: String {
        averageConsumption.map { Fmt.number($0, digits: 1) } ?? "–"
    }

    var vehicleSymbol: String { fuelType == .electric ? "bolt.car.fill" : "car.side.fill" }
}

private extension VehicleSnapshot.Due {
    /// "in 12 Tagen", "heute", "seit 3 Tagen", "bei 120.000 km".
    var whenText: String {
        if let days {
            switch days {
            case ..<0: return String(localized: "seit \(-days) Tagen")
            case 0: return String(localized: "heute")
            case 1: return String(localized: "morgen")
            default: return String(localized: "in \(days) Tagen")
            }
        }
        if let dueKm { return String(localized: "bei \(Fmt.kilometres(dueKm))") }
        return status == .overdue ? String(localized: "überfällig") : ""
    }

    var symbol: String {
        switch status {
        case .overdue: "exclamationmark.circle.fill"
        case .soon: "clock.fill"
        default: "checkmark.circle.fill"
        }
    }
}

// MARK: - Families

private struct ConsumptionFigure: View {
    let vehicle: VehicleSnapshot
    var valueFont: Font = .system(.largeTitle, design: .rounded).weight(.bold)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ø Verbrauch")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(vehicle.consumptionValue)
                .font(valueFont)
                .foregroundStyle(WidgetColor.brandDeep)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(vehicle.consumptionUnit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Durchschnittsverbrauch \(vehicle.consumptionValue) \(vehicle.consumptionUnit)"))
    }
}

private struct DueLine: View {
    let due: VehicleSnapshot.Due?

    var body: some View {
        if let due {
            Label {
                Text("\(due.title) \(due.whenText)")
                    .lineLimit(1)
            } icon: {
                Image(systemName: due.symbol)
                    .foregroundStyle(WidgetColor.status(due.status))
            }
            .font(.caption2.weight(.medium))
        } else {
            Label("Keine Termine", systemImage: "calendar")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct VehicleTitle: View {
    let vehicle: VehicleSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: vehicle.vehicleSymbol)
                .foregroundStyle(WidgetColor.brand)
                .accessibilityHidden(true)
            Text(vehicle.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }
}

private struct SmallView: View {
    let vehicle: VehicleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VehicleTitle(vehicle: vehicle)
            Spacer(minLength: 0)
            ConsumptionFigure(vehicle: vehicle)
            Spacer(minLength: 0)
            DueLine(due: vehicle.nextDue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MediumView: View {
    let vehicle: VehicleSnapshot

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                VehicleTitle(vehicle: vehicle)
                if let plate = vehicle.licensePlate {
                    Text(plate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ConsumptionFigure(vehicle: vehicle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                DueLine(due: vehicle.nextDue)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WidgetColor.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer(minLength: 0)
                if vehicle.canFuel {
                    EntryButton(title: "Tanken", systemImage: "fuelpump.fill",
                                link: .addEntry(kind: "fuel", vehicleID: vehicle.id))
                }
                if vehicle.canCharge {
                    EntryButton(title: "Laden", systemImage: "bolt.fill",
                                link: .addEntry(kind: "charge", vehicleID: vehicle.id))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct EntryButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let link: AppLink

    var body: some View {
        Link(destination: link.url) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetColor.onBrand)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(WidgetColor.brand, in: Capsule())
        }
        .accessibilityHint(Text("Öffnet die Eingabemaske in Fuelstat"))
    }
}

private struct RectangularView: View {
    let vehicle: VehicleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(vehicle.name)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
            Text("Ø \(vehicle.consumptionValue) \(vehicle.consumptionUnit)")
                .font(.caption)
                .lineLimit(1)
            if let due = vehicle.nextDue {
                Label("\(due.title) \(due.whenText)", systemImage: due.symbol)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct CircularView: View {
    let vehicle: VehicleSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Image(systemName: vehicle.fuelType == .electric ? "bolt.fill" : "fuelpump.fill")
                    .font(.caption2)
                    .widgetAccentable()
                Text(vehicle.consumptionValue)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.6)
                Text(vehicle.fuelType.tankCapacityUnit)
                    .font(.system(size: 9))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(vehicle.name): Durchschnittsverbrauch \(vehicle.consumptionValue) \(vehicle.consumptionUnit)"))
    }
}

private struct InlineView: View {
    let vehicle: VehicleSnapshot

    var body: some View {
        Label("\(vehicle.name) · Ø \(vehicle.consumptionValue) \(vehicle.consumptionUnit)",
              systemImage: vehicle.fuelType == .electric ? "bolt.car" : "fuelpump")
    }
}

#Preview(as: .systemSmall) {
    VehicleWidget()
} timeline: {
    VehicleWidgetEntry(date: .now, state: .data(.preview))
    VehicleWidgetEntry(date: .now, state: .signedOut)
}

#Preview(as: .systemMedium) {
    VehicleWidget()
} timeline: {
    VehicleWidgetEntry(date: .now, state: .data(.preview))
}
