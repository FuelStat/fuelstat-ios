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
    }
}

/// Destinations reachable from several tabs.
enum Route: Hashable {
    case vehicle(String)
    case reminders(String)
    case vehicles
}

/// What the quick-entry sheet starts with.
enum EntryKind: String, Identifiable {
    case fuel = "l"
    case charge = "kwh"

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
        .task { await store.load() }
        .onChange(of: selectedID) { VehicleSelection.storedID = selectedID }
        .sheet(item: $entry, onDismiss: { refresh += 1 }) { kind in
            FillupEntryView(store: store, vehicleID: store.resolvedSelection(selectedID), kind: kind)
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

    private func openEntry(_ kind: EntryKind?) {
        guard !store.vehicles.isEmpty else { return }
        if let kind {
            entry = kind
        } else {
            entry = selectedVehicle?.fuelType == .electric ? .charge : .fuel
        }
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
