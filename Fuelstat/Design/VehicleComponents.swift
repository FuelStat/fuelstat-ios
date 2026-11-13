import SwiftUI

// MARK: - VehicleHero

/// Vehicle as the hero of a screen: photo with a bottom gradient, name, plate, odometer and energy badge.
struct VehicleHero: View {
    let vehicle: RemoteVehicle
    let photoURL: URL?
    let odometer: String?
    var height: CGFloat = 200

    @ScaledMetric(relativeTo: .title) private var scaledHeight: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VehiclePhoto(url: photoURL, fuelType: vehicle.fuelType)
                .frame(maxWidth: .infinity)
                .frame(height: height * min(scaledHeight, 1.5))
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                }

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                EnergyBadge(fuelType: vehicle.fuelType)
                Text(vehicle.name)
                    .font(.title2.bold())
                    .lineLimit(2)
                Text([vehicle.licensePlate, odometer].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(Theme.Spacing.m)
        }
        .clipShape(.card)
        // Taps only inside the card, never on what the photo would cover beyond it.
        .contentShape(.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [vehicle.name, vehicle.fuelType.label]
        if let plate = vehicle.licensePlate { parts.append(String(localized: "Kennzeichen \(plate)")) }
        if let odometer { parts.append(String(localized: "Kilometerstand \(odometer)")) }
        return parts.joined(separator: ", ")
    }
}

/// Fuel type label with its energy symbol, for use on photos and cards.
struct EnergyBadge: View {
    let fuelType: RemoteFuelType

    var body: some View {
        Label(fuelType.label, systemImage: fuelType.badgeSymbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(.ultraThinMaterial, in: .capsule)
            .environment(\.colorScheme, .dark)
    }
}

extension RemoteFuelType {
    /// Symbol for badges and entry rows.
    var badgeSymbol: String {
        switch self {
        case .electric: "bolt.fill"
        case .phev, .hybrid: "leaf.fill"
        default: "fuelpump.fill"
        }
    }
}

// MARK: - VehicleSwitcher

/// Header button "VW Golf ▾" that opens a sheet with all vehicles. The choice is stored by `VehicleSelection`.
struct VehicleSwitcher: View {
    let store: VehicleStore
    @Binding var selectedID: String?
    var onManage: (() -> Void)?

    @State private var showingSheet = false

    private var selected: RemoteVehicle? { selectedID.flatMap(store.vehicle) }

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: Theme.Spacing.xxs) {
                Text(selected?.name ?? String(localized: "Fahrzeug wählen"))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.brand)
            }
            .font(.title2.bold())
            .foregroundStyle(Theme.brandDeep)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Fahrzeug: \(selected?.name ?? "")"))
        .accessibilityHint(Text("Öffnet die Fahrzeugauswahl"))
        .sheet(isPresented: $showingSheet) {
            VehicleSwitcherSheet(store: store, selectedID: $selectedID) {
                showingSheet = false
                onManage?()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct VehicleSwitcherSheet: View {
    let store: VehicleStore
    @Binding var selectedID: String?
    var onManage: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .headline) private var photoSize: CGFloat = 52

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.vehicles) { vehicle in
                    Button {
                        selectedID = vehicle.id
                        Haptics.selection()
                        dismiss()
                    } label: {
                        HStack(spacing: Theme.Spacing.s) {
                            VehiclePhoto(url: store.imageURL(of: vehicle), fuelType: vehicle.fuelType)
                                .frame(width: photoSize, height: photoSize)
                                .clipShape(.tile)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vehicle.name).font(.headline)
                                Text([vehicle.licensePlate, vehicle.fuelType.label].compactMap { $0 }
                                    .joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if vehicle.isShared { SharedVehicleBadge(vehicle: vehicle) }
                            }
                            Spacer()
                            if vehicle.id == selectedID {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                    .accessibilityAddTraits(vehicle.id == selectedID ? [.isSelected] : [])
                }
                Section {
                    Button("Fahrzeuge verwalten", systemImage: "car.2", action: onManage)
                        .foregroundStyle(Theme.brand)
                        .listRowBackground(Theme.card)
                }
            }
            .themedBackground()
            .navigationTitle("Fahrzeug wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
}

/// Marks a vehicle of another account that was shared with the user: icon, owner and the user's role.
struct SharedVehicleBadge: View {
    let vehicle: RemoteVehicle

    var body: some View {
        Label(Self.text(for: vehicle), systemImage: "person.2.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.brandDeep)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 2)
            .background(Theme.cardTint, in: .capsule)
    }

    static func text(for vehicle: RemoteVehicle) -> String {
        if let owner = vehicle.ownerName {
            return String(localized: "Geteilt von \(owner) · \(vehicle.role.label)")
        }
        return String(localized: "Geteilt · \(vehicle.role.label)")
    }
}

/// The vehicle chosen in the switcher, remembered across launches.
enum VehicleSelection {
    private static let key = "selection.vehicleID"

    static var storedID: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
