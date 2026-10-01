import SwiftUI
import BrewCore

/// Every equipment setting, in the brewer's units.
struct EquipmentFields: View {
    @Binding var equipment: Equipment
    let units: UnitSystem
    var includeBatch = true

    var body: some View {
        if includeBatch {
            NumberField(label: "Batch Size (into fermenter)",
                        value: $equipment.batchSizeL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                        unit: units.volumeUnit)
            NumberField(label: "Boil Time", value: $equipment.boilTimeMinutes, unit: "min", digits: 0)
        }
        NumberField(label: "Brewhouse Efficiency", value: $equipment.efficiency, unit: "%", digits: 0)
        Picker("Mash Method", selection: $equipment.mashMethod) {
            ForEach(MashMethod.allCases) { Text($0.displayName).tag($0) }
        }
        NumberField(label: "Boil-off Rate",
                    value: $equipment.boilOffLPerHour.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                    unit: "\(units.volumeUnit)/hr")
        NumberField(label: "Kettle Trub Loss",
                    value: $equipment.trubLossL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                    unit: units.volumeUnit)
        NumberField(label: "Mash Tun Dead Space",
                    value: $equipment.mashTunDeadspaceL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                    unit: units.volumeUnit)
        NumberField(label: "Grain Absorption",
                    value: $equipment.grainAbsorptionLPerKg.converted(
                        { units == .metric ? $0 : $0 * BrewMath.gallonsPerLiter / BrewMath.poundsPerKilogram },
                        { units == .metric ? $0 : $0 / (BrewMath.gallonsPerLiter / BrewMath.poundsPerKilogram) }),
                    unit: units == .metric ? "L/kg" : "gal/lb", digits: 3)
        if equipment.mashMethod == .sparge {
            NumberField(label: "Mash Thickness",
                        value: $equipment.mashThicknessLPerKg.converted(
                            { units == .metric ? $0 : $0 / BrewMath.poundsPerKilogram * 1.056_688 },
                            { units == .metric ? $0 : $0 * BrewMath.poundsPerKilogram / 1.056_688 }),
                        unit: units == .metric ? "L/kg" : "qt/lb")
        }
        NumberField(label: "Grain Temperature",
                    value: $equipment.grainTempC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                    unit: units.temperatureUnit, digits: 0)
    }
}

/// List of saved brewing systems.
struct EquipmentProfilesView: View {
    @Environment(RecipeStore.self) private var store
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    @State private var editing: EquipmentProfile?

    var body: some View {
        List {
            Section {
                ForEach(store.equipmentProfiles) { profile in
                    Button { editing = profile } label: {
                        ProfileRow(profile: profile, units: units, isDefault: profile.equipment == store.defaultEquipment)
                    }
                }
                .onDelete { offsets in
                    store.deleteProfiles(ids: offsets.map { store.equipmentProfiles[$0].id })
                }
                Button("New Profile from Current Defaults", systemImage: "plus.circle") {
                    editing = EquipmentProfile(name: "My System", equipment: store.defaultEquipment)
                }
            } header: {
                Text("My Systems")
            } footer: {
                if store.equipmentProfiles.isEmpty {
                    Text("Save your brewing system once and load it into any recipe.")
                }
            }

            Section {
                ForEach(EquipmentProfile.presets) { preset in
                    Button {
                        editing = EquipmentProfile(name: preset.name, equipment: preset.equipment, notes: preset.notes)
                    } label: {
                        ProfileRow(profile: preset, units: units, isDefault: false)
                    }
                }
            } header: {
                Text("Start from a Preset")
            } footer: {
                Text("Presets are typical starting points. Use the brew log's measured efficiency and boil-off to fine-tune your own.")
            }
        }
        .navigationTitle("Equipment Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { profile in
            NavigationStack {
                EquipmentProfileEditor(profile: profile, units: units)
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: EquipmentProfile
    let units: UnitSystem
    let isDefault: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).foregroundStyle(.primary)
                Text("\(units.formatVolume(liters: profile.equipment.batchSizeL)) · \(Int(profile.equipment.efficiency))% · \(profile.equipment.mashMethod == .fullVolume ? "full volume" : "mash + sparge")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDefault {
                Text("Default").font(.caption.weight(.semibold)).foregroundStyle(Color.brewAmber)
            }
        }
    }
}

struct EquipmentProfileEditor: View {
    @State var profile: EquipmentProfile
    let units: UnitSystem

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $profile.name)
                TextField("Notes", text: $profile.notes, axis: .vertical)
            }
            Section("Settings") {
                EquipmentFields(equipment: $profile.equipment, units: units)
            }
            Section {
                Button("Save and Use for New Recipes", systemImage: "star") {
                    store.saveProfile(profile)
                    store.updateDefaultEquipment(profile.equipment)
                    dismiss()
                }
            }
        }
        .navigationTitle(profile.name.isEmpty ? "Profile" : profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.saveProfile(profile)
                    dismiss()
                }
                .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

extension Equipment {
    /// Copies a system's settings into a recipe while keeping the recipe's own batch size and
    /// boil time.
    func applyingSystem(from profile: Equipment) -> Equipment {
        var result = profile
        result.batchSizeL = batchSizeL
        result.boilTimeMinutes = boilTimeMinutes
        return result
    }
}
