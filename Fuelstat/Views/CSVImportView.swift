import FuelstatCore
import SwiftUI
import UniformTypeIdentifiers

/// Fahrzeug → Daten → CSV importieren (FuelStat/fuelstat-ios#38, like `import.php` of the web app): choose a file,
/// assign its columns, check the rows against the API (duplicates, odometer readings) and import. Reading and
/// converting the file is `CSVImport` in FuelstatCore; duplicates and validation are the API's.
@MainActor
@Observable
final class CSVImportModel {
    enum Stage { case pick, map, check, done }

    /// What the API said about a row in the check.
    struct Hint {
        enum Kind { case duplicate, warning, rejected }
        let kind: Kind
        let text: String
    }

    let store: VehicleStore
    let vehicle: RemoteVehicle

    private(set) var stage = Stage.pick
    var errorMessage: String?
    private(set) var fileName = ""
    private(set) var table = CSVTable(header: [], rows: [])
    private(set) var mapping: [ImportField: Int] = [:]
    private(set) var defaultCategory = "Werkstatt"
    private(set) var plan = ImportPlan()
    var skipErrors = false

    private(set) var categoryChoices: [RemoteCategory] = []
    private var categories: [ImportCategory] = []
    private var fuels: [ImportFuel] = []

    private(set) var isChecking = false
    private(set) var checkFailed = false
    private(set) var hints: [Int: Hint] = [:]

    private(set) var isImporting = false
    private(set) var imported = ImportResponse.Count()
    private(set) var skipped = ImportResponse.Count()
    private(set) var failure: String?

    init(store: VehicleStore, vehicle: RemoteVehicle) {
        self.store = store
        self.vehicle = vehicle
    }

    // MARK: File

    /// Reads the chosen file right away: the address from the picker is only valid while it is open.
    func open(_ result: Result<URL, Error>) async {
        errorMessage = nil
        let url: URL
        do { url = try result.get() } catch {
            errorMessage = error.localizedDescription
            return
        }
        let data: Data
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > CSVImport.maxFileBytes {
                errorMessage = String(localized: "Die Datei ist größer als 5 MB.")
                return
            }
            data = try Data(contentsOf: url)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard data.count <= CSVImport.maxFileBytes else {
            errorMessage = String(localized: "Die Datei ist größer als 5 MB.")
            return
        }
        let table = CSVTable.read(data)
        if table.header.isEmpty || table.rows.isEmpty {
            errorMessage = String(localized: "Die Datei enthält keine Datenzeilen. Erwartet wird eine Kopfzeile und darunter die Einträge.")
            return
        }
        if table.rows.count > CSVImport.maxRows {
            errorMessage = String(localized: "Maximal 10.000 Zeilen pro Import.")
            return
        }
        guard await loadCatalogs() else { return }
        self.table = table
        fileName = url.lastPathComponent
        mapping = CSVImport.detectMapping(header: table.header)
        rebuild()
        stage = .map
    }

