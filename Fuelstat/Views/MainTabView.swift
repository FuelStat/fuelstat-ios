import SwiftUI
import UIKit

/// Signed-in app: tabs Start · Einträge · Statistik · Profil and a central "+" for quick entry.
///
/// The "+" is a tab item whose selection is intercepted: it opens the quick-entry sheet instead of a tab.
struct MainTabView: View {
    @Environment(AuthSession.self) private var auth
    @State private var store: VehicleStore?

    var body: some View {
        Group {
            if let store {
                MainTabs(store: store)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if store == nil { store = VehicleStore(auth: auth) }
        }
        .fullScreenCover(item: Binding(
            get: { auth.user?.terms.flatMap { $0.required ? $0.version : nil }.map(PendingTerms.init) },
            set: { _ in }
        )) { pending in
            TermsPromptView(version: pending.version)
        }
    }
}

/// Terms of use the user still has to accept, as an item for `fullScreenCover`.
private struct PendingTerms: Identifiable {
    let version: String
    var id: String { version }
}

/// Destinations reachable from several tabs.
enum Route: Hashable {
    case vehicle(String)
    case reminders(String)
    case vehicles
    case feedback
    case releaseNotes
    case deleteAccount
    case account
    case accountUsername
    case accountEmail
    case accountPassword
    case accountTwoFactor
    case accountDevices
    case tripLog(String)
    case sharing(String)
    case invitations
    case categories
    case allReminders
    /// One entry of a vehicle, opened from Start, the vehicle page or the trip log.
    case entry(vehicleID: String, item: TimelineItem)
}

/// What the quick-entry sheet starts with.
enum EntryKind: String, Identifiable {
    case fuel, charge, expense, trip, odometer

    var id: String { rawValue }
}

private struct MainTabs: View {
    @Bindable var store: VehicleStore

    private enum Tab: Hashable {
        case start, entries, add, statistics, profile
    }

    @State private var tab: Tab = .start
    @State private var selectedID: String? = VehicleSelection.storedID
    @State private var entry: EntryKind?
    /// Changes after an entry was saved, so the tabs reload their data.
    @State private var refresh = 0
    @State private var profilePath: [Route] = []
    @State private var router = IntentRouter.shared
    @Environment(\.colorScheme) private var colorScheme

    private var selection: Binding<String?> {
        Binding(get: { store.resolvedSelection(selectedID) }, set: { selectedID = $0 })
    }

    private var selectedVehicle: RemoteVehicle? { store.resolvedSelection(selectedID).flatMap(store.vehicle) }

    var body: some View {
        TabView(selection: Binding(get: { tab }, set: { newValue in
            if newValue == .add {
                openEntry(nil)
            } else {
                tab = newValue
            }
        })) {
            StartView(store: store, selectedID: selection, refresh: refresh,
                      onShowEntries: { tab = .entries },
                      onShowProfile: { tab = .profile },
                      onManageVehicles: manageVehicles)
                .tabItem { Label("Start", systemImage: "house") }
                .tag(Tab.start)

            EntriesView(store: store, selectedID: selection, refresh: refresh, onManageVehicles: manageVehicles)
                .tabItem { Label("Einträge", systemImage: "list.bullet.rectangle") }
                .tag(Tab.entries)

            Color.clear
                .tabItem {
                    Label {
                        Text("Erfassen").accessibilityLabel(Text("Eintrag erfassen"))
                    } icon: {
                        Image(uiImage: Self.addIcon(dark: colorScheme == .dark))
                    }
                }
                .tag(Tab.add)

            StatisticsView(store: store, selectedID: selection, refresh: refresh, onManageVehicles: manageVehicles)
                .tabItem { Label("Statistik", systemImage: "chart.xyaxis.line") }
                .tag(Tab.statistics)

            ProfileView(store: store, path: $profilePath)
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .task {
            await store.load()
            await store.loadFuelCatalog()
            // Lets Siri understand phrases with vehicle names ("VW Golf in Fuelstat öffnen").
            FuelstatShortcuts.updateAppShortcutParameters()
            // Replan local reminders from the API's due dates at every start (loading them does that).
            if ReminderNotifications.isEnabled { _ = await store.allReminders() }
        }
        .onChange(of: selectedID) {
            VehicleSelection.storedID = selectedID
            shareSelection()
        }
        .onChange(of: store.vehicles.map(\.id), initial: true) {
            QuickActions.update(for: store.vehicles, selectedID: store.resolvedSelection(selectedID))
            shareSelection()
        }
        .onChange(of: router.pending, initial: true) { handleIntentRequest() }
        .onChange(of: store.hasLoaded) { handleIntentRequest() }
        .onChange(of: router.savedEntries) { refresh += 1 }
        .sheet(item: $entry, onDismiss: { refresh += 1 }) { kind in
            QuickEntryView(store: store, vehicleID: store.resolvedSelection(selectedID), kind: kind)
        }
    }

    /// The "+" as tab icon: a filled brand circle, drawn as an original-colour image so the tab bar does not
    /// tint it. Being the tab item itself, it sits exactly in the bar on every iOS version.
    private static func addIcon(dark: Bool) -> UIImage {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let fill = (UIColor(named: "Brand") ?? .systemTeal).resolvedColor(with: traits)
        let mark = (UIColor(named: "OnBrand") ?? .white).resolvedColor(with: traits)
        let size = CGSize(width: 34, height: 34)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            fill.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
            if let plus = UIImage(systemName: "plus", withConfiguration: config)?
                .withTintColor(mark, renderingMode: .alwaysOriginal) {
                plus.draw(at: CGPoint(x: (size.width - plus.size.width) / 2, y: (size.height - plus.size.height) / 2))
            }
        }
        return image.withRenderingMode(.alwaysOriginal)
    }

