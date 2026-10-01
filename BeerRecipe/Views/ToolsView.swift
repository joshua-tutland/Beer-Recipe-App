import SwiftUI
import BrewCore

/// Settings shared by the gravity tools and the brew log.
enum GravitySettings {
    static let wcfKey = "wortCorrectionFactor"
    static let calibrationKey = "hydrometerCalibrationC"
    static let defaultCalibrationC = 20.0
}

/// Quick brewing calculators: hydrometer correction, refractometer conversions, and ABV.
struct ToolsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        HydrometerCorrectionView()
                    } label: {
                        toolLabel("Hydrometer Temperature Correction", "thermometer.medium",
                                  "Correct a reading taken warmer or colder than your hydrometer's calibration.")
                    }
                    NavigationLink {
                        RefractometerView()
                    } label: {
                        toolLabel("Refractometer: Wort", "drop",
                                  "Convert Brix to gravity before fermentation, and calibrate your correction factor.")
                    }
                    NavigationLink {
                        RefractometerFermentingView()
                    } label: {
                        toolLabel("Refractometer: Fermenting Beer", "drop.degreesign",
                                  "Get the real gravity once alcohol is present, from original and current Brix.")
                    }
                    NavigationLink {
                        YeastStarterView()
                    } label: {
                        toolLabel("Yeast Starter", "flask",
                                  "Cells needed, yeast viability, and starter size (stir plate or not), up to 3 steps.")
                    }
                    NavigationLink {
                        KegCarbonationView()
                    } label: {
                        toolLabel("Keg Carbonation", "gauge.with.dots.needle.33percent",
                                  "Regulator pressure for your target CO₂ and a balanced serving line length.")
                    }
                    NavigationLink {
                        ABVCalculatorView()
                    } label: {
                        toolLabel("ABV Calculator", "percent",
                                  "Alcohol, attenuation and calories from OG and FG.")
                    }
                }
            }
            .navigationTitle("Brewing Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func toolLabel(_ title: String, _ icon: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.brewAmber)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Shared result styling

private struct ResultRow: View {
    let label: String
    let value: String
    var emphasized = false

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .font(emphasized ? .title3.weight(.semibold) : .body)
                .foregroundStyle(emphasized ? Color.brewAmber : Color.primary)
        }
    }
}

private struct GravityInput: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        NumberField(label: label, value: $value, unit: "SG", digits: 3)
    }
}

// MARK: - Hydrometer

struct HydrometerCorrectionView: View {
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    @AppStorage(GravitySettings.calibrationKey) private var calibrationC = GravitySettings.defaultCalibrationC
    @State private var reading = 1.050
    @State private var sampleTempC = 30.0

    var body: some View {
        let corrected = GravityTools.hydrometerCorrected(reading: reading, sampleTempC: sampleTempC,
                                                         calibrationTempC: calibrationC)
        Form {
            Section("Reading") {
                GravityInput(label: "Measured Gravity", value: $reading)
                NumberField(label: "Sample Temperature",
                            value: $sampleTempC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                            unit: units.temperatureUnit, digits: 1)
            }
            Section {
                NumberField(label: "Calibrated At",
                            value: $calibrationC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                            unit: units.temperatureUnit, digits: 1)
                HStack {
                    Button("60°F / 15.6°C") { calibrationC = BrewMath.fToC(60) }
                    Spacer()
                    Button("68°F / 20°C") { calibrationC = 20 }
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Hydrometer")
            } footer: {
                Text("The calibration temperature is printed on the hydrometer or its paperwork. It's remembered for next time and used by the brew log.")
            }
            Section("Result") {
                ResultRow(label: "Corrected Gravity", value: UnitSystem.gravity(corrected), emphasized: true)
                ResultRow(label: "Correction", value: String(format: "%+.1f pts", (corrected - reading) * 1000))
                ResultRow(label: "Plato", value: String(format: "%.1f°P", BrewMath.sgToPlato(corrected)))
            }
        }
        .navigationTitle("Hydrometer")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }
}

// MARK: - Refractometer (wort)

struct RefractometerView: View {
    @AppStorage(GravitySettings.wcfKey) private var wcf = GravityTools.defaultWortCorrectionFactor
    @State private var brix = 12.5
    @State private var calibrationBrix = 12.5
    @State private var calibrationSG = 1.048