    /// Categories and fuel grades of the API, needed to file the rows; without them nothing is imported.
    private func loadCatalogs() async -> Bool {
        do {
            let response = try await store.loadCategories()
            _ = await store.loadFuelCatalog()
            categories = response.categories.map {
                ImportCategory(key: $0.key, name: $0.name, form: $0.form, isLegacy: $0.isLegacy,
                               isAvailable: $0.isAvailable)
            }
            categoryChoices = response.categories.filter {
                $0.form == "expense" && $0.isSelectable && $0.isAvailable && !$0.isLegacy && !$0.isShared
            }
            fuels = (store.fuelCatalog?.fuels ?? []).map { ImportFuel(key: $0.key, name: $0.name) }
            if !categoryChoices.contains(where: { $0.key == defaultCategory }), let first = categoryChoices.first {
                defaultCategory = first.key
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func backToMapping() {
        stage = .map
        hints = [:]
        errorMessage = nil
    }

    func restart() {
        stage = .pick
        table = CSVTable(header: [], rows: [])
        plan = ImportPlan()
        hints = [:]
        errorMessage = nil
    }

    // MARK: Mapping

    func setColumn(_ column: Int?, for field: ImportField) {
        mapping[field] = column
        rebuild()
    }

    func setDefaultCategory(_ key: String) {
        defaultCategory = key
        rebuild()
    }

    private func rebuild() {
        plan = CSVImport.plan(rows: table.rows, mapping: mapping, defaultCategory: defaultCategory, fuels: fuels,
                              categories: categories)
    }

    var canContinue: Bool { mapping[.date] != nil && !plan.isEmpty }

    var errorCount: Int { plan.errors.count }

    /// Rows of the file that will not be sent: errors of the file and rows the API rejected in the check.
    private var rejectedLines: Set<Int> {
        Set(hints.filter { $0.value.kind == .rejected }.keys)
    }

    /// What `runImport` sends: without rows the API rejected.
    var toImport: ImportPlan { plan.excluding(lines: rejectedLines) }

    /// Rows that stop the import unless "skip faulty rows" is on.
    var blockingCount: Int { errorCount + rejectedLines.count }

    var canImport: Bool {
        !isChecking && !checkFailed && !toImport.isEmpty && (blockingCount == 0 || skipErrors)
    }

    // MARK: Check and import

    /// Asks the API what would happen: duplicates, implausible odometer readings and rows it rejects.
    func check() async {
        stage = .check
        isChecking = true
        checkFailed = false
        errorMessage = nil
        hints = [:]
        skipErrors = false
        defer { isChecking = false }
        do {
            for chunk in plan.fillupChunks {
                try await check(chunk.items, lines: plan.fillupLines, offset: chunk.offset) { items in
                    try await self.store.importRows(into: self.vehicle.id, fillups: items, entries: [], dryRun: true)
                }
            }
            for chunk in plan.entryChunks {
                try await check(chunk.items, lines: plan.entryLines, offset: chunk.offset) { items in
                    try await self.store.importRows(into: self.vehicle.id, fillups: [], entries: items, dryRun: true)
                }
            }
        } catch is CancellationError {
            checkFailed = true
        } catch {
            checkFailed = true
            errorMessage = error.localizedDescription
        }
    }

    /// Checks one package. The API names at most 50 rejected rows per answer, so the package is checked again
    /// without the rows named so far, until nothing is rejected any more.
    private func check<Item>(_ items: [Item], lines: [Int], offset: Int,
                             send: ([Item]) async throws -> ImportResponse) async throws {
        var remaining = Array(items.indices)
        for _ in 0..<40 {
            let sending = remaining.map { items[$0] }
            do {
                let answer = try await send(sending)
                for duplicate in answer.duplicates where remaining.indices.contains(duplicate.index) {
                    hints[lines[offset + remaining[duplicate.index]]] = Hint(
                        kind: .duplicate, text: String(localized: "Bereits vorhanden, wird übersprungen"))
                }
                for warning in answer.warnings where remaining.indices.contains(warning.index) {
                    let line = lines[offset + remaining[warning.index]]
                    guard hints[line] == nil else { continue }
                    hints[line] = Hint(kind: .warning,
                                       text: String(localized: "Tachostand prüfen: \(warning.message ?? "")"))
                }
                return
            } catch APIError.invalidRows(let rows) {
                let bad = Set(rows.filter { remaining.indices.contains($0.index) }.map(\.index))
                guard !bad.isEmpty else { throw APIError.invalidRows(rows) }
                for row in rows where remaining.indices.contains(row.index) {
                    hints[lines[offset + remaining[row.index]]] = Hint(
                        kind: .rejected,
                        text: APIError.server(code: row.error, status: 400).errorDescription ?? row.error)
                }
                remaining = remaining.indices.filter { !bad.contains($0) }.map { remaining[$0] }
                if remaining.isEmpty { return }
            }
        }
    }

    /// Sends the rows in packages of 500, fill-ups first. Each package is saved on its own, so after an error the
    /// result says what already went in.
    func runImport() async {
        isImporting = true
        errorMessage = nil
        failure = nil
        imported = .init()
        skipped = .init()
        defer { isImporting = false }
        let rows = toImport
        var current: (lines: [Int], offset: Int) = ([], 0)
        do {
            for chunk in rows.fillupChunks {
                current = (rows.fillupLines, chunk.offset)
                add(try await store.importRows(into: vehicle.id, fillups: chunk.items, entries: [], dryRun: false))
            }
            for chunk in rows.entryChunks {
                current = (rows.entryLines, chunk.offset)
                add(try await store.importRows(into: vehicle.id, fillups: [], entries: chunk.items, dryRun: false))
            }
        } catch is CancellationError {
            failure = String(localized: "Der Import wurde abgebrochen.")
        } catch APIError.invalidRows(let issues) {
            let lines = issues.prefix(5).compactMap { issue in
                current.lines.indices.contains(current.offset + issue.index)
                    ? String(localized: "Zeile \(current.lines[current.offset + issue.index])") : nil
            }
            failure = String(localized: "Der Server hat Zeilen abgelehnt (\(lines.joined(separator: ", "))). Dieses Paket wurde nicht importiert.")
        } catch {
            failure = error.localizedDescription
        }
        stage = .done
    }

    private func add(_ answer: ImportResponse) {
        imported = .init(fillups: imported.fillups + answer.imported.fillups,
                         entries: imported.entries + answer.imported.entries)
        skipped = .init(fillups: skipped.fillups + answer.skipped.fillups,
                        entries: skipped.entries + answer.skipped.entries)
    }

    /// Rows that did not go in because an earlier package failed.
    var notSent: Int {
        let rows = toImport
        return max(0, rows.fillups.count + rows.entries.count
                   - imported.fillups - imported.entries - skipped.fillups - skipped.entries)
    }
}

// MARK: - View

struct CSVImportView: View {
    let store: VehicleStore
    let vehicle: RemoteVehicle

    @Environment(\.dismiss) private var dismiss
    @State private var model: CSVImportModel
    @State private var showingPicker = false
    @State private var template: ExportedFile?

    init(store: VehicleStore, vehicle: RemoteVehicle) {
        self.store = store
        self.vehicle = vehicle
        _model = State(initialValue: CSVImportModel(store: store, vehicle: vehicle))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .pick: pickStage
                case .map: mapStage
                case .check: checkStage
                case .done: doneStage
                }
            }
            .themedBackground()
            .navigationTitle("CSV importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.stage == .done ? "Fertig" : "Abbrechen") { dismiss() }
                        .disabled(model.isImporting)
                }
            }
            .fileImporter(isPresented: $showingPicker,
                          allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { result in
                Task { await model.open(result) }
            }
            .sheet(item: $template) { file in
                ShareSheet(items: [file.url])
            }
        }
        .interactiveDismissDisabled(model.isImporting)
    }

