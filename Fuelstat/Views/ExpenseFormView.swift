import SwiftUI

/// Records or changes an expense (insurance, workshop, tax …) or a plain odometer note.
///
/// Categories come from `GET /categories`; locked ones are shown with a "mit Plus" hint and the API decides
/// whether the plan allows them. The API checks the odometer reading and answers with warnings after saving.
struct ExpenseFormView: View {
    enum Mode {
        case expense, odometer
    }

    let store: VehicleStore
    let mode: Mode
    /// The type chips of the quick-entry sheet; nil when the form was opened for one type only.
    var kindSelection: Binding<EntryKind>?
    /// The entry being changed, nil for a new one.
    var editing: TimelineItem?
    var onVehicleChange: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var vehicleID: String
    @State private var categoryKey: String?
    @State private var amount: Double?
    @State private var odometerKm: Int?
    @State private var date = Date.now
    @State private var vendor = ""
    @State private var note = ""

    @State private var categories: [RemoteCategory] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var warnings: [String] = []

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case amount, odometer, vendor, note
    }

    init(store: VehicleStore, vehicleID: String? = nil, mode: Mode = .expense, category: String? = nil,
         kindSelection: Binding<EntryKind>? = nil, editing: TimelineItem? = nil,
         onVehicleChange: ((String) -> Void)? = nil) {
        self.store = store
        self.mode = editing.map { $0.kind == .odometer ? .odometer : .expense } ?? mode
        self.kindSelection = kindSelection
        self.editing = editing
        self.onVehicleChange = onVehicleChange
        _vehicleID = State(initialValue: vehicleID ?? store.lastUsedVehicleID ?? "")
        _categoryKey = State(initialValue: editing?.category ?? category)
        if let editing {
            _amount = State(initialValue: editing.cost)
            _odometerKm = State(initialValue: editing.odometerKm.map { Int($0) })
            _date = State(initialValue: editing.date ?? .now)
            _vendor = State(initialValue: editing.place ?? "")
            _note = State(initialValue: editing.description ?? "")
        }
    }

    private var vehicle: RemoteVehicle? { store.vehicle(vehicleID) }

    /// Categories offered for an expense. The current one stays in the list even when it is no longer selectable.
    private var choices: [RemoteCategory] {
        categories.filter { $0.form == "expense" && ($0.isSelectable || $0.key == categoryKey) }
    }

    private var canSave: Bool {
        guard vehicle != nil, !isSaving else { return false }
        switch mode {
        case .expense: return categoryKey != nil && (amount ?? -1) >= 0
        case .odometer: return (odometerKm ?? 0) > 0
        }
    }

    private var title: LocalizedStringKey {
        if editing != nil { return "Eintrag bearbeiten" }
        return mode == .odometer ? "Kilometerstand erfassen" : "Ausgabe erfassen"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if editing == nil {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            if let kindSelection {
                                EntryTypeChips(fuelType: vehicle?.fuelType, selection: kindSelection)
                            }
                            EntryVehiclePicker(store: store, vehicleID: $vehicleID)
                        }
                    }

                    if mode == .expense {
                        categorySection
                        NumberField(title: "Betrag", value: $amount, unit: "€", digits: 2, focus: $focusedField,
                                    field: Field.amount)
                    }

                    NumberField(title: mode == .odometer ? "Kilometerstand" : "Kilometerstand (optional)",
                                value: $odometerKm.asDouble, unit: "km",
                                hint: vehicle.flatMap { store.currentOdometer(of: $0) }.map {
                                    String(localized: "Bisher: \(Fmt.kilometres($0))")
                                },
                                focus: $focusedField, field: Field.odometer)

                    CardContainer(padding: Theme.Spacing.s) {
                        DatePicker("Datum", selection: $date, displayedComponents: .date)
                    }

                    if mode == .expense {
                        LabeledTextField(title: "Anbieter (optional)", text: $vendor, focus: $focusedField,
                                         field: Field.vendor)
                    }
                    LabeledTextField(title: "Notiz (optional)", text: $note, axis: .vertical, focus: $focusedField,
                                     field: Field.note)

                    if let errorMessage { FormMessage(text: errorMessage) }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.m)
            }
            .entryFormChrome(title: title, isSaving: isSaving, canSave: canSave,
                             onDone: { focusedField = nil }, onCancel: { dismiss() }, onSave: save)
            .interactiveDismissDisabled(isSaving || amount != nil || odometerKm != nil)
            .task { await loadCategories() }
            .onChange(of: vehicleID) { onVehicleChange?(vehicleID) }
            .odometerWarnings($warnings) { dismiss() }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Kategorie")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if choices.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.xs)],
                      alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(choices) { category in
                    CategoryChoice(category: category, isSelected: category.key == categoryKey) {
                        categoryKey = category.key
                    }
                }
            }
        }
    }

    private func loadCategories() async {
        guard mode == .expense else { return }
        do {
            categories = try await store.loadCategories().categories
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        focusedField = nil
        guard canSave else { return }
        let input = ExpenseInput(
            vehicleId: vehicleID,
            category: mode == .odometer ? ExpenseInput.odometerCategory : (categoryKey ?? ""),
            amountEur: mode == .odometer ? 0 : (amount ?? 0),
            odometerKm: odometerKm,
            occurredAt: date,
            vendor: mode == .odometer ? nil : trimmed(vendor),
            description: trimmed(note)
        )
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let messages = try await store.saveExpense(input, id: editing?.rawID)
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

/// Category as a selectable tile: icon in the category colour, name, and a "mit Plus" hint when the plan lacks it.
private struct CategoryChoice: View {
    let category: RemoteCategory
    let isSelected: Bool
    let action: () -> Void

    private var isLocked: Bool { !category.isAvailable && !isSelected }

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: category.symbol)
                    .foregroundStyle(isSelected ? Theme.onBrand : category.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: category.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if isLocked {
                        Label("mit Plus", systemImage: "lock.fill")
                            .font(.caption)
                            .opacity(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .foregroundStyle(isSelected ? Theme.onBrand : Theme.brandDeep)
            .background(isSelected ? Theme.brand : Theme.card, in: .tile)
            .contentShape(.tile)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
