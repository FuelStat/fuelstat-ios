import FuelstatCore
import SwiftUI

/// Expense categories: the fixed ones of the server and the user's own. Own categories can be added, changed and
/// deleted; whether the plan allows them, and how many, is decided by the API.
struct CategoriesView: View {
    let store: VehicleStore

    @State private var response: CategoriesResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var editor: EditorTarget?
    @State private var deleting: RemoteCategory?
    /// The API refused to delete a category that is still used: ask where its expenses should go.
    @State private var moving: RemoteCategory?

    private enum EditorTarget: Identifiable {
        case new
        case edit(RemoteCategory)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let category): category.key
            }
        }
    }

    private var own: [RemoteCategory] { (response?.categories ?? []).filter { $0.isCustom && !$0.isShared } }
    private var builtIn: [RemoteCategory] {
        (response?.categories ?? []).filter { !$0.isCustom && $0.form == "expense" && $0.isSelectable }
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    FormMessage(text: errorMessage)
                }
                .listRowBackground(Theme.card)
            }

            Section {
                ForEach(own) { category in
                    Button { editor = .edit(category) } label: {
                        CategoryRow(category: category)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Löschen", systemImage: "trash", role: .destructive) { deleting = category }
                    }
                }
                if let rules = response?.custom {
                    Button("Eigene Kategorie anlegen", systemImage: "plus") { editor = .new }
                        .foregroundStyle(Theme.brand)
                    if rules.max > 0 {
                        Text("\(rules.used) von \(rules.max) eigenen Kategorien genutzt.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Eigene Kategorien")
            } footer: {
                if response?.custom?.max == 0 {
                    Text("Eigene Kategorien gehören zum Tarif Plus.")
                }
            }
            .listRowBackground(Theme.card)

            Section("Feste Kategorien") {
                ForEach(builtIn) { category in
                    CategoryRow(category: category, locked: !category.isAvailable)
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedBackground()
        .overlay { if isLoading, response == nil { ProgressView() } }
        .navigationTitle("Kategorien")
        .refreshable { await load(reload: true) }
        .task { await load(reload: true) }
        .sheet(item: $editor, onDismiss: { response = store.categories ?? response }) { target in
            if let rules = response?.custom {
                switch target {
                case .new:
                    CategoryEditorView(store: store, rules: rules, groups: response?.groups ?? [], editing: nil)
                case .edit(let category):
                    CategoryEditorView(store: store, rules: rules, groups: response?.groups ?? [], editing: category)
                }
            }
        }
        .confirmationDialog("Kategorie löschen?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible, presenting: deleting) { category in
            Button("„\(category.name)“ löschen", role: .destructive) { delete(category, moveTo: nil) }
        }
        .confirmationDialog("Ausgaben verschieben nach", isPresented: Binding(
            get: { moving != nil }, set: { if !$0 { moving = nil } }
        ), titleVisibility: .visible, presenting: moving) { category in
            ForEach((own + builtIn).filter { $0.key != category.key && $0.isAvailable }.prefix(12)) { target in
                Button(target.name) { delete(category, moveTo: target.key) }
            }
        } message: { category in
            Text("„\(category.name)“ wird noch verwendet. Wähle die Kategorie, die ihre Ausgaben übernimmt.")
        }
    }

    private func load(reload: Bool) async {
        defer { isLoading = false }
        do {
            response = try await store.loadCategories(reload: reload)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ category: RemoteCategory, moveTo: String?) {
        guard let id = category.customID else { return }
        errorMessage = nil
        Task {
            do {
                try await store.deleteCategory(id, moveTo: moveTo)
                response = store.categories
            } catch APIError.server(code: "category_in_use", _) where moveTo == nil {
                moving = category
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct CategoryRow: View {
    let category: RemoteCategory
    var locked = false

    @ScaledMetric(relativeTo: .body) private var circle = Theme.iconCircle

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: category.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(category.tint)
                .frame(width: circle, height: circle)
                .background(Theme.cardTint, in: .circle)
            Text(verbatim: category.name)
            Spacer()
            if locked {
                Label("mit Plus", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Name, symbol, colour and group of an own category. Symbols and colours are the ones the API allows.
private struct CategoryEditorView: View {
    let store: VehicleStore
    let rules: CategoriesResponse.CustomRules
    let groups: [CategoriesResponse.Group]
    let editing: RemoteCategory?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var color: String
    @State private var group: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Bool?

    init(store: VehicleStore, rules: CategoriesResponse.CustomRules, groups: [CategoriesResponse.Group],
         editing: RemoteCategory?) {
        self.store = store
        self.rules = rules
        self.groups = groups
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _icon = State(initialValue: editing?.icon ?? rules.icons.first ?? "fa-tag")
        _color = State(initialValue: editing?.color ?? rules.colors.first ?? "#0d6efd")
        _group = State(initialValue: editing?.group ?? "sonstiges")
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    LabeledTextField(title: "Name", text: $name, focus: $focusedField, field: true)
                        .onChange(of: name) { name = String(name.prefix(rules.nameMaxLength)) }

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Symbol")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: Theme.Spacing.xs)],
                                  spacing: Theme.Spacing.xs) {
                            ForEach(rules.icons, id: \.self) { candidate in
                                Button {
                                    icon = candidate
                                    Haptics.selection()
                                } label: {
                                    Image(systemName: CategoryStyle.symbol(forIcon: candidate))
                                        .font(.body.weight(.semibold))
                                        .frame(width: 48, height: 48)
                                        .foregroundStyle(icon == candidate ? Theme.onBrand : Theme.brandDeep)
                                        .background(icon == candidate ? Theme.brand : Theme.card, in: .tile)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: candidate.replacingOccurrences(of: "fa-", with: "")))
                                .accessibilityAddTraits(icon == candidate ? [.isSelected] : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Farbe")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: Theme.Spacing.xs)],
                                  spacing: Theme.Spacing.xs) {
                            ForEach(Array(rules.colors.enumerated()), id: \.element) { index, candidate in
                                Button {
                                    color = candidate
                                    Haptics.selection()
                                } label: {
                                    Circle()
                                        .fill(Color(apiHex: candidate) ?? Theme.brand)
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            // Selection is shown by a check mark, not by colour alone.
                                            if color.caseInsensitiveCompare(candidate) == .orderedSame {
                                                Image(systemName: "checkmark")
                                                    .font(.footnote.bold())
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .frame(width: 48, height: 48)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Farbe \(index + 1)"))
                                .accessibilityAddTraits(color.caseInsensitiveCompare(candidate) == .orderedSame
                                    ? [.isSelected] : [])
                            }
                        }
                    }

                    if !groups.isEmpty {
                        CardContainer(padding: Theme.Spacing.s) {
                            Picker("Gruppe in der Auswertung", selection: $group) {
                                ForEach(groups) { Text(verbatim: $0.name).tag($0.key) }
                            }
                            .tint(Theme.brand)
                        }
                    }

                    if let errorMessage { FormMessage(text: errorMessage) }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.m)
            }
            .entryFormChrome(title: editing == nil ? "Neue Kategorie" : "Kategorie bearbeiten", isSaving: isSaving,
                             canSave: canSave, onDone: { focusedField = nil }, onCancel: { dismiss() }, onSave: save)
        }
    }

    private func save() {
        focusedField = nil
        errorMessage = nil
        isSaving = true
        let input = CategoryInput(name: name.trimmingCharacters(in: .whitespaces), icon: icon, color: color,
                                  group: group)
        Task {
            defer { isSaving = false }
            do {
                try await store.saveCategory(input, id: editing?.customID)
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
