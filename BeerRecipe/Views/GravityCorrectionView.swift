import SwiftUI
import BrewCore

/// What to do when the wort is off its target gravity: add water, add dry malt extract, or boil
/// longer.
struct GravityCorrectionView: View {
    enum Stage: String, CaseIterable, Identifiable {
        case beforeBoil, afterBoil
        var id: String { rawValue }
        var displayName: String { self == .beforeBoil ? "Before Boil" : "After Boil" }
    }

    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    @State private var stage: Stage
    @State private var measuredSG: Double
    @State private var volumeL: Double
    @State private var boilMinutes: Double
    @State private var boilOffLPerHour: Double
    @State private var targetSG: Double

    init(stage: Stage = .beforeBoil, measuredSG: Double = 1.044, volumeL: Double = 27,
         boilMinutes: Double = 60, boilOffLPerHour: Double = 3.5, targetSG: Double = 1.050) {
        _stage = State(initialValue: stage)
        _measuredSG = State(initialValue: measuredSG)
        _volumeL = State(initialValue: volumeL)
        _boilMinutes = State(initialValue: boilMinutes)
        _boilOffLPerHour = State(initialValue: boilOffLPerHour)
        _targetSG = State(initialValue: targetSG)
    }

    /// Prefilled from a brew session's plan and measurements.
    init(session: BrewSession, stage: Stage) {
        let plan = session.plan
        let boilOff = max(0, plan.preBoilVolumeL - plan.postBoilVolumeL)
        let rate = plan.boilTimeMinutes > 0 ? boilOff / plan.boilTimeMinutes * 60 : 3.5
        if stage == .beforeBoil {
            self.init(stage: .beforeBoil,
                      measuredSG: session.preBoilGravity ?? plan.preBoilGravity,
                      volumeL: session.preBoilVolumeL ?? plan.preBoilVolumeL,
                      boilMinutes: plan.boilTimeMinutes, boilOffLPerHour: rate, targetSG: plan.og)
        } else {
            self.init(stage: .afterBoil,
                      measuredSG: session.og ?? plan.og,
                      volumeL: session.postBoilVolumeL ?? session.fermenterVolumeL ?? plan.postBoilVolumeL,
                      boilMinutes: 0, boilOffLPerHour: rate, targetSG: plan.og)
        }
    }

    var body: some View {
        let boilOff = stage == .beforeBoil ? boilOffLPerHour * boilMinutes / 60 : 0
        let result = GravityCorrection.plan(measuredSG: measuredSG, volumeL: volumeL, boilOffL: boilOff,
                                            targetSG: targetSG, boilOffLPerHour: boilOffLPerHour)

        Form {
            Section {
                Picker("Stage", selection: $stage) {
                    ForEach(Stage.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                NumberField(label: "Measured Gravity", value: $measuredSG, unit: "SG", digits: 3)
                NumberField(label: stage == .beforeBoil ? "Volume in Kettle" : "Volume",
                            value: $volumeL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                            unit: units.volumeUnit)
            } header: {
                Text("Measured")
            } footer: {
                Text("Temperature-correct the reading first. Measure volume at the same point you took the sample.")
            }

            Section {
                if stage == .beforeBoil {
                    NumberField(label: "Boil Time Left", value: $boilMinutes, unit: "min", digits: 0)
                }
                NumberField(label: "Boil-off Rate",
                            value: $boilOffLPerHour.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                            unit: "\(units.volumeUnit)/hr")
                NumberField(label: "Target Gravity", value: $targetSG, unit: "SG", digits: 3)
            } header: {
                Text("Plan")
            } footer: {
                Text(stage == .beforeBoil
                     ? "Target is the gravity you want at the end of the boil, usually the recipe's OG."
                     : "Use this for wort that's finished boiling, in the kettle or the fermenter.")
            }

            Section("If Nothing Changes") {
                ResultRow(label: stage == .beforeBoil ? "End-of-Boil Gravity" : "Gravity",
                          value: UnitSystem.gravity(result.projectedSG), emphasized: true)
                ResultRow(label: "Volume", value: units.formatVolume(liters: result.projectedVolumeL))
                ResultRow(label: "Difference", value: String(format: "%+.1f pts", result.differencePoints))
            }

            fixSection(result)
        }
        .navigationTitle("Gravity Correction")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }

    @ViewBuilder
    private func fixSection(_ result: GravityCorrection.Result) -> some View {
        if result.isOnTarget {
            Section {
                Label("On target. Nothing to change.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } else if result.isHigh, let water = result.waterToAddL {
            Section {
                ResultRow(label: "Add Water", value: units.formatVolume(liters: water), emphasized: true)
                if let after = result.volumeAfterWaterL {
                    ResultRow(label: "New Volume", value: units.formatVolume(liters: after))
                }
            } header: {
                Text("Too Strong")
            } footer: {
                Text(stage == .beforeBoil
                     ? "Add boiled or filtered water to the kettle now, or top up the fermenter after the boil. You'll end up with more beer at the target gravity. Hop bitterness will be slightly lower."
                     : "Add boiled, cooled water to the fermenter. You'll end up with more beer at the target gravity.")
            }
        } else if result.isLow {
            Section {
                if let grams = result.dryMaltExtractGrams {
                    ResultRow(label: "Add Dry Malt Extract",
                              value: grams >= 1000 ? units.formatLargeWeight(kg: grams / 1000) : units.formatSmallWeight(grams: grams),
                              emphasized: true)
                }
                if let minutes = result.extraBoilMinutes, let after = result.volumeAfterExtraBoilL {
                    ResultRow(label: "Or Boil Longer", value: "\(Int(minutes.rounded())) min")
                    ResultRow(label: "Volume After", value: units.formatVolume(liters: after))
                }
            } header: {
                Text("Too Weak")
            } footer: {
                Text("Dry malt extract keeps the batch size; stir it into a little hot wort first so it doesn't clump. A longer boil keeps the recipe all-grain but makes less beer. Add the extra time before your first hop addition so hop timings stay the same.")
            }
        }
    }
}
