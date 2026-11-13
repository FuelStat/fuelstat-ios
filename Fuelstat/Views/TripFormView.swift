import SwiftUI

/// Records or changes a trip of the trip log.
///
/// The odometer at the end is required. With a start reading the API derives the distance; without one the
/// distance is entered instead. Which purposes the plan allows is decided by the API.
struct TripFormView: View {
    let store: VehicleStore
    var kindSelection: Binding<EntryKind>?
    /// Id of the trip being changed, nil for a new one.
    var editingID: String?
    var onVehicleChange: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var vehicleID: String
    @State private var date = Date.now
    @State private var purpose: TripPurpose = .personal
    @State private var odometerStart: Int?
    @State private var odometerEnd: Int?
    @State private var distance: Double?
    @State private var startPlace = ""
    @State private var endPlace = ""
    @State private var note = ""
    /// The start reading was prefilled with the vehicle's current odometer, not typed.
    @State private var startIsPrefilled = false

    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var warnings: [String] = []

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case start, end, distance, from, to, note
    }

    init(store: VehicleStore, vehicleID: String? = nil, kindSelection: Binding<EntryKind>? = nil,
         editingID: String? = nil, onVehicleChange: ((String) -> Void)? = nil) {
        self.store = store
        self.kindSelection = kindSelection
        self.editingID = editingID
        self.onVehicleChange = onVehicleChange
        _vehicleID = State(initialValue: vehicleID ?? store.lastUsedVehicleID ?? "")
        _isLoading = State(initialValue: editingID != nil)
    }

    private var vehicle: RemoteVehicle? { store.vehicle(vehicleID) }

    private var canSave: Bool {
        guard vehicle != nil, !isSaving, !isLoading, let end = odometerEnd, end > 0 else { return false }
        return odometerStart != nil || (distance ?? -1) >= 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if editingID == nil {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            if let kindSelection {
                                EntryTypeChips(store: store, vehicle: vehicle, selection: kindSelection)
                            }
                            EntryVehiclePicker(store: store, vehicleID: $vehicleID)
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Zweck")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ChipGroup(options: TripPurpose.allCases.map {
                            .init(value: $0, title: LocalizedStringKey($0.label), systemImage: $0.symbol)
                        }, selection: $purpose)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                            NumberField(title: "Start (optional)", value: $odometerStart.asDouble, unit: "km",
                                        focus: $focusedField, field: Field.start)
                            NumberField(title: "Ende", value: $odometerEnd.asDouble, unit: "km",
                                        focus: $focusedField, field: Field.end)
                        }
                        if odometerStart == nil {
                            NumberField(title: "Strecke", value: $distance, unit: "km", digits: 1,
                                        hint: String(localized: "Ohne Kilometerstand am Start gibst du die Strecke an."),
                                        focus: $focusedField, field: Field.distance)
                        } else if let start = odometerStart, let end = odometerEnd, end >= start {
                            Text("Strecke: \(Fmt.kilometres(Double(end - start)))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        LabeledTextField(title: "Von (optional)", text: $startPlace, focus: $focusedField,
                                         field: Field.from)
                        LabeledTextField(title: "Nach (optional)", text: $endPlace, focus: $focusedField,
                                         field: Field.to)
                    }

                    CardContainer(padding: Theme.Spacing.s) {
                        DatePicker("Beginn", selection: $date)
                    }

                    LabeledTextField(title: "Notiz (optional)", text: $note, axis: .vertical, focus: $focusedField,
                                     field: Field.note)

                    if let errorMessage { FormMessage(text: errorMessage) }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.m)
            }
            .overlay { if isLoading { ProgressView() } }
            .entryFormChrome(title: editingID == nil ? "Fahrt erfassen" : "Fahrt bearbeiten", isSaving: isSaving,
                             canSave: canSave, onDone: { focusedField = nil }, onCancel: { dismiss() }, onSave: save)
            .interactiveDismissDisabled(isSaving || odometerEnd != nil)
            .task { await prepare() }
            .onChange(of: vehicleID) {
                onVehicleChange?(vehicleID)
                prefillStart()
            }
            .onChange(of: odometerStart) { if focusedField == .start { startIsPrefilled = false } }
            .odometerWarnings($warnings) { dismiss() }
        }
    }

    /// Loads the trip being changed, or prefills the start with the vehicle's current odometer.
    private func prepare() async {
        guard let editingID else {
            prefillStart()
            return
        }
        defer { isLoading = false }
        do {
            let trip = try await store.trip(editingID)
            date = trip.startedAt ?? .now
            purpose = TripPurpose(rawValue: trip.purpose) ?? .personal
            odometerStart = trip.odometerStart.map { Int($0) }
            odometerEnd = trip.odometerEnd.map { Int($0) }
            distance = trip.distanceKm
            startPlace = trip.startPlace ?? ""
            endPlace = trip.endPlace ?? ""
            note = trip.note ?? ""
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prefillStart() {
        guard editingID == nil, odometerStart == nil || startIsPrefilled, let vehicle else { return }
        odometerStart = store.currentOdometer(of: vehicle).map { Int($0) }
        startIsPrefilled = odometerStart != nil
    }

    private func save() {
        focusedField = nil
        guard canSave, let end = odometerEnd else { return }
        let input = TripInput(
            vehicleId: vehicleID,
            startedAt: date,
            odometerStart: odometerStart,
            odometerEnd: end,
            distanceKm: odometerStart == nil ? distance : nil,
            startPlace: trimmed(startPlace),
            endPlace: trimmed(endPlace),
            purpose: purpose.rawValue,
            note: trimmed(note)
        )
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let messages = try await store.saveTrip(input, id: editingID)
                if messages.isEmpty {
                    Haptics.success()
                    dismiss()
                } else {
                    Haptics.warning()
                    warnings = messages
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
