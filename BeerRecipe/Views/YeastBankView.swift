import SwiftUI
import BrewCore

/// Jars of saved yeast slurry, with their age, generation and estimated cell count.
struct YeastBankView: View {
    @Environment(RecipeStore.self) private var store
    @State private var editing: YeastHarvest?
    @State private var pickingYeast = false

    var body: some View {
        List {
            if store.yeastBank.isEmpty {
                ContentUnavailableView("No Saved Yeast", systemImage: "flask",
                                       description: Text("Harvest slurry from a finished batch in its brew log, or add a jar here."))
            }
            ForEach(store.yeastBank) { harvest in
                Button { editing = harvest } label: {
                    HarvestRow(harvest: harvest)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                store.deleteHarvests(ids: offsets.map { store.yeastBank[$0].id })
            }
        }
        .navigationTitle("Yeast Bank")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Jar", systemImage: "plus") { pickingYeast = true }
            }
        }
        .sheet(isPresented: $pickingYeast) {
            NavigationStack {
                YeastPickerView { yeast in
                    pickingYeast = false
                    editing = YeastHarvest(yeast: yeast, slurryML: 200)
                }
            }
        }
        .sheet(item: $editing) { harvest in
            NavigationStack {
                HarvestEditor(harvest: harvest) { store.saveHarvest($0) }
            }
        }
    }
}

struct HarvestRow: View {
    let harvest: YeastHarvest

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(harvest.yeast.displayName).font(.body.weight(.medium))
                if !harvest.source.isEmpty {
                    Text(harvest.source).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(Int(harvest.slurryML.rounded())) mL · \(Int(harvest.ageDays().rounded())) days old · \(Int((harvest.viability() * 100).rounded()))% viable")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                GenerationBadge(generation: harvest.generation)
                Text("\(Int(harvest.viableCells().rounded())) B cells")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct GenerationBadge: View {
    let generation: Int

    var body: some View {
        let old = generation > YeastHarvest.recommendedMaxGeneration
        Text("Gen \(generation)")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background((old ? Color.orange : Color.brewAmber).opacity(0.18), in: Capsule())
            .foregroundStyle(old ? Color.orange : Color.brewAmber)
    }
}

struct HarvestEditor: View {
    @State var harvest: YeastHarvest
    let onSave: (YeastHarvest) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                LabeledContent("Yeast", value: harvest.yeast.displayName)
                TextField("Source (e.g. Pale Ale · Batch 2)", text: $harvest.source)
                DatePicker("Harvested", selection: $harvest.harvestedOn, displayedComponents: .date)
                Stepper("Generation \(harvest.generation)", value: $harvest.generation, in: 1...50)
            } footer: {
                if harvest.isPastRecommendedGenerations {
                    Text("Past about \(YeastHarvest.recommendedMaxGeneration) generations, many brewers start again from fresh yeast: flavor can drift and contamination becomes more likely.")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                NumberField(label: "Slurry", value: $harvest.slurryML, unit: "mL", digits: 0)
                Picker("Consistency", selection: $harvest.consistency) {
                    ForEach(SlurryConsistency.allCases) { c in
                        Text("\(c.displayName): \(c.detail)").tag(c)
                    }
                }
                NumberField(label: "Trub & Dead Cells", value: $harvest.trubPercent, unit: "%", digits: 0)
            } header: {
                Text("Slurry")
            } footer: {
                Text("Measure the settled slurry only, not the beer above it. 25% trub is typical for slurry taken straight from a fermenter; less if it was rinsed.")
            }
            Section {
                ResultRow(label: "Viability", value: "\(Int((harvest.viability() * 100).rounded()))%")
                ResultRow(label: "Viable Cells", value: "\(Int(harvest.viableCells().rounded())) billion", emphasized: true)
                ResultRow(label: "Per mL", value: String(format: "%.2f billion", harvest.billionViableCellsPerML()))
            } header: {
                Text("Estimate Today")
            } footer: {
                Text("Estimates assume \(Int(YeastHarvest.initialViability * 100))% viability at harvest, falling about 0.7% a day in the fridge. Use within 2–3 weeks for best results, or make a starter for older slurry.")
            }
            Section("Notes") {
                TextField("Notes", text: $harvest.notes, axis: .vertical).lineLimit(2...6)
            }
        }
        .navigationTitle("Yeast Jar")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(harvest)
                    dismiss()
                }
                .disabled(harvest.slurryML <= 0)
            }
        }
    }
}