    // MARK: Pick

    private var pickStage: some View {
        Form {
            Section {
                Text("Importiere Tank- und Ladevorgänge und Ausgaben aus einer CSV-Datei, zum Beispiel aus einer anderen App oder einer Tabelle. Das Format ist dasselbe wie beim Export.")
                Button("CSV-Datei auswählen", systemImage: "doc.badge.plus") { showingPicker = true }
                Button("Vorlage für \(vehicle.fuelType.label) teilen", systemImage: "square.and.arrow.up", action: shareTemplate)
            } footer: {
                Text("Höchstens 5 MB und 10.000 Zeilen. Zeilen, die es schon gibt (gleiches Datum und gleicher Tachostand bzw. gleiche Kategorie und gleicher Betrag), überspringt der Server.")
            }
            .listRowBackground(Theme.card)
            ErrorSection(message: model.errorMessage)
        }
    }

    private func shareTemplate() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(CSVImport.templateFileName)
        do {
            try CSVImport.template(fuelType: vehicle.fuelType.rawValue).write(to: url, options: .atomic)
            template = ExportedFile(url: url)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    // MARK: Map

    private var mapStage: some View {
        Form {
            Section("Datei") {
                LabeledContent("Name", value: model.fileName)
                LabeledContent("Zeilen", value: String(model.table.rows.count))
                Button("Andere Datei wählen", systemImage: "arrow.uturn.backward") { model.restart() }
            }
            .listRowBackground(Theme.card)

            Section {
                ForEach(visibleFields, id: \.self) { field in
                    Picker(field.title, selection: Binding(
                        get: { model.mapping[field] }, set: { model.setColumn($0, for: field) }
                    )) {
                        Text("Nicht importieren").tag(Int?.none)
                        ForEach(model.table.header.indices, id: \.self) { index in
                            Text(columnName(index)).tag(Int?.some(index))
                        }
                    }
                }
            } header: {
                Text("Spalten zuordnen")
            } footer: {
                Text("Die Zuordnung ist aus den Überschriften geraten. Das Datum ist Pflicht. Ohne „Art“ gilt eine Zeile mit Menge als Tank- bzw. Ladevorgang, alle anderen als Ausgabe.")
            }
            .listRowBackground(Theme.card)

            if !model.categoryChoices.isEmpty {
                Section {
                    Picker("Kategorie ohne Angabe", selection: Binding(
                        get: { model.defaultCategory }, set: { model.setDefaultCategory($0) }
                    )) {
                        ForEach(model.categoryChoices) { Text(verbatim: $0.name).tag($0.key) }
                    }
                } footer: {
                    Text("Für Ausgaben, bei denen die Datei keine Art nennt. Unbekannte Kategorien landen unter „Sonstiges“, ihr Name bleibt in der Beschreibung.")
                }
                .listRowBackground(Theme.card)
            }

            Section("Ergebnis") {
                LabeledContent("Tank- und Ladevorgänge", value: String(model.plan.fillups.count))
                LabeledContent("Ausgaben", value: String(model.plan.entries.count))
                if model.errorCount > 0 {
                    LabeledContent("Fehlerhafte Zeilen", value: String(model.errorCount))
                        .foregroundStyle(Theme.Status.overdue)
                }
                ForEach(model.plan.otherCategories.sorted { $0.key < $1.key }, id: \.key) { name, count in
                    Label("\(count) × „\(name)“ landet unter Sonstiges", systemImage: "questionmark.folder")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Theme.card)

            Section("Vorschau") {
                ForEach(model.plan.preview.prefix(8)) { row in
                    PreviewRowView(row: row, hint: nil)
                }
            }
            .listRowBackground(Theme.card)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Weiter zur Prüfung", systemImage: "checkmark.shield") {
                Task { await model.check() }
            }
            .disabled(!model.canContinue)
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.xs)
            .background(.bar)
        }
    }