    /// Carries out what an intent asked for (open the entry sheet or a vehicle) once the vehicles are loaded.
    private func handleIntentRequest() {
        guard let request = router.pending, store.hasLoaded else { return }
        router.pending = nil
        switch request {
        case .addEntry(let kind, let vehicleID):
            if let vehicleID, store.vehicle(vehicleID) != nil { selectedID = vehicleID }
            entry = nil
            openEntry(kind)
        case .openVehicle(let id):
            guard store.vehicle(id) != nil else { return }
            entry = nil
            selectedID = id
            tab = .start
        }
    }

    private func openEntry(_ kind: EntryKind?) {
        guard store.vehicles.contains(where: \.role.canRecord) else { return }
        if let kind {
            entry = kind
        } else {
            entry = selectedVehicle?.fuelType == .electric ? .charge : .fuel
        }
    }

    /// Tells the CarPlay widget which vehicle to show: the one selected in the app.
    private func shareSelection() {
        guard store.hasLoaded else { return }
        let id = store.resolvedSelection(selectedID)
        guard id != KeychainStore.loadSelectedVehicle() else { return }
        KeychainStore.saveSelectedVehicle(id)
        WidgetRefresh.reload()
    }

    private func manageVehicles() {
        tab = .profile
        profilePath = [.vehicles]
    }
}

extension View {
    /// Pushes vehicle pages, due dates and vehicle management from any tab.
    func vehicleRoutes(store: VehicleStore) -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .vehicle(let id): RemoteVehicleDetailView(vehicleID: id, store: store)
            case .reminders(let id): RemindersListView(store: store, vehicleID: id)
            case .vehicles: VehicleManagementView(store: store)
            case .feedback: FeedbackView()
            case .releaseNotes: ReleaseNotesView()
            case .deleteAccount: DeleteAccountView()
            case .account: AccountView()
            case .accountUsername: UsernameEditView()
            case .accountEmail: EmailEditView()
            case .accountPassword: PasswordChangeView()
            case .accountTwoFactor: TwoFactorView()
            case .accountDevices: DevicesView()
            case .tripLog(let id): TripLogView(store: store, vehicleID: id)
            case .sharing(let id): VehicleSharingView(store: store, vehicleID: id)
            case .invitations: InvitationsView(store: store)
            case .categories: CategoriesView(store: store)
            case .allReminders: AllRemindersView(store: store)
            // The other screens reload through `store.entryChanges`.
            case .entry(let vehicleID, let item): EntryDetailView(store: store, vehicleID: vehicleID, item: item) {}
            }
        }
    }
}

/// Shown on a tab while there is no vehicle yet or the list failed to load.
struct VehicleListPlaceholder: View {
    @Bindable var store: VehicleStore
    @State private var showingAddVehicle = false

    var body: some View {
        Group {
            if !store.hasLoaded {
                ProgressView()
            } else if let error = store.loadError, store.vehicles.isEmpty {
                ContentUnavailableView {
                    Label("Laden fehlgeschlagen", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Erneut versuchen") { Task { await store.load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("Noch keine Fahrzeuge", systemImage: "car.side")
                } description: {
                    Text("Lege dein erstes Fahrzeug an, danach kannst du Tank- und Ladevorgänge erfassen.")
                } actions: {
                    Button("Fahrzeug hinzufügen") { showingAddVehicle = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingAddVehicle) {
            RemoteVehicleFormView(store: store)
        }
    }
}
