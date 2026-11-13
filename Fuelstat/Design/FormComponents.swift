import FuelstatCore
import SwiftUI

// Building blocks of the entry forms (expense, odometer note, trip): labelled fields on tiles, the entry type
// chips of the quick-entry sheet and the alert for odometer warnings.

// MARK: - NumberField

/// Big numeric field with a visible label and unit (odometer, amount, distance).
struct NumberField<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var value: Double?
    var unit: String?
    var digits = 0
    var hint: String?
    var focus: FocusState<Value?>.Binding
    let field: Value

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(0...digits)))
                    .keyboardType(digits == 0 ? .numberPad : .decimalPad)
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(Theme.brandDeep)
                    .focused(focus, equals: field)
                    .accessibilityLabel(title)
                if let unit {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            if let hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .tile)
        .overlay {
            if focus.wrappedValue == field {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(Theme.brand, lineWidth: 2)
            }
        }
        .contentShape(.tile)
        .onTapGesture { focus.wrappedValue = field }
    }
}

/// Whole-number variant for odometer readings.
extension Binding where Value == Int? {
    /// Lets a `NumberField` edit a whole number.
    var asDouble: Binding<Double?> {
        Binding<Double?>(
            get: { wrappedValue.map(Double.init) },
            set: { wrappedValue = $0.map { Int($0.rounded()) } }
        )
    }
}

// MARK: - Text field

/// Text field with a visible label above it, on a tile.
struct LabeledTextField<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var axis: Axis = .horizontal
    var focus: FocusState<Value?>.Binding
    let field: Value

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(title, text: $text, axis: axis)
                .lineLimit(axis == .vertical ? 2...5 : 1...1)
                .focused(focus, equals: field)
                .accessibilityLabel(title)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .tile)
        .contentShape(.tile)
        .onTapGesture { focus.wrappedValue = field }
    }
}

// MARK: - Entry type chips

/// The type picker at the top of the quick-entry sheet: Tanken, Laden, Ausgabe, Fahrt, Kilometer.
/// Fuel and charging are only offered when the vehicle can do them.
struct EntryTypeChips: View {
    let store: VehicleStore
    let vehicle: RemoteVehicle?
    @Binding var selection: EntryKind

    private var kinds: [EntryKind] {
        let modes = vehicle.map { store.entryModes(of: $0) } ?? (fuel: true, charge: false)
        var kinds: [EntryKind] = []
        if modes.fuel { kinds.append(.fuel) }
        if modes.charge { kinds.append(.charge) }
        return kinds + [.expense, .trip, .odometer]
    }

    var body: some View {
        ChipGroup(options: kinds.map { .init(value: $0, title: $0.title, systemImage: $0.symbol) },
                  selection: $selection)
    }
}

extension EntryKind {
    var title: LocalizedStringKey {
        switch self {
        case .fuel: "Tanken"
        case .charge: "Laden"
        case .expense: "Ausgabe"
        case .trip: "Fahrt"
        case .odometer: "Kilometer"
        }
    }

    var symbol: String {
        switch self {
        case .fuel: "fuelpump.fill"
        case .charge: "bolt.fill"
        case .expense: "eurosign.circle.fill"
        case .trip: "arrow.triangle.turn.up.right.diamond.fill"
        case .odometer: "gauge.with.needle.fill"
        }
    }
}

// MARK: - Form chrome

/// Vehicle choice of an entry form: a picker with several vehicles, otherwise just the name.
struct EntryVehiclePicker: View {
    let store: VehicleStore
    @Binding var vehicleID: String

    /// Vehicles the user may record entries for; the API enforces the rights.
    private var vehicles: [RemoteVehicle] { store.vehicles.filter(\.role.canRecord) }

    var body: some View {
        if vehicles.count > 1 {
            CardContainer(padding: Theme.Spacing.s) {
                Picker("Fahrzeug", selection: $vehicleID) {
                    ForEach(vehicles) { Text($0.name).tag($0.id) }
                }
                .tint(Theme.brand)
            }
        } else if let vehicle = store.vehicle(vehicleID) {
            Label(vehicle.name, systemImage: "car.side")
                .font(.headline)
                .foregroundStyle(Theme.brandDeep)
        }
    }
}

/// Error line of a form.
struct FormMessage: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.Status.overdue)
    }
}

extension View {
    /// Scroll view chrome shared by the entry forms: background, save button pinned to the bottom, cancel and
    /// keyboard "Fertig".
    func entryFormChrome(title: LocalizedStringKey, saveTitle: LocalizedStringKey = "Speichern", isSaving: Bool,
                         canSave: Bool, onDone: @escaping () -> Void, onCancel: @escaping () -> Void,
                         onSave: @escaping () -> Void) -> some View {
        scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: saveTitle, isLoading: isSaving, action: onSave)
                    .disabled(!canSave)
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(.bar)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig", action: onDone)
                }
            }
    }

    /// The API saved the entry but warns about the odometer reading; closing the alert closes the form.
    func odometerWarnings(_ warnings: Binding<[String]>, onDismiss: @escaping () -> Void) -> some View {
        alert("Gespeichert, bitte prüfen", isPresented: Binding(
            get: { !warnings.wrappedValue.isEmpty },
            set: { shown in
                if !shown {
                    warnings.wrappedValue = []
                    onDismiss()
                }
            }
        )) {
            Button("OK") {}
        } message: {
            Text(warnings.wrappedValue.joined(separator: "\n"))
        }
    }
}

// MARK: - Category look

extension RemoteCategory {
    /// SF Symbol for the icon name the API delivers.
    var symbol: String { CategoryStyle.symbol(forIcon: icon) }

    /// The colour the API delivers, falling back to the brand colour.
    var tint: Color {
        CategoryStyle.rgb(hex: color).map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Theme.brand
    }
}

extension Color {
    /// Colour from a hex value the API delivers (own categories), or nil when it cannot be read.
    init?(apiHex: String) {
        guard let rgb = CategoryStyle.rgb(hex: apiHex) else { return nil }
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
