import FuelstatCore
import SwiftUI

/// Sold and decommissioned vehicles (FuelStat/fuelstat#79): the app shows what the API stored and offers to
/// archive or reactivate. Whether that is allowed, including the plan limits, is the API's decision.
extension RemoteVehicle {
    /// "Verkauft am 1. Nov. 2026 · 84.500 km · 12.500 €" or "Stillgelegt seit …, abgemeldet bis …".
    var archiveSummary: String? {
        func day(_ text: String?) -> String? {
            text.flatMap(APIDate.parseDay).map { APIDate.formatDay($0) }
        }
        switch status {
        case .active:
            return nil
        case .sold:
            var parts = [day(saleDate).map { String(localized: "Verkauft am \($0)") } ?? String(localized: "Verkauft")]
            if let saleOdometerKm { parts.append(Fmt.kilometres(saleOdometerKm)) }
            if let salePrice { parts.append(Fmt.currency(salePrice)) }
            return parts.joined(separator: " · ")
        case .decommissioned:
            var parts = [day(decommissionedFrom).map { String(localized: "Stillgelegt seit \($0)") }
                         ?? String(localized: "Stillgelegt")]
            if let until = day(decommissionedUntil) { parts.append(String(localized: "abgemeldet bis \(until)")) }
            return parts.joined(separator: " · ")
        }
    }

    var statusLabel: String? {
        switch status {
        case .active: nil
        case .sold: String(localized: "Verkauft")
        case .decommissioned: String(localized: "Stillgelegt")
        }
    }
}

/// On the page of an archived vehicle: what was stored, that it is read-only, and the owner's way back.
struct ArchiveBanner: View {
    let vehicle: RemoteVehicle
    let isWorking: Bool
    var onReactivate: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label(vehicle.archiveSummary ?? "", systemImage: "archivebox")
                    .font(.headline)
                    .foregroundStyle(Theme.brandDeep)
                Text("Alle Daten und Statistiken bleiben lesbar. Erfassen und Bearbeiten ist erst wieder möglich, wenn das Fahrzeug aktiv ist.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !vehicle.isShared {
                    Button("Wieder aktivieren", systemImage: "arrow.uturn.backward", action: onReactivate)
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isWorking)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// "Verkauft" or "Stillgelegt" with the details the web app asks for; every field except the status is optional and
/// the API fills a missing date with today.
struct VehicleStatusFormView: View {
    let store: VehicleStore
    let vehicle: RemoteVehicle

    @Environment(\.dismiss) private var dismiss

    private enum Kind: Hashable { case sold, decommissioned }

    @State private var kind: Kind = .sold
    @State private var soldOn = Date.now
    @State private var odometerKm: Double?
    @State private var price: Double?
    @State private var decommissionedFrom = Date.now
    @State private var hasUntil = false
    @State private var until = Date.now
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Status", selection: $kind) {
                        Text("Verkauft").tag(Kind.sold)
                        Text("Stillgelegt").tag(Kind.decommissioned)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Das Fahrzeug wandert ins Archiv. Alle Daten und Statistiken bleiben lesbar, Erinnerungen und der Monatsbericht entfallen. Du kannst es jederzeit wieder aktivieren.")
                }
                .listRowBackground(Theme.card)

                Section {
                    switch kind {
                    case .sold:
                        DatePicker("Verkauft am", selection: $soldOn, in: ...Date.now, displayedComponents: .date)
                        numberField("Kilometerstand", unit: "km", value: $odometerKm, integer: true)
                        numberField("Erlös", unit: "€", value: $price, integer: false)
                    case .decommissioned:
                        DatePicker("Stillgelegt seit", selection: $decommissionedFrom, displayedComponents: .date)
                        Toggle("Abgemeldet bis", isOn: $hasUntil).tint(Theme.brand)
                        if hasUntil {
                            DatePicker("Bis", selection: $until, in: decommissionedFrom..., displayedComponents: .date)
                        }
                    }
                } footer: {
                    if kind == .decommissioned {
                        Text("„Abgemeldet bis“ ist nur eine Angabe. Das Fahrzeug wird nicht von selbst wieder aktiv.")
                    } else {
                        Text("Den Erlös braucht die Auswertung der Gesamtkosten. Du kannst ihn später im Fahrzeug ergänzen.")
                    }
                }
                .listRowBackground(Theme.card)

                ErrorSection(message: errorMessage)
            }
            .themedBackground()
            .navigationTitle(vehicle.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Archivieren") { Task { await save() } }
                    }
                }
            }
        }
        .tint(Theme.brand)
    }

    private func numberField(_ title: LocalizedStringKey, unit: String, value: Binding<Double?>, integer: Bool)
        -> some View {
        LabeledContent(title) {
            HStack(spacing: Theme.Spacing.xxs) {
                TextField(title, value: value, format: .number)
                    .keyboardType(integer ? .numberPad : .decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(unit)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let change: VehicleStatusChange = switch kind {
        case .sold:
            .sold(date: Self.apiDate(soldOn), odometerKm: odometerKm.map { Int($0.rounded()) }, price: price)
        case .decommissioned:
            .decommissioned(from: Self.apiDate(decommissionedFrom), until: hasUntil ? Self.apiDate(until) : nil)
        }
        do {
            try await store.setStatus(vehicle.id, change)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func apiDate(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