/// The brew log's yeast section: pitch from the yeast bank, and harvest after fermentation.
struct BrewSessionYeastSection: View {
    @Binding var session: BrewSession
    let recipe: Recipe

    @Environment(RecipeStore.self) private var store
    @State private var harvesting: YeastHarvest?
    @State private var confirmPitch: YeastHarvest?

    var body: some View {
        let needed = recipe.stats.yeastCellsNeededBillions
        let yeastID = recipe.yeasts.first?.yeast.id
        let matching = store.yeastBank.filter { $0.yeast.id == yeastID && $0.viability() > 0 }

        Section {
            if let generation = session.yeastGeneration {
                HStack {
                    Label("Pitched from saved slurry", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    GenerationBadge(generation: generation)
                }
                Button("Mark as Fresh Yeast", role: .destructive) {
                    session.pitchedHarvestID = nil
                    session.yeastGeneration = nil
                }
                .font(.caption)
            } else if session.og == nil {
                ForEach(matching) { harvest in
                    Button { confirmPitch = harvest } label: {
                        pitchRow(harvest, needed: needed)
                    }
                }
                if matching.isEmpty && !store.yeastBank.isEmpty {
                    Text("No saved slurry of \(recipe.yeasts.first?.yeast.displayName ?? "this yeast") in the yeast bank.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if session.og != nil, let yeast = recipe.yeasts.first?.yeast {
                Button("Harvest Yeast from This Batch", systemImage: "tray.and.arrow.down") {
                    harvesting = YeastHarvest.harvest(from: session, recipe: recipe, slurryML: 200)
                        ?? YeastHarvest(yeast: yeast, slurryML: 200)
                }
            }
        } header: {
            Text("Yeast")
        } footer: {
            Text(session.og == nil
                 ? "This batch needs about \(Int(needed.rounded())) billion cells. Pitch fresh yeast, or saved slurry from the yeast bank."
                 : "After fermentation, save the settled yeast in a clean jar in the fridge to pitch into a future batch.")
        }
        .sheet(item: $harvesting) { harvest in
            NavigationStack {
                HarvestEditor(harvest: harvest) { store.saveHarvest($0) }
            }
        }
        .confirmationDialog("Pitch saved slurry?", isPresented: Binding(get: { confirmPitch != nil },
                                                                     set: { if !$0 { confirmPitch = nil } }),
                            titleVisibility: .visible) {
            if let harvest = confirmPitch {
                let ml = min(harvest.slurryML, harvest.slurryML(forCells: needed) ?? harvest.slurryML)
                Button("Pitch \(Int(ml.rounded())) mL") {
                    session.pitch(from: harvest)
                    store.useSlurry(ml, from: harvest.id)
                    confirmPitch = nil
                }
            }
        } message: {
            Text("The slurry used is taken out of the yeast bank, and this batch is recorded as the next generation.")
        }
    }

    private func pitchRow(_ harvest: YeastHarvest, needed: Double) -> some View {
        let ml = harvest.slurryML(forCells: needed) ?? .infinity
        let enough = ml <= harvest.slurryML
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(enough ? "Pitch \(Int(ml.rounded())) mL of slurry" : "Pitch all \(Int(harvest.slurryML.rounded())) mL")
                Text("\(harvest.source.isEmpty ? harvest.yeast.displayName : harvest.source) · \(Int(harvest.ageDays().rounded())) days old")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !enough {
                    Text("Only \(Int((harvest.viableCells() / max(needed, 1) * 100).rounded()))% of the cells needed. Make a starter or add fresh yeast.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            GenerationBadge(generation: harvest.generation)
        }
    }
}
