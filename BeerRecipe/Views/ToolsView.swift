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
