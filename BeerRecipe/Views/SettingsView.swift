import SwiftUI
import BrewCore

struct SettingsView: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    @State private var equipment = Equipment()
    @State private var confirmRestore = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Units", selection: $units) {
                        ForEach(UnitSystem.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    NumberField(label: "Batch Size",
                                value: $equipment.batchSizeL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                                unit: units.volumeUnit)
                    NumberField(label: "Boil Time", value: $equipment.boilTimeMinutes, unit: "min", digits: 0)
                    NumberField(label: "Brewhouse Efficiency", value: $equipment.efficiency, unit: "%", digits: 0)
                    NumberField(label: "Boil-off Rate",
                                value: $equipment.boilOffLPerHour.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                                unit: "\(units.volumeUnit)/hr")
                    NumberField(label: "Kettle Trub Loss",
                                value: $equipment.trubLossL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                                unit: units.volumeUnit)
                    NumberField(label: "Mash Tun Deadspace",
                                value: $equipment.mashTunDeadspaceL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                                unit: units.volumeUnit)
                } header: {
                    Text("Defaults for New Recipes")
                } footer: {
                    Text("Measure your own system for the most accurate volume and gravity predictions.")
                }

                Section {
                    NavigationLink {
                        MyWaterView()
                    } label: {
                        LabeledContent("My Tap Water", value: store.myWater == nil ? "Not set" : "Saved")
                    }
                } header: {
                    Text("Water")
                } footer: {
                    Text("Used as the starting water when you set up water chemistry for a recipe.")
                }

                Section("Data") {
                    Button("Restore Sample Recipes") { confirmRestore = true }
                }

                Section {
                    LabeledContent("Formulas", value: "Tinseth / Rager IBU, Morey SRM")
                    LabeledContent("Styles", value: "BJCP 2021 (subset)")
                    LabeledContent("Recipe Exchange", value: "BeerXML 1.0")
                    Link("BeerXML specification", destination: URL(string: "http://www.beerxml.com")!)
                    Link("BJCP Style Guidelines", destination: URL(string: "https://www.bjcp.org/beer-styles/")!)
                    NavigationLink("Third-Party Notices") {
                        ScrollView {
                            Text(ThirdPartyNotices.text)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .navigationTitle("Third-Party Notices")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Recipes are stored on this device in the app's Documents folder and are visible in the Files app. Ingredient values are typical figures (partly from the open common-beer-data set by Wall Brew Co.) — check your supplier's specs.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.updateDefaultEquipment(equipment)
                        dismiss()
                    }
                }
            }
            .onAppear { equipment = store.defaultEquipment }
            .confirmationDialog("Add the sample recipes to your list?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Add Samples") { store.restoreSamples() }
            }
        }
    }
}