    var body: some View {
        let sg = GravityTools.refractometerSG(brix: brix, wortCorrectionFactor: wcf)
        let measuredWCF = GravityTools.wortCorrectionFactor(brix: calibrationBrix, hydrometerSG: calibrationSG)

        Form {
            Section("Reading") {
                NumberField(label: "Refractometer", value: $brix, unit: "°Bx", digits: 1)
            }
            Section("Result") {
                ResultRow(label: "Gravity", value: UnitSystem.gravity(sg), emphasized: true)
                ResultRow(label: "Plato", value: String(format: "%.1f°P", BrewMath.sgToPlato(sg)))
            }
            Section {
                NumberField(label: "Wort Correction Factor", value: $wcf, digits: 3)
                Button("Reset to \(UnitSystem.number(GravityTools.defaultWortCorrectionFactor, digits: 2))") {
                    wcf = GravityTools.defaultWortCorrectionFactor
                }
            } header: {
                Text("Correction Factor")
            } footer: {
                Text("Refractometers are calibrated for sugar water, and wort reads a little high. 1.04 is typical; calibrate below for your own instrument.")
            }
            Section {
                NumberField(label: "Refractometer", value: $calibrationBrix, unit: "°Bx", digits: 1)
                NumberField(label: "Hydrometer", value: $calibrationSG, unit: "SG", digits: 3)
                ResultRow(label: "Your Factor", value: measuredWCF.map { UnitSystem.number($0, digits: 3) } ?? "–")
                Button("Use This Factor") {
                    if let measuredWCF { wcf = (measuredWCF * 1000).rounded() / 1000 }
                }
                .disabled(measuredWCF.map { $0 < 0.9 || $0 > 1.2 } ?? true)
            } header: {
                Text("Calibrate")
            } footer: {
                Text("Measure the same unfermented, cooled wort with both instruments (temperature-correct the hydrometer reading first). Average a few brews for the best result.")
            }
        }
        .navigationTitle("Refractometer: Wort")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }
}

// MARK: - Refractometer (fermenting)

struct RefractometerFermentingView: View {
    @AppStorage(GravitySettings.wcfKey) private var wcf = GravityTools.defaultWortCorrectionFactor
    @State private var originalBrix = 13.0
    @State private var currentBrix = 6.5

    var body: some View {
        let og = GravityTools.refractometerSG(brix: originalBrix, wortCorrectionFactor: wcf)
        let current = GravityTools.refractometerFermentingSG(originalBrix: originalBrix, currentBrix: currentBrix,
                                                             wortCorrectionFactor: wcf)
        let uncorrected = GravityTools.refractometerSG(brix: currentBrix, wortCorrectionFactor: wcf)

        Form {
            Section {
                NumberField(label: "Original Reading", value: $originalBrix, unit: "°Bx", digits: 1)
                NumberField(label: "Current Reading", value: $currentBrix, unit: "°Bx", digits: 1)
                NumberField(label: "Correction Factor", value: $wcf, digits: 3)
            } header: {
                Text("Readings")
            } footer: {
                Text("Use the Brix you measured before pitching yeast as the original reading.")
            }
            Section {
                ResultRow(label: "Current Gravity", value: UnitSystem.gravity(current), emphasized: true)
                ResultRow(label: "Original Gravity", value: UnitSystem.gravity(og))
                ResultRow(label: "ABV", value: String(format: "%.1f%%", BrewMath.abv(og: og, fg: current)))
                ResultRow(label: "Apparent Attenuation",
                          value: String(format: "%.0f%%", BrewMath.apparentAttenuation(og: og, fg: current)))
            } header: {
                Text("Result")
            } footer: {
                Text("Alcohol makes a refractometer read high. Converted directly, \(UnitSystem.number(currentBrix, digits: 1))°Bx would look like \(UnitSystem.gravity(uncorrected)). The corrected value uses Sean Terrill's formula.")
            }
        }
        .navigationTitle("Fermenting Beer")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }
}

// MARK: - ABV

struct ABVCalculatorView: View {
    @State private var og = 1.055
    @State private var fg = 1.012

