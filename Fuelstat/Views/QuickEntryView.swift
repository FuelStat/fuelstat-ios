import SwiftUI

/// The quick-entry sheet behind the "+": type chips at the top (Tanken, Laden, Ausgabe, Fahrt, Kilometer) and the
/// form of the chosen type below. The chosen vehicle carries over when the type changes.
struct QuickEntryView: View {
    let store: VehicleStore

    @State private var kind: EntryKind
    @State private var vehicleID: String?

    init(store: VehicleStore, vehicleID: String? = nil, kind: EntryKind) {
        self.store = store
        // Entries can only be recorded for vehicles the user may edit; the API enforces it.
        let preferred = vehicleID.flatMap(store.vehicle).flatMap { $0.role.canRecord ? $0.id : nil }
        _vehicleID = State(initialValue: preferred ?? store.vehicles.first(where: \.role.canRecord)?.id)
        _kind = State(initialValue: kind)
    }

    var body: some View {
        switch kind {
        case .fuel, .charge:
            FillupEntryView(store: store, vehicleID: vehicleID, kind: kind, kindSelection: $kind,
                            onVehicleChange: { vehicleID = $0 })
        case .expense:
            ExpenseFormView(store: store, vehicleID: vehicleID, mode: .expense, kindSelection: $kind,
                            onVehicleChange: { vehicleID = $0 })
        case .odometer:
            ExpenseFormView(store: store, vehicleID: vehicleID, mode: .odometer, kindSelection: $kind,
                            onVehicleChange: { vehicleID = $0 })
                .id(EntryKind.odometer)
        case .trip:
            TripFormView(store: store, vehicleID: vehicleID, kindSelection: $kind,
                         onVehicleChange: { vehicleID = $0 })
        }
    }
}