    /// The fields that fit the vehicle; a field the file already fills stays visible.
    private var visibleFields: [ImportField] {
        let charges = ["electric", "phev"].contains(vehicle.fuelType.rawValue)
        return ImportField.allCases.filter { field in
            if model.mapping[field] != nil { return true }
            switch field {
            case .chargeType, .socBefore, .socAfter, .chargeMinutes: return charges
            case .unit: return vehicle.fuelType.rawValue == "phev"
            case .fuel: return vehicle.fuels.count > 1
            default: return true
            }
        }
    }

    private func columnName(_ index: Int) -> String {
        let name = model.table.header[index]
        return name.isEmpty ? String(localized: "Spalte \(index + 1)") : "\(index + 1): \(name)"
    }

    // MARK: Check

    private var checkStage: some View {
        List {
            Section {
                if model.isChecking {
                    HStack(spacing: Theme.Spacing.xs) {
                        ProgressView()
                        Text("Der Server prüft die Zeilen …").foregroundStyle(.secondary)
                    }
                } else if model.checkFailed {
                    if let message = model.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.Status.overdue)
                    }
                    Button("Erneut prüfen") { Task { await model.check() } }
                } else {
                    summary
                    if model.blockingCount > 0 {
                        Toggle("Fehlerhafte Zeilen überspringen", isOn: Bindable(model).skipErrors).tint(Theme.brand)
                    }
                }
            } footer: {
                if !model.isChecking, !model.checkFailed, model.blockingCount > 0 {
                    Text("Einige Zeilen sind fehlerhaft. Korrigiere die Datei oder überspringe diese Zeilen.")
                }
            }
            .listRowBackground(Theme.card)

