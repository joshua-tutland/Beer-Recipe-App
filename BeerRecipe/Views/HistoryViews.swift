import SwiftUI
import BrewCore

/// Saved versions of a recipe, what changed between them, and restore.
struct VersionHistoryView: View {
    @Binding var recipe: Recipe
    let units: UnitSystem

    @Environment(\.dismiss) private var dismiss
    @State private var restoring: RecipeVersion?

    var body: some View {
        List {
            Section {
                let current = RecipeDiff.changes(from: recipe.versions.first?.recipe ?? recipe, to: recipe, units: units)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current recipe").font(.headline)
                    if recipe.versions.isEmpty {
                        Text("No versions saved yet. One is saved each time you start a brew day.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if current.isEmpty {
                        Text("Same as the latest version.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(current, id: \.self) { Text("• \($0)").font(.caption) }
                    }
                }
            }
            ForEach(Array(recipe.versions.indices), id: \.self) { index in
                let version = recipe.versions[index]
                Section {
                    let previous = index + 1 < recipe.versions.count ? recipe.versions[index + 1].recipe : nil
                    let changes = previous.map { RecipeDiff.changes(from: $0, to: version.recipe, units: units) } ?? []
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(version.note).font(.headline)
                            Spacer()
                            Text(version.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        let s = version.recipe.stats
                        Text("OG \(UnitSystem.gravity(s.og)) · \(s.abv, specifier: "%.1f")% · \(s.ibu, specifier: "%.0f") IBU · \(s.srm, specifier: "%.1f") SRM")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if previous == nil {
                            Text("First saved version").font(.caption).foregroundStyle(.secondary)
                        } else if changes.isEmpty {
                            Text("No ingredient changes").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(changes, id: \.self) { Text("• \($0)").font(.caption) }
                        }
                    }
                    Button("Restore This Version", systemImage: "arrow.uturn.backward") { restoring = version }
                }
            }
            .onDelete { offsets in recipe.versions.remove(atOffsets: offsets) }
        }
        .navigationTitle("Version History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .confirmationDialog("Restore “\(restoring?.note ?? "")”?",
                            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                            titleVisibility: .visible) {
            Button("Restore") {
                if let version = restoring { recipe.restore(version) }
                restoring = nil
            }
        } message: {
            Text("The current recipe is saved as a version first, so you can switch back. Brew logs are kept.")
        }
    }
}

/// Every brew of a recipe side by side: measured against predicted.
struct BrewComparisonView: View {
    let recipe: Recipe
    let units: UnitSystem
    @Environment(\.dismiss) private var dismiss

    private var sessions: [BrewSession] { recipe.sessions.sorted { $0.brewDate < $1.brewDate } }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("")
                    ForEach(sessions) { s in
                        VStack(alignment: .leading) {
                            Text(s.name).font(.headline)
                            Text(s.brewDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                row("OG") { s in pair(s.og.map(UnitSystem.gravity), UnitSystem.gravity(s.plan.og)) }
                row("FG") { s in pair(s.currentGravity.map(UnitSystem.gravity), UnitSystem.gravity(s.plan.fg)) }
                row("ABV") { s in pair(s.results.abv.map { String(format: "%.1f%%", $0) }, nil) }
                row("Attenuation") { s in pair(s.results.apparentAttenuation.map { String(format: "%.0f%%", $0) }, nil) }
                row("Efficiency") { s in
                    pair(s.results.brewhouseEfficiency.map { String(format: "%.0f%%", $0) }, String(format: "%.0f%%", s.plan.efficiency))
                }
                row("Into Fermenter") { s in
                    pair(s.fermenterVolumeL.map { units.formatVolume(liters: $0) }, units.formatVolume(liters: s.plan.batchSizeL))
                }
                row("Boil-off") { s in pair(s.results.boilOffLPerHour.map { "\(units.formatVolume(liters: $0))/hr" }, nil) }
                row("Mash pH") { s in pair(s.mashPH.map { String(format: "%.2f", $0) }, nil) }
                row("Score") { s in
                    pair(s.scoresheet.map { "\($0.total)/50 \($0.rating)" }, nil)
                }
                row("Rating") { s in pair(s.rating > 0 ? String(repeating: "★", count: s.rating) : nil, nil) }
            }
            .padding()
        }
        .navigationTitle("Compare Brews")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private func row(_ label: String, _ value: @escaping (BrewSession) -> AnyView) -> some View {
        GridRow {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            ForEach(sessions) { value($0) }
        }
    }

    /// Measured value, with the plan underneath when there is one.
    private func pair(_ measured: String?, _ planned: String?) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 1) {
                Text(measured ?? "–").monospacedDigit()
                if let planned {
                    Text("plan \(planned)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        )
    }
}

/// BJCP-style 50-point scoresheet for one brew.
struct ScoresheetView: View {
    @Binding var session: BrewSession

    private var sheet: Binding<TastingScoresheet> {
        Binding(get: { session.scoresheet ?? TastingScoresheet() }, set: { session.scoresheet = $0 })
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Tasted", selection: sheet.tastedOn, displayedComponents: .date)
                HStack {
                    Text("Total")
                    Spacer()
                    Text("\(sheet.wrappedValue.total) / 50 · \(sheet.wrappedValue.rating)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.brewAmber)
                }
            }
            ForEach(TastingScoresheet.Category.allCases) { category in
                Section {
                    Stepper(value: Binding(get: { sheet.wrappedValue.scores[category] ?? 0 },
                                           set: { sheet.wrappedValue.scores[category] = $0 }),
                            in: 0...category.maximum) {
                        HStack {
                            Text(category.displayName)
                            Spacer()
                            Text("\(sheet.wrappedValue.scores[category] ?? 0) / \(category.maximum)").monospacedDigit()
                        }
                    }
                    TextField(category.prompt,
                              text: Binding(get: { sheet.wrappedValue.notes[category] ?? "" },
                                            set: { sheet.wrappedValue.notes[category] = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            Section {
                Text("45–50 Outstanding · 38–44 Excellent · 30–37 Very Good · 21–29 Good · 14–20 Fair · 0–13 Problematic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Scoresheet")
        .navigationBarTitleDisplayMode(.inline)
    }
}
