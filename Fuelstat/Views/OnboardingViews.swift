import SwiftUI

/// First start (FuelStat/fuelstat-ios #33, like `onboarding.php` of the web app): an account without vehicles gets
/// two short steps, "Fahrzeug anlegen" and "Ersten Eintrag erfassen", and open invitations to shared vehicles.
/// It can be skipped. Location and notification permissions are not asked here but where they are needed
/// (nearby stations, switching on reminders), with their own explanation.
struct OnboardingView: View {
    @Bindable var store: VehicleStore
    let pendingInvitations: Int
    var onShowInvitations: () -> Void
    var onSkip: () -> Void

    @State private var showingAddVehicle = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Image(systemName: "fuelpump.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.brand)
                        .accessibilityHidden(true)
                    Text("Willkommen bei Fuelstat")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.brandDeep)
                        .accessibilityAddTraits(.isHeader)
                    Text("In zwei Schritten bist du startklar.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Theme.Spacing.xl)

                if pendingInvitations > 0 {
                    CardContainer {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Label(pendingInvitations == 1 ? "Du hast eine Einladung" : "Du hast \(pendingInvitations) Einladungen",
                                  systemImage: "envelope.badge")
                                .font(.headline)
                                .foregroundStyle(Theme.brandDeep)
                            Text("Jemand hat ein Fahrzeug mit dir geteilt. Nimm die Einladung an, dann erscheint es hier, ohne dass du ein eigenes anlegen musst.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Einladungen ansehen", action: onShowInvitations)
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    step(number: 1, title: "Fahrzeug anlegen",
                         text: "Name und Antriebsart genügen, alles Weitere kannst du später ergänzen.", isCurrent: true)
                    step(number: 2, title: "Ersten Eintrag erfassen",
                         text: "Eine Tankfüllung, ein Ladevorgang oder eine Ausgabe. Nach den ersten vollen Tankfüllungen zeigt Fuelstat deinen Verbrauch.",
                         isCurrent: false)
                }

                VStack(spacing: Theme.Spacing.xs) {
                    PrimaryButton(title: "Fahrzeug anlegen", systemImage: "car.side") { showingAddVehicle = true }
                    Button("Später", action: onSkip)
                        .font(.subheadline)
                        .foregroundStyle(Theme.brand)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingAddVehicle) {
            RemoteVehicleFormView(store: store)
        }
    }

    private func step(number: Int, title: LocalizedStringKey, text: LocalizedStringKey, isCurrent: Bool) -> some View {
        CardContainer {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Text(verbatim: String(number))
                    .font(.headline)
                    .foregroundStyle(isCurrent ? Theme.onBrand : Theme.brandDeep)
                    .frame(width: Theme.iconCircle, height: Theme.iconCircle)
                    .background(isCurrent ? Theme.brand : Theme.cardTint, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title).font(.headline).foregroundStyle(Theme.brandDeep)
                    Text(text).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// On Start for a vehicle without any entry: the second onboarding step.
struct FirstEntryCard: View {
    let vehicleName: String
    var onAdd: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Ersten Eintrag erfassen")
                    .font(.headline)
                    .foregroundStyle(Theme.brandDeep)
                    .accessibilityAddTraits(.isHeader)
                Text("Erfasse eine Tankfüllung, einen Ladevorgang oder eine Ausgabe für \(vehicleName), um Verbrauch und Kosten zu sehen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                PrimaryButton(title: "Eintrag erfassen", systemImage: "plus", action: onAdd)
            }
        }
    }
}

/// Remembers per account that the first-start steps were skipped.
enum OnboardingState {
    private static func key(_ userID: String) -> String { "onboarding.skipped.\(userID)" }

    static func isSkipped(userID: String?) -> Bool {
        guard let userID else { return false }
        return UserDefaults.standard.bool(forKey: key(userID))
    }

    static func skip(userID: String?) {
        guard let userID else { return }
        UserDefaults.standard.set(true, forKey: key(userID))
    }
}
