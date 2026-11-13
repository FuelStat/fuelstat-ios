import FuelstatCore
import SwiftUI
import WidgetKit

/// Mini widget for the car's display (CarPlay widgets, iOS 26): the vehicle selected in the app with its average
/// consumption. Display only – no buttons, no link, nothing to do while driving. The figure comes from `/stats`.
///
/// CarPlay shows small widgets from the iPhone without a CarPlay entitlement, so this works with the free
/// developer account. On the iPhone itself the widget is not suggested (it would duplicate "Fahrzeug").
struct CarPlayVehicleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CarPlayVehicle", provider: CarPlayProvider()) { entry in
            CarPlayVehicleView(entry: entry)
        }
        .configurationDisplayName("Fahrzeug im Auto")
        .description("Für CarPlay: das in Fuelstat gewählte Fahrzeug und sein Durchschnittsverbrauch.")
        .supportedFamilies([.systemSmall])
        .disfavoredLocations([.homeScreen, .standBy], for: [.systemSmall])
    }
}

struct CarPlayProvider: TimelineProvider {
    func placeholder(in context: Context) -> VehicleWidgetEntry {
        VehicleWidgetEntry(date: .now, state: .data(.preview))
    }

    func getSnapshot(in context: Context, completion: @escaping (VehicleWidgetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await VehicleWidgetEntry.load(vehicleID: KeychainStore.loadSelectedVehicle())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VehicleWidgetEntry>) -> Void) {
        Task {
            let entry = await VehicleWidgetEntry.load(vehicleID: KeychainStore.loadSelectedVehicle())
            // The average changes only with new entries (the app then reloads the widgets).
            let hours: Double = if case .offline = entry.state { 0.5 } else { 6 }
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(hours * 3600))))
        }
    }
}

struct CarPlayVehicleView: View {
    let entry: VehicleWidgetEntry

    var body: some View {
        Group {
            switch entry.state {
            case .data(let vehicle):
                figure(vehicle)
            case .signedOut:
                message("In Fuelstat anmelden", systemImage: "person.crop.circle.badge.exclamationmark")
            case .noVehicle:
                message("Noch kein Fahrzeug", systemImage: "car.side")
            case .offline:
                message("Keine Verbindung", systemImage: "wifi.exclamationmark")
            }
        }
        .containerBackground(for: .widget) { Color("WidgetBackground") }
    }

    /// Large, high-contrast figure that can be read at a glance.
    private func figure(_ vehicle: VehicleSnapshot) -> some View {
        let value = vehicle.averageConsumption.map { Fmt.number($0, digits: 1) } ?? "–"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: vehicle.fuelType == .electric ? "bolt.car.fill" : "car.side.fill")
                    .foregroundStyle(Color("Brand"))
                Text(vehicle.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("Ø \(vehicle.consumptionUnit)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(vehicle.name): Durchschnittsverbrauch \(value) \(vehicle.consumptionUnit)"))
    }

    private func message(_ text: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color("Brand"))
            Text(text)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(as: .systemSmall) {
    CarPlayVehicleWidget()
} timeline: {
    VehicleWidgetEntry(date: .now, state: .data(.preview))
    VehicleWidgetEntry(date: .now, state: .signedOut)
}
