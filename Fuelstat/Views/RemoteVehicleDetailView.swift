import PhotosUI
import SwiftUI

/// Vehicle page: photo, key figures, latest fill-ups and master data.
struct RemoteVehicleDetailView: View {
    let vehicleID: String
    @Bindable var store: VehicleStore

    @Environment(\.dismiss) private var dismiss

    @State private var fillups: [RemoteFillup] = []
    @State private var errorMessage: String?
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var isWorking = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false

    private static let recentCount = 5

    var body: some View {
        if let vehicle = store.vehicle(vehicleID) {
            content(vehicle)
        } else {
            ContentUnavailableView("Fahrzeug nicht gefunden", systemImage: "car")
        }
    }

    private func content(_ vehicle: RemoteVehicle) -> some View {
        List {
            Section {
                photoHeader(vehicle)
                    .listRowInsets(EdgeInsets())
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            keyFigures(vehicle)
            recentFillups(vehicle)
            masterData(vehicle)

            Section {
                Button("Fahrzeug löschen", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .disabled(isWorking)
            }
        }
        .navigationTitle(vehicle.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Bearbeiten") { showingEdit = true }
                    .disabled(isWorking)
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showingEdit) {
            RemoteVehicleFormView(store: store, editing: vehicle)
        }
        .confirmationDialog("„\(vehicle.name)“ löschen?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Fahrzeug und alle Einträge löschen", role: .destructive) { delete() }
        } message: {
            Text("Alle Tank- und Ladevorgänge, Ausgaben und Fotos des Fahrzeugs werden ebenfalls gelöscht. Das lässt sich nicht rückgängig machen.")
        }
        .photosPicker(isPresented: $showingPhotoLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { loadPickedPhoto() }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in upload(image) }
                .ignoresSafeArea()
        }
    }

    // MARK: - Sections

    private func photoHeader(_ vehicle: RemoteVehicle) -> some View {
        ZStack(alignment: .bottomTrailing) {
            VehiclePhoto(url: store.imageURL(of: vehicle), fuelType: vehicle.fuelType)
                .frame(maxWidth: .infinity)
                .frame(height: 200)

            Menu {
                Button("Foto auswählen", systemImage: "photo.on.rectangle") { showingPhotoLibrary = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Foto aufnehmen", systemImage: "camera") { showingCamera = true }
                }
                if vehicle.imageURL != nil {
                    Button("Foto entfernen", systemImage: "trash", role: .destructive) { removePhoto() }
                }
            } label: {
                Group {
                    if isWorking {
                        ProgressView()
                    } else {
                        Image(systemName: "camera.fill")
                    }
                }
                .padding(12)
                .background(.thinMaterial, in: Circle())
            }
            .disabled(isWorking)
            .padding(12)
            .accessibilityLabel(vehicle.imageURL == nil ? "Foto hinzufügen" : "Foto ändern")
        }
    }