            if !model.isChecking, !model.checkFailed {
                Section("Zeilen") {
                    ForEach(model.plan.preview) { row in
                        PreviewRowView(row: row, hint: model.hints[row.number])
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Spacing.xs) {
                PrimaryButton(title: "Importieren", systemImage: "square.and.arrow.down",
                              isLoading: model.isImporting) {
                    Task { await model.runImport() }
                }
                .disabled(!model.canImport)
                Button("Zurück zur Zuordnung") { model.backToMapping() }
                    .disabled(model.isImporting || model.isChecking)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.xs)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var summary: some View {
        let duplicates = model.hints.values.filter { $0.kind == .duplicate }.count
        let rows = model.toImport
        LabeledContent("Werden importiert", value: String(max(0, rows.fillups.count + rows.entries.count - duplicates)))
        if duplicates > 0 {
            LabeledContent("Schon vorhanden", value: String(duplicates))
        }
        if model.blockingCount > 0 {
            LabeledContent("Fehlerhaft", value: String(model.blockingCount)).foregroundStyle(Theme.Status.overdue)
        }
    }

    // MARK: Done

    private var doneStage: some View {
        Form {
            Section {
                if model.failure == nil {
                    Label("Import abgeschlossen", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.Status.ok)
                } else {
                    Label("Import unvollständig", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.Status.overdue)
                }
                LabeledContent("Tank- und Ladevorgänge importiert", value: String(model.imported.fillups))
                LabeledContent("Ausgaben importiert", value: String(model.imported.entries))
                let skipped = model.skipped.fillups + model.skipped.entries
                if skipped > 0 {
                    LabeledContent("Übersprungen (schon vorhanden)", value: String(skipped))
                }
            }
            .listRowBackground(Theme.card)

            if let failure = model.failure {
                Section {
                    Text(verbatim: failure).foregroundStyle(Theme.Status.overdue)
                    if model.notSent > 0 {
                        Text("\(model.notSent) Zeilen wurden nicht importiert. Die bereits importierten Zeilen bleiben gespeichert. Ein erneuter Import überspringt sie als Duplikate.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Fehler")
                }
                .listRowBackground(Theme.card)
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Fertig", action: { dismiss() })
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.xs)
                .background(.bar)
        }
    }
}

// MARK: - Rows

private struct PreviewRowView: View {
    let row: ImportPreviewRow
    let hint: CSVImportModel.Hint?

    private var date: String {
        row.date.flatMap(APIDate.parseDay).map { APIDate.formatDay($0) } ?? String(localized: "Kein Datum")
    }

    private var details: String {
        var parts: [String] = []
        if let km = row.odometerKm { parts.append(Fmt.kilometres(Double(km))) }
        if row.isFillup, let amount = row.amount {
            parts.append("\(Fmt.number(amount, digits: 2)) \(row.unit ?? "")".trimmingCharacters(in: .whitespaces))
        }
        if !row.place.isEmpty { parts.append(row.place) }
        return parts.joined(separator: " · ")
    }

    private var problem: (text: String, color: Color)? {
        if let error = row.error {
            return (error.message, Theme.Status.overdue)
        }
        guard let hint else { return nil }
        switch hint.kind {
        case .duplicate: return (hint.text, .secondary)
        case .warning: return (hint.text, Theme.Status.soon)
        case .rejected: return (hint.text, Theme.Status.overdue)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(row.number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityHidden(true)
                Text(verbatim: date).font(.subheadline.weight(.semibold))
                Text(verbatim: row.categoryText).font(.subheadline)
                Spacer()
                if let cost = row.cost { Text(verbatim: Fmt.currency(cost)).font(.subheadline).monospacedDigit() }
            }
            if !details.isEmpty {
                Text(verbatim: details).font(.footnote).foregroundStyle(.secondary)
            }
            if let problem {
                Text(verbatim: problem.text).font(.footnote).foregroundStyle(problem.color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Zeile \(row.number)"))
        .accessibilityValue(Text(verbatim: [date, row.categoryText, details, problem?.text ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ", ")))
    }
}

private extension ImportRowError {
    var message: String {
        switch self {
        case .dateInvalid: String(localized: "Datum fehlt oder ist ungültig")
        case .amountMissing: String(localized: "Tank-/Ladevorgang ohne gültige Menge")
        case .costInvalid: String(localized: "Kosten fehlen oder sind ungültig")
        }
    }
}

private extension ImportField {
    var title: LocalizedStringKey {
        switch self {
        case .date: "Datum *"
        case .kind: "Art / Kategorie"
        case .odometer: "Tachostand (km)"
        case .amount: "Menge (l, kWh, kg)"
        case .unit: "Einheit (l oder kWh)"
        case .fuel: "Sorte"
        case .cost: "Kosten gesamt (€)"
        case .pricePerUnit: "Preis pro Einheit (€)"
        case .full: "Voll getankt bzw. geladen"
        case .gapBefore: "Lücke davor"
        case .chargeType: "Ladeart"
        case .socBefore: "Ladestand vorher (%)"
        case .socAfter: "Ladestand nachher (%)"
        case .chargeMinutes: "Ladedauer (Minuten)"
        case .place: "Tankstelle / Ort"
        case .note: "Beschreibung / Notiz"
        }
    }
}
