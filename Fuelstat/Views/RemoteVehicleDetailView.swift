import PhotosUI
import SwiftUI

/// Vehicle page: full-width photo with a sheet-style card over it; segments Übersicht · Einträge · Statistik · Daten.
struct RemoteVehicleDetailView: View {
    let vehicleID: String
    @Bindable var store: VehicleStore

    @Environment(\.dismiss) private var dismiss

    @State private var latest: [TimelineItem] = []
    @State private var errorMessage: String?
    @State private var showingEdit = false
    @State private var showingFillup = false
    @State private var confirmingDelete = false
    @State private var isWorking = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false
    @State private var segment: Segment = .overview
    @State private var chartRange: ConsumptionChartCard.Range = .year
    @State private var reminders: [RemoteReminder] = []

    private static let recentCount = 5
    /// Entries shown in the "Einträge" segment; the full list is in the Einträge tab.
    private static let entriesCount = 30

    var body: some View {
        if let vehicle = store.vehicle(vehicleID) {
            content(vehicle)
        } else {
            ContentUnavailableView("Fahrzeug nicht gefunden", systemImage: "car")
        }
    }

    private enum Segment: Hashable {
        case overview, entries, statistics, data
    }

    private func content(_ vehicle: RemoteVehicle) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                photoHeader(vehicle)

                VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                    Capsule()
                        .fill(.secondary.opacity(0.4))
                        .frame(width: 36, height: 5)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    titleBlock(vehicle)

                    Picker("Ansicht", selection: $segment) {
                        Text("Übersicht").tag(Segment.overview)
                        Text("Einträge").tag(Segment.entries)
                        Text("Statistik").tag(Segment.statistics)
                        Text("Daten").tag(Segment.data)
                    }
                    .pickerStyle(.segmented)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Status.overdue)
                    }

                    switch segment {
                    case .overview: overview(vehicle)
                    case .entries:
                        RecentEntriesCard(store: store, vehicle: vehicle, items: latest)
                    case .statistics:
                        ConsumptionChartCard(stats: store.stats[vehicle.id], fuelType: vehicle.fuelType,
                                             range: $chartRange, catalog: store.fuelCatalog)
                    case .data:
                        MasterDataCards(vehicle: vehicle, odometer: store.currentOdometer(of: vehicle))
                        NavigationLink(value: Route.sharing(vehicle.id)) {
                            Label(vehicle.isShared ? "Zugriff ansehen" : "Fahrzeug teilen", systemImage: "person.2")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        // Only the owner may delete the vehicle; the API enforces it.
                        if !vehicle.isShared {
                            Button("Fahrzeug löschen", systemImage: "trash", role: .destructive) {
                                confirmingDelete = true
                            }
                            .disabled(isWorking)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Theme.Spacing.s)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xl)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.card, topTrailingRadius: Theme.Radius.card,
                                           style: .continuous)
                        .fill(Theme.background)
                        .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
                )
                .offset(y: -Theme.Radius.card)
            }
        }
        .background(Theme.background)
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                NavigationLink(value: Route.tripLog(vehicle.id)) {
                    Label("Fahrtenbuch", systemImage: "book.closed")
                }
                // Master data and photo belong to the owner; the API enforces it.
                if !vehicle.isShared {
                    Button("Bearbeiten", systemImage: "pencil") { showingEdit = true }
                        .disabled(isWorking)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: store.entryChanges) { await load() }
        .sheet(isPresented: $showingEdit) {
            RemoteVehicleFormView(store: store, editing: vehicle)
        }
        .sheet(isPresented: $showingFillup, onDismiss: { Task { await load() } }) {
            QuickEntryView(store: store, vehicleID: vehicle.id, kind: vehicle.fuelType == .electric ? .charge : .fuel)
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
                .frame(height: 300)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .center)
                }

            if !vehicle.isShared {
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
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
            }
            .disabled(isWorking)
            .padding(.trailing, Theme.Spacing.m)
            .padding(.bottom, Theme.Radius.card + Theme.Spacing.s)
            .accessibilityLabel(vehicle.imageURL == nil ? "Foto hinzufügen" : "Foto ändern")
            }
        }
    }

    private func titleBlock(_ vehicle: RemoteVehicle) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(vehicle.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.brandDeep)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            HStack(spacing: Theme.Spacing.xs) {
                Label(vehicle.fuelType.label, systemImage: vehicle.fuelType.badgeSymbol)
                    .foregroundStyle(vehicle.fuelType.energyColor)
                if let plate = vehicle.licensePlate {
                    Text(plate).foregroundStyle(.secondary)
                }
                if let odometer = store.currentOdometer(of: vehicle) {
                    Text(Fmt.kilometres(odometer))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.subheadline.weight(.medium))
            if vehicle.isShared { SharedVehicleBadge(vehicle: vehicle) }
        }
    }

    @ViewBuilder
    private func overview(_ vehicle: RemoteVehicle) -> some View {
        KeyFigureTiles(vehicle: vehicle, stats: store.stats[vehicle.id], odometer: store.currentOdometer(of: vehicle),
                       catalog: store.fuelCatalog)
        if vehicle.role.canRecord {
            PrimaryButton(title: vehicle.fuelType == .electric ? "Laden erfassen" : "Tanken erfassen",
                          systemImage: vehicle.fuelType == .electric ? "bolt.fill" : "fuelpump.fill") {
                showingFillup = true
            }
        }
        NavigationLink(value: Route.reminders(vehicle.id)) {
            RemindersCard(reminders: reminders)
        }
        .buttonStyle(.plain)
        RecentEntriesCard(store: store, vehicle: vehicle, items: Array(latest.prefix(Self.recentCount))) {
            segment = .entries
        }
    }

    // MARK: - Actions

    private func load() async {
        do {
            async let reloaded = store.reload(vehicleID)
            async let entries = store.latestFillups(of: vehicleID, limit: Self.entriesCount)
            async let due = try? store.reminders(of: vehicleID)
            _ = try await reloaded
            latest = try await entries
            reminders = await due ?? reminders
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
}