    @ViewBuilder
    private func keyFigures(_ vehicle: RemoteVehicle) -> some View {
        let stats = store.stats[vehicle.id]
        let unit = vehicle.fuelType.tankCapacityUnit
        Section("Kennzahlen") {
            row("Kilometerstand", store.currentOdometer(of: vehicle).map(Fmt.kilometres))
            row("Ø Verbrauch", stats?.averageConsumption.map { "\(Fmt.number($0, digits: 2)) \(unit)/100 km" })
            if let trend = stats?.trend {
                LabeledContent("Letzte Tankfüllung") {
                    HStack(spacing: 4) {
                        Text("\(Fmt.number(trend.current, digits: 2)) \(unit)/100 km")
                        if trend.diff != 0 {
                            Image(systemName: trend.diff < 0 ? "arrow.down.right" : "arrow.up.right")
                                .foregroundStyle(trend.diff < 0 ? .green : .orange)
                                .accessibilityLabel(trend.diff < 0 ? "weniger als zuvor" : "mehr als zuvor")
                        }
                    }
                }
            }
            row("Ø Preis", stats?.averagePricePerUnit.map { "\(Fmt.pricePerUnit($0))/\(unit)" })
            if stats == nil {
                Text("Noch keine Auswertung. Sie erscheint nach den ersten vollen Tankfüllungen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let missing = stats?.missingOdometer, missing > 0 {
                Text("\(missing) Einträge ohne Kilometerstand zählen nicht für den Verbrauch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func recentFillups(_ vehicle: RemoteVehicle) -> some View {
        Section("Letzte Einträge") {
            if fillups.isEmpty {
                Text("Noch keine Tank- oder Ladevorgänge.")
                    .foregroundStyle(.secondary)
            }
            ForEach(fillups) { fillup in
                FillupRow(fillup: fillup)
            }
        }
    }

    @ViewBuilder
    private func masterData(_ vehicle: RemoteVehicle) -> some View {
        Section("Allgemein") {
            LabeledContent("Kraftstoff", value: vehicle.fuelType.label)
            row("Marke", vehicle.brand)
            row("Modell", vehicle.model)
            row("Baujahr", vehicle.year.map(String.init))
        }

        if vehicle.licensePlate != nil || vehicle.vin != nil || vehicle.firstRegistration != nil {
            Section("Zulassung") {
                row("Kennzeichen", vehicle.licensePlate)
                row("FIN", vehicle.vin)
                row("Erstzulassung", vehicle.firstRegistration.flatMap(Self.formatDate))
            }
        }

        if vehicle.odometerKm != nil || vehicle.tankCapacity != nil || vehicle.batteryCapacity != nil
            || vehicle.tireSizeSummer != nil || vehicle.tireSizeWinter != nil {
            Section("Technik") {
                row("Kilometerstand bei Anschaffung", vehicle.odometerKm.map(Fmt.kilometres))
                row(LocalizedStringKey(vehicle.fuelType.tankCapacityLabel),
                    vehicle.tankCapacity.map { "\(Fmt.number($0)) \(vehicle.fuelType.tankCapacityUnit)" })
                row("Akkukapazität", vehicle.batteryCapacity.map { "\(Fmt.number($0)) kWh" })
                row("Reifen Sommer", vehicle.tireSizeSummer)
                row("Reifen Winter", vehicle.tireSizeWinter)
            }
        }
    }

    @ViewBuilder
    private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        if let value {
            LabeledContent(title, value: value)
        }
    }

    // MARK: - Actions

    private func load() async {
        do {
            async let reloaded = store.reload(vehicleID)
            async let latest = store.fillups(of: vehicleID, limit: Self.recentCount)
            _ = try await reloaded
            fillups = try await latest
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        run {
            try await store.delete(vehicleID)
            dismiss()
        }
    }

    private func loadPickedPhoto() {
        guard let item = photoItem else { return }
        photoItem = nil
        run {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                throw APIError.server(code: "invalid_image", status: 0)
            }
            try await store.setPhoto(image, for: vehicleID)
        }
    }

    private func upload(_ image: UIImage) {
        run { try await store.setPhoto(image, for: vehicleID) }
    }

    private func removePhoto() {
        run { try await store.removePhoto(of: vehicleID) }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await action()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func formatDate(_ value: String) -> String? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: value) else { return value }
        var style = Date.FormatStyle.dateTime.day().month().year()
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }
}

private struct FillupRow: View {
    let fillup: RemoteFillup

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fillup.filledAt?.formatted(date: .abbreviated, time: .omitted) ?? "–")
                if let odometer = fillup.odometerKm {
                    Text(Fmt.kilometres(odometer))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Fmt.number(fillup.amount, digits: 2)) \(fillup.unitLabel)")
                if let cost = fillup.totalCostEur {
                    Text(cost.formatted(.currency(code: "EUR")))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(fillup.isFull ? "" : String(localized: "Teilfüllung"))
    }
}
