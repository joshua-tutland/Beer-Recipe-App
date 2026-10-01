import SwiftUI
import BrewCore

struct SettingsView: View {
    @Environment(RecipeStore.self) private var store
    @Environment(CloudSync.self) private var cloud
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
                    NavigationLink {
                        EquipmentProfilesView()
                    } label: {
                        Label("Equipment Profiles", systemImage: "cylinder.split.1x2")
                    }
                    EquipmentFields(equipment: $equipment, units: units)
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

                Section {
                    Toggle("Sync with iCloud", isOn: Binding(get: { cloud.isEnabled }, set: { cloud.setEnabled($0) }))
                    HStack(spacing: 8) {
                        switch cloud.status {
                        case .connecting:
                            ProgressView()
                        case .on:
                            Image(systemName: "checkmark.icloud").foregroundStyle(.green)
                        case .unavailable:
                            Image(systemName: "exclamationmark.icloud").foregroundStyle(.orange)
                        case .off:
                            Image(systemName: "iphone").foregroundStyle(.secondary)
                        }
                        Text(cloud.status.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Keeps recipes, brew logs, water plans, inventory and custom ingredients the same on your iPhone and iPad. Turning sync on merges this device's recipes into iCloud; if the same recipe was changed on two devices, the most recent edit wins.")
                }

                Section("Data") {
                    Button("Restore Sample Recipes") { confirmRestore = true }
                }

                Section {
                    LabeledContent("Formulas", value: "Tinseth / Rager IBU, Morey SRM")
                    LabeledContent("Styles", value: "BJCP 2021 (subset)")
                    LabeledContent("Recipe Exchange", value: "BeerXML 1.0 · BeerJSON 1.0")
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
            .onChange(of: store.defaultEquipment) { _, updated in equipment = updated }
            .confirmationDialog("Add the sample recipes to your list?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Add Samples") { store.restoreSamples() }
            }
        }
    }
}
