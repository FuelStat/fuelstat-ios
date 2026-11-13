import SwiftUI

/// Everything about one entry of the list, with edit, delete and – for fill-ups without a real odometer reading –
/// "Kilometerstand nachtragen". Whether the user may change the entry is decided by the API; viewers of a shared
/// vehicle are not offered the actions at all.
struct EntryDetailView: View {
    let store: VehicleStore
    let vehicleID: String
    let item: TimelineItem
    /// Called after the entry was changed or deleted, so the list reloads.
    var onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthSession.self) private var auth

    @State private var showingEdit = false
    @State private var showingOdometer = false
    @State private var confirmingDelete = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// `store.entryChanges` when a sheet was opened, to tell a saved change from a cancelled one.
    @State private var changesBefore = 0

    private var vehicle: RemoteVehicle? { store.vehicle(vehicleID) }
    private var category: RemoteCategory? { store.categories?.category(item.category) }
    private var canChange: Bool { vehicle?.role.canRecord ?? true }

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.screen,
                                              bottom: Theme.Spacing.s, trailing: Theme.Spacing.screen))
            }

            if let errorMessage {
                Section {
                    FormMessage(text: errorMessage)
                }
                .listRowBackground(Theme.card)
            }

            Section {
                ForEach(rows.indices, id: \.self) { index in
                    LabeledContent {
                        Text(verbatim: rows[index].value).monospacedDigit()
                    } label: {
                        Text(rows[index].label)
                    }
                }
            }
            .listRowBackground(Theme.card)

            if let note = noteText {
                Section("Notiz") {
                    Text(verbatim: note)
                }
                .listRowBackground(Theme.card)
            }

            if item.isMissingOdometer, canChange {
                Section {
                    Button("Kilometerstand nachtragen", systemImage: "gauge.with.needle") {
                        changesBefore = store.entryChanges
                        showingOdometer = true
                    }
                        .foregroundStyle(Theme.brand)
                } footer: {
                    Text("Ohne echten Kilometerstand zählt der Eintrag nicht für den Verbrauch. Nachtragen geht jederzeit.")
                }
                .listRowBackground(Theme.card)
            }

            if canChange {
                Section {
                    Button("Löschen", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        .disabled(isWorking)
                }
                .listRowBackground(Theme.card)
            }
        }
        .themedBackground()
        .navigationTitle(kindTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canChange {
                ToolbarItem(placement: .primaryAction) {
                    Button("Bearbeiten") {
                        changesBefore = store.entryChanges
                        showingEdit = true
                    }
                    .disabled(isWorking)
                }
            }
        }
        .task { _ = try? await store.loadCategories() }
        .sheet(isPresented: $showingEdit, onDismiss: sheetClosed) {
            EntryEditor(store: store, vehicleID: vehicleID, item: item)
        }
        .sheet(isPresented: $showingOdometer, onDismiss: sheetClosed) {
            OdometerEditView(store: store, vehicleID: vehicleID, item: item)
                .presentationDetents([.medium])
        }
        .confirmationDialog("Eintrag löschen?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: delete)
        } message: {
            Text("Das lässt sich nicht rückgängig machen.")
        }
    }

    // MARK: - Content

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Label {
                Text(verbatim: item.title(category: category))
                    .font(.title2.bold())
                    .foregroundStyle(Theme.brandDeep)
            } icon: {
                Image(systemName: item.kind == .expense ? (category?.symbol ?? item.kind.symbol) : item.kind.symbol)
                    .foregroundStyle(item.kind == .expense ? (category?.tint ?? Theme.brand) : Theme.brand)
            }
            if let figure = headlineFigure {
                Text(verbatim: figure)
                    .font(.title.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
            }
            if let date = item.date {
                Text(date.formatted(date: .complete, time: item.source == .entry ? .omitted : .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var kindTitle: LocalizedStringKey {
        switch item.kind {
        case .fuel: "Tankvorgang"
        case .charge: "Ladevorgang"
        case .expense: "Ausgabe"
        case .trip: "Fahrt"
        case .odometer: "Kilometerstand"
        }
    }

    private var headlineFigure: String? {
        switch item.kind {
        case .fuel, .charge, .expense: item.cost.map(Fmt.currency)
        case .trip: item.distanceKm.map { "\(Fmt.number($0, digits: 1)) km" }
        case .odometer: item.odometerKm.map(Fmt.kilometres)
        }
    }

    /// The description is the note of an expense or trip.
    private var noteText: String? { item.description }

    private struct Row {
        let label: LocalizedStringKey
        let value: String
    }

    /// Only values the API delivered; nothing is calculated here.
    private var rows: [Row] {
        var rows: [Row] = []
        func add(_ label: LocalizedStringKey, _ value: String?) {
            if let value, !value.isEmpty { rows.append(Row(label: label, value: value)) }
        }
        if let vehicle { add("Fahrzeug", vehicle.name) }
        switch item.kind {
        case .fuel, .charge:
            add("Sorte", store.fuelCatalog?.fuel(item.fuel)?.name)
            add(item.kind == .charge ? "Ladestation" : "Tankstelle", item.place)
            add(item.kind == .charge ? "Geladen" : "Getankt",
                item.amount.map { "\(Fmt.number($0, digits: 2)) \(item.unitLabel)" })
            add("Betrag", item.cost.map(Fmt.currency))
            add("Kilometerstand", odometerText)
            if let isFull = item.isFull {
                add("Füllung", isFull
                    ? (item.kind == .charge ? String(localized: "Voll geladen") : String(localized: "Vollgetankt"))
                    : (item.kind == .charge ? String(localized: "Teilladung") : String(localized: "Teilbetankung")))
            }
            add("Verbrauch", item.consumption.map { "\(Fmt.number($0, digits: 1)) \(item.unitLabel)/100 km" })
            if item.skipPrevious == true { add("Lücke davor", String(localized: "Letzter Eintrag fehlt")) }
        case .expense:
            add("Kategorie", category?.name ?? item.category)
            add("Betrag", item.cost.map(Fmt.currency))
            add("Anbieter", item.place)
            add("Kilometerstand", odometerText)
        case .odometer:
            add("Kilometerstand", odometerText)
        case .trip:
            add("Zweck", item.purpose.flatMap(TripPurpose.init(rawValue:))?.label ?? item.purpose)
            add("Von", item.startPlace)
            add("Nach", item.endPlace)
            add("Strecke", item.distanceKm.map { "\(Fmt.number($0, digits: 1)) km" })
            add("Kilometerstand am Ende", odometerText)
        }
        // On shared vehicles: who recorded the entry.
        if let name = item.createdByName, item.createdBy != auth.user?.id || vehicle?.isShared == true {
            add("Erfasst von", name)
        }
        return rows
    }

    private var odometerText: String? {
        guard let km = item.odometerKm else {
            return item.source == .fillup ? String(localized: "fehlt") : nil
        }
        return item.odometerEstimated ? String(localized: "\(Fmt.kilometres(km)) (geschätzt)") : Fmt.kilometres(km)
    }

    // MARK: - Actions

    /// The entry shown here is a snapshot of the list; after a change the list reloads and this page closes.
    private func changed() {
        onChanged()
        dismiss()
    }

    private func sheetClosed() {
        if store.entryChanges != changesBefore { changed() }
    }

    private func delete() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await store.delete(item, of: vehicleID)
                changed()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Adds the odometer reading to a fill-up. The API accepts this at any time, also after the 14 days in which a
/// fill-up can be changed.
struct OdometerEditView: View {
    let store: VehicleStore
    let vehicleID: String
    let item: TimelineItem

    @Environment(\.dismiss) private var dismiss

    @State private var odometerKm: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var warnings: [String] = []
    @FocusState private var focusedField: Bool?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text(verbatim: summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    NumberField(title: "Kilometerstand", value: $odometerKm.asDouble, unit: "km",
                                hint: item.odometerEstimated ? item.odometerKm.map {
                                    String(localized: "Bisher geschätzt: \(Fmt.kilometres($0))")
                                } : nil,
                                focus: $focusedField, field: true)
                    if let errorMessage { FormMessage(text: errorMessage) }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.m)
            }
            .entryFormChrome(title: "Kilometerstand nachtragen", isSaving: isSaving,
                             canSave: (odometerKm ?? 0) > 0 && !isSaving,
                             onDone: { focusedField = nil }, onCancel: { dismiss() }, onSave: save)
            .onAppear { focusedField = true }
            .odometerWarnings($warnings) { dismiss() }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if let date = item.date { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        if let place = item.place { parts.append(place) }
        if let amount = item.amount { parts.append("\(Fmt.number(amount, digits: 2)) \(item.unitLabel)") }
        return parts.joined(separator: " · ")
    }

    private func save() {
        guard let km = odometerKm, km > 0 else { return }
        focusedField = nil
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let messages = try await store.setFillupOdometer(item.rawID, km: km, of: vehicleID)
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
}
