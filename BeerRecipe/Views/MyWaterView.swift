import SwiftUI
import BrewCore

/// Edit the brewer's own tap water report.
struct MyWaterView: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var profile = WaterProfile(name: "My Water")
    @State private var importing = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Button("Scan or Paste a Water Report", systemImage: "doc.text.viewfinder") { importing = true }
            }
            Section {
                ForEach(Ion.allCases) { ion in
                    NumberField(label: "\(ion.displayName) (\(ion.symbol))",
                                value: Binding(get: { profile[ion] }, set: { profile[ion] = max(0, $0) }),
                                unit: "ppm", digits: 0)
                }
            } footer: {
                Text("Copy these from your water utility's annual report or a lab test. If the report gives alkalinity as CaCO₃ instead of bicarbonate, multiply it by 1.22.")
            }
            Section {
                LabeledContent("Residual Alkalinity",
                               value: "\(UnitSystem.number(profile.residualAlkalinityAsCaCO3, digits: 0)) ppm as CaCO₃")
                if let ratio = profile.sulfateToChloride {
                    LabeledContent("Sulfate : Chloride", value: UnitSystem.number(ratio, digits: 2))
                }
                if profile.ionBalanceError > 10 {
                    Label("Ion balance is off by \(Int(profile.ionBalanceError))%. Check the numbers.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("My Tap Water")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.saveMyWater(profile)
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $importing) {
            NavigationStack {
                WaterReportImportView(base: profile) { profile = $0 }
            }
        }
        .onAppear {
            // Only once, so values just imported from a report aren't replaced by the saved ones.
            guard !loaded else { return }
            loaded = true
            if let saved = store.myWater { profile = saved }
        }
    }
}
