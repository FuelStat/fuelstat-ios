import FuelstatCore
import SwiftUI

/// Charging stations near the user (Open Charge Map via `GET /charging-stations`), shown when recording a
/// charging session. The data and its order come from the API; the app only displays them.

/// Link and name of the data source; Open Charge Map's licence asks for it to be shown.
struct ChargingSourceLink: View {
    var body: some View {
        Link("Daten: Open Charge Map, CC BY 4.0", destination: URL(string: "https://openchargemap.org")!)
            .font(.footnote)
            .foregroundStyle(Theme.brand)
    }
}

/// Nearby charging station as a horizontal card: name, power, plugs and distance; the selected one is highlighted.
struct ChargerCard: View {
    let station: ChargingStation
    let isSelected: Bool
    let isRecent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xxs) {
                    Text(station.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if isRecent {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .accessibilityLabel("zuletzt genutzt")
                    }
                }
                Text(station.maxPowerText.map { "bis \($0) kW" } ?? "–")
                    .font(.title3.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                if let plugs = station.connectorsText {
                    Text(plugs)
                        .font(.footnote)
                        .lineLimit(1)
                }
                HStack(spacing: Theme.Spacing.xxs) {
                    if let km = station.distanceKm {
                        Text("\(km.formatted(.number.precision(.fractionLength(1)))) km")
                    }
                    if !station.isOperational {
                        Text("außer Betrieb")
                    }
                }
                .font(.footnote)
                .opacity(0.85)
            }
            .foregroundStyle(isSelected ? Theme.onBrand : Theme.brandDeep)
            .padding(Theme.Spacing.s)
            .frame(width: 170, alignment: .leading)
            .frame(minHeight: 104, alignment: .topLeading)
            .background(isSelected ? Theme.brand : Theme.card, in: .tile)
            .contentShape(.tile)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// All charging stations nearby as a list. With `onPick` a tap chooses the station; without it the list is
/// for browsing only.
struct ChargingStationPickerView: View {
    let store: VehicleStore
    var onPick: ((ChargingStation) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var location = LocationProvider()
    @State private var stations: [ChargingStation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(stations) { station in
                    Group {
                        if let onPick {
                            Button {
                                onPick(station)
                                dismiss()
                            } label: {
                                ChargerRow(station: station)
                            }
                            .foregroundStyle(.primary)
                        } else {
                            ChargerRow(station: station)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                if !stations.isEmpty {
                    Section { ChargingSourceLink() }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("Suche Ladestationen …")
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Keine Ladestationen", systemImage: "bolt.slash")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Erneut versuchen") { Task { await load() } }
                    }
                } else if stations.isEmpty {
                    ContentUnavailableView("Keine Ladestationen im Umkreis von 10 km", systemImage: "bolt")
                }
            }
            .themedBackground()
            .navigationTitle("In der Nähe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(onPick == nil ? "Schließen" : "Abbrechen") { dismiss() }
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = stations.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            let here = try await location.currentLocation()
            stations = try await store.chargingStations(near: here.coordinate.latitude, here.coordinate.longitude)
                .stations
        } catch is CancellationError {
            return
        } catch APIError.server(code: "http_404", _) {
            // Server without the charging station endpoint (older Fuelstat version)
            errorMessage = String(localized: "Die Ladestationssuche ist auf diesem Server nicht eingerichtet.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ChargerRow: View {
    let station: ChargingStation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(station.title).font(.headline)
                Spacer()
                if let power = station.maxPowerText {
                    Text("bis \(power) kW")
                        .font(.headline)
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.brand)
                        .monospacedDigit()
                }
            }
            if !station.address.isEmpty {
                Text(station.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if let distance = station.distanceKm {
                    Text(distance.formatted(.number.precision(.fractionLength(1))) + " km")
                }
                if let points = station.points {
                    Text(points == 1 ? "1 Ladepunkt" : "\(points) Ladepunkte")
                }
                if let plugs = station.connectorsText {
                    Text(plugs)
                }
                if !station.isOperational {
                    Text("außer Betrieb").foregroundStyle(Theme.Status.overdue)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let cost = station.usageCost {
                Text(cost)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