    var body: some View {
        let valid = og > fg && og > 1
        Form {
            Section("Gravity") {
                GravityInput(label: "Original Gravity", value: $og)
                GravityInput(label: "Final Gravity", value: $fg)
            }
            Section("Result") {
                ResultRow(label: "ABV", value: valid ? String(format: "%.1f%%", BrewMath.abv(og: og, fg: fg)) : "–",
                          emphasized: true)
                ResultRow(label: "ABV (high-gravity formula)",
                          value: valid ? String(format: "%.1f%%", BrewMath.abvAlternate(og: og, fg: fg)) : "–")
                ResultRow(label: "Apparent Attenuation",
                          value: valid ? String(format: "%.0f%%", BrewMath.apparentAttenuation(og: og, fg: fg)) : "–")
                ResultRow(label: "Real Attenuation",
                          value: valid ? String(format: "%.0f%%", BrewMath.realAttenuation(og: og, fg: fg)) : "–")
                ResultRow(label: "Calories (12 oz)",
                          value: valid ? String(format: "%.0f", BrewMath.caloriesPer12oz(og: og, fg: fg)) : "–")
                ResultRow(label: "OG / FG Plato",
                          value: String(format: "%.1f / %.1f°P", BrewMath.sgToPlato(og), BrewMath.sgToPlato(fg)))
            }
        }
        .navigationTitle("ABV Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }
}

// MARK: - Yeast starter

struct YeastStarterView: View {
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    @State private var og = 1.055
    @State private var batchL = 20.0
    @State private var lager = false
    @State private var form = YeastForm.liquid
    @State private var packs = 1.0
    @State private var ageDays = 30.0
    @State private var dryGrams = 11.5
    @State private var steps: [YeastStarter.Step] = [.init(volumeL: 1.5)]

    var body: some View {
        let needed = (lager ? 1.5 : 0.75) * batchL * 1000 * max(BrewMath.sgToPlato(og), 0) / 1000
        let pitched = form == .liquid
            ? YeastStarter.liquidCells(packs: packs, ageDays: ageDays)
            : dryGrams * YeastStarter.dryCellsPerGram
        let results = form == .liquid ? YeastStarter.run(startingCells: pitched, steps: steps) : []
        let totalCells = results.last?.endCellsBillions ?? pitched

        Form {
            Section("Beer") {
                NumberField(label: "Original Gravity", value: $og, unit: "SG", digits: 3)
                NumberField(label: "Batch Size",
                            value: $batchL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                            unit: units.volumeUnit)
                Picker("Yeast Type", selection: $lager) {
                    Text("Ale (0.75 M/mL/°P)").tag(false)
                    Text("Lager (1.5 M/mL/°P)").tag(true)
                }
                ResultRow(label: "Cells Needed", value: "\(Int(needed.rounded())) billion", emphasized: true)
            }
            Section {
                Picker("Form", selection: $form) {
                    ForEach(YeastForm.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                if form == .liquid {
                    NumberField(label: "Packs / Vials", value: $packs, digits: 1)
                    NumberField(label: "Days Since Manufacture", value: $ageDays, unit: "days", digits: 0)
                } else {
                    NumberField(label: "Dry Yeast", value: $dryGrams, unit: "g", digits: 1)
                }
                ResultRow(label: "Viable Cells", value: "\(Int(pitched.rounded())) billion")
            } header: {
                Text("Your Yeast")
            } footer: {
                Text(form == .liquid
                     ? "Liquid yeast loses about 0.7% viability per day after manufacture."
                     : "Dry yeast is usually pitched without a starter; rehydrate it and add another sachet if you're short.")
            }
            if form == .liquid {
                ForEach($steps) { $step in
                    let index = steps.firstIndex { $0.id == step.id } ?? 0
                    Section {
                        NumberField(label: "Starter Volume",
                                    value: $step.volumeL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                                    unit: units.volumeUnit, digits: units == .metric ? 2 : 3)
                        NumberField(label: "Starter Gravity", value: $step.gravity, unit: "SG", digits: 3)
                        Picker("Aeration", selection: $step.aeration) {
                            ForEach(YeastStarter.Aeration.allCases) { Text($0.displayName).tag($0) }
                        }
                        if index < results.count {
                            let r = results[index]
                            ResultRow(label: "Dry Malt Extract", value: units.formatSmallWeight(grams: r.dryMaltExtractGrams))
                            ResultRow(label: "Cells After", value: "\(Int(r.endCellsBillions.rounded())) billion")
                        }
                    } header: {
                        HStack {
                            Text("Starter Step \(index + 1)")
                            Spacer()
                            if steps.count > 1 {
                                Button("Remove", role: .destructive) { steps.removeAll { $0.id == step.id } }
                                    .font(.caption)
                            }
                        }
                    }
                }
                if steps.count < 3 {
                    Button("Add Step", systemImage: "plus.circle") {
                        steps.append(.init(volumeL: (steps.last?.volumeL ?? 1) * 2))
                    }
                }
            }
            Section("Result") {
                ResultRow(label: "Total Cells", value: "\(Int(totalCells.rounded())) billion", emphasized: true)
                let ratio = needed > 0 ? totalCells / needed : 0
                Label(ratio >= 0.9 ? "Enough yeast (\(Int((ratio * 100).rounded()))% of target)"
                                   : "Short: \(Int((needed - totalCells).rounded())) billion more needed",
                      systemImage: ratio >= 0.9 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ratio >= 0.9 ? Color.green : Color.orange)
            }
        }
        .navigationTitle("Yeast Starter")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }
}

// MARK: - Kegging

struct KegCarbonationView: View {
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    @State private var tempC = 3.0
    @State private var volumes = 2.5
    @State private var line = Carbonation.Line.vinyl3_16
    @State private var riseFeet = 1.0

    var body: some View {
        let psi = Carbonation.forceCarbonationPSI(tempC: tempC, volumes: volumes)
        let feet = Carbonation.balancedLineFeet(kegPSI: psi, line: line, riseFeet: riseFeet)

        Form {
            Section("Beer") {
                NumberField(label: "Beer Temperature",
                            value: $tempC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                            unit: units.temperatureUnit, digits: 0)
                NumberField(label: "Target Carbonation", value: $volumes, unit: "vols", digits: 1)
                Text("Typical: British ales 1.5–2.0 · American ales & lagers 2.2–2.7 · Wheat & Belgian 2.8–3.5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Regulator") {
                ResultRow(label: "Set Pressure", value: String(format: "%.1f psi", psi), emphasized: true)
                ResultRow(label: "", value: String(format: "%.0f kPa · %.2f bar", Carbonation.psiToKPa(psi), Carbonation.psiToKPa(psi) / 100))
            }
            Section {
                Picker("Beer Line", selection: $line) {
                    ForEach(Carbonation.Line.allCases) { Text($0.displayName).tag($0) }
                }
                NumberField(label: "Faucet Above Keg", value: $riseFeet, unit: "ft", digits: 1)
                ResultRow(label: "Line Length",
                          value: units == .metric ? String(format: "%.2f m", feet * 0.3048) : String(format: "%.1f ft", feet),
                          emphasized: true)
            } header: {
                Text("Balanced Serving Line")
            } footer: {
                Text("Long enough line keeps the pour from foaming. Start a little long and trim to taste.")
            }
        }
        .navigationTitle("Keg Carbonation")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }
}
