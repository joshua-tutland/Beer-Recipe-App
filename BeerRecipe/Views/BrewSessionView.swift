import SwiftUI
import Charts
import BrewCore

/// Records one brew: measured volumes and gravities, fermentation readings, and tasting notes,
/// compared with what the recipe predicted.
struct BrewSessionView: View {
    @Binding var session: BrewSession
    @Binding var recipe: Recipe
    let units: UnitSystem

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newReading: Double?
    @State private var newReadingTempC: Double?
    @State private var instrument = Instrument.hydrometer
    @AppStorage(GravitySettings.wcfKey) private var wcf = GravityTools.defaultWortCorrectionFactor
    @AppStorage(GravitySettings.calibrationKey) private var calibrationC = GravitySettings.defaultCalibrationC
    @State private var newReadingDate = Date()
    @State private var appliedMessage: String?

    var body: some View {
        let plan = session.plan
        let results = session.results

        Form {
            Section {
                NavigationLink {
                    BrewDayChecklistView(session: $session, recipe: recipe, units: units)
                } label: {
                    let steps = BrewDayPlan.steps(for: recipe, units: units)
                    let done = steps.filter { session.isStepDone($0.id) }.count
                    HStack {
                        Label("Brew Day Checklist & Timers", systemImage: "checklist")
                            .font(.headline)
                            .foregroundStyle(Color.brewAmber)
                        Spacer()
                        Text("\(done)/\(steps.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            inventorySection

            Section {
                TextField("Name", text: $session.name)
                DatePicker("Brew Date", selection: $session.brewDate, displayedComponents: .date)
            }

            Section("Mash") {
                MeasurementField(label: "Mash Temp",
                                 value: $session.mashTempC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                                 unit: units.temperatureUnit, digits: 1,
                                 planned: recipe.mashSteps.first.map { units.temperature(fromC: $0.tempC) })
                MeasurementField(label: "Mash pH", value: $session.mashPH, digits: 2, planned: nil)
            }

            Section("Boil") {
                volumeField("Pre-Boil Volume", $session.preBoilVolumeL, planned: plan.preBoilVolumeL)
                gravityField("Pre-Boil Gravity", $session.preBoilGravity, planned: plan.preBoilGravity)
                volumeField("Post-Boil Volume", $session.postBoilVolumeL, planned: plan.postBoilVolumeL)
            }

            Section("Into Fermenter") {
                gravityField("Original Gravity", $session.og, planned: plan.og)
                volumeField("Volume", $session.fermenterVolumeL, planned: plan.batchSizeL)
            }

            fermentationSection(plan: plan)

            if session.og != nil && session.fg == nil {
                TiltLogSection(session: $session)
            }

            resultsSection(plan: plan, results: results)

            Section("Tasting") {
                HStack {
                    Text("Rating")
                    Spacer()
                    RatingControl(rating: $session.rating)
                }
                TextField("How did it turn out? What would you change?", text: $session.notes, axis: .vertical)
                    .lineLimit(3...10)
                NavigationLink {
                    ScoresheetView(session: $session)
                } label: {
                    HStack {
                        Label("Scoresheet", systemImage: "list.clipboard")
                        Spacer()
                        if let sheet = session.scoresheet {
                            Text("\(sheet.total)/50 · \(sheet.rating)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Recipe Updated", isPresented: Binding(get: { appliedMessage != nil }, set: { if !$0 { appliedMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appliedMessage ?? "")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var inventorySection: some View {
        if !store.inventory.isEmpty || session.inventoryDeductedAt != nil {
            Section {
                if let date = session.inventoryDeductedAt {
                    Label("Ingredients deducted \(date.formatted(date: .abbreviated, time: .shortened))",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    let missing = Inventory.needs(for: recipe, stock: store.inventory).filter { !$0.isCovered }
                    Button("Deduct Ingredients from Inventory", systemImage: "shippingbox") {
                        store.setInventory(Inventory.deducting(recipe, from: store.inventory))
                        session.inventoryDeductedAt = Date()
                    }
                    if !missing.isEmpty {
                        Text("\(missing.count) ingredient\(missing.count == 1 ? " isn't" : "s aren't") fully in stock; whatever is on hand will be used.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } footer: {
                Text("Uses the recipe's current amounts and takes the oldest stock first.")
            }
        }
    }

    @ViewBuilder
    private func fermentationSection(plan: BrewSession.Plan) -> some View {
        Section {
            if session.og != nil || !session.readings.isEmpty {
                GravityChart(session: session)
                    .frame(height: 180)
                    .padding(.vertical, 4)
            }

            ForEach(session.readings.sorted { $0.date < $1.date }) { reading in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reading.date, format: .dateTime.month().day().hour().minute())
                        if !reading.note.isEmpty {
                            Text(reading.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(UnitSystem.gravity(reading.gravity)).monospacedDigit()
                }
            }
            .onDelete { offsets in
                let sorted = session.readings.sorted { $0.date < $1.date }
                let ids = Set(offsets.map { sorted[$0].id })
                session.readings.removeAll { ids.contains($0.id) }
            }

            Picker("Instrument", selection: $instrument) {
                Text("Hydrometer").tag(Instrument.hydrometer)
                Text("Refractometer").tag(Instrument.refractometer)
            }
            .pickerStyle(.segmented)
            DatePicker("Taken", selection: $newReadingDate)
            if instrument == .hydrometer {
                MeasurementField(label: "Gravity", value: $newReading, unit: "SG", digits: 3, planned: nil)
                MeasurementField(label: "Sample Temp",
                                 value: $newReadingTempC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                                 unit: units.temperatureUnit, digits: 0,
                                 planned: nil)
            } else {
                MeasurementField(label: "Reading", value: $newReading, unit: "°Bx", digits: 1, planned: nil)
            }
            Button {
                if let pending = pendingReading {
                    session.readings.append(pending)
                    newReading = nil
                    newReadingTempC = nil
                    newReadingDate = Date()
                }
            } label: {
                HStack {
                    Label("Add Reading", systemImage: "plus.circle.fill")
                    Spacer()
                    if let pending = pendingReading {
                        Text("→ \(UnitSystem.gravity(pending.gravity))").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(pendingReading == nil)

            gravityField("Final Gravity", $session.fg, planned: plan.fg)

            Toggle("Packaged", isOn: Binding(
                get: { session.packagedDate != nil },
                set: { session.packagedDate = $0 ? Date() : nil }))
            if session.packagedDate != nil {
                DatePicker("Packaged On", selection: Binding(
                    get: { session.packagedDate ?? Date() },
                    set: { session.packagedDate = $0 }), displayedComponents: .date)
                volumeField("Packaged Volume", $session.packagedVolumeL, planned: nil)
            }
        } header: {
            Text("Fermentation")
        } footer: {
            Text("Hydrometer readings are corrected for sample temperature; refractometer readings are corrected for alcohol using this batch's OG. Correction settings are in Brewing Tools. Enter the final gravity once readings are stable for 2–3 days.")
        }
    }

    @ViewBuilder
    private func resultsSection(plan: BrewSession.Plan, results: BrewSessionResults) -> some View {
        Section {
            resultRow("ABV", results.abv.map { String(format: "%.1f%%", $0) },
                      detail: session.fg == nil && results.abv != nil ? "so far" : nil)
            resultRow("Apparent Attenuation", results.apparentAttenuation.map { String(format: "%.0f%%", $0) })
            resultRow("OG vs Plan", results.ogDifference.map(pointsDelta))
            resultRow("FG vs Plan", results.fgDifference.map(pointsDelta))
            resultRow("Brewhouse Efficiency", results.brewhouseEfficiency.map { String(format: "%.0f%%", $0) },
                      detail: String(format: "planned %.0f%%", plan.efficiency))
            resultRow("Kettle Efficiency", results.kettleEfficiency.map { String(format: "%.0f%%", $0) })
            resultRow("Boil-off Rate", results.boilOffLPerHour.map { "\(units.formatVolume(liters: $0))/hr" },
                      detail: "recipe \(units.formatVolume(liters: recipe.equipment.boilOffLPerHour))/hr")

            if let efficiency = results.brewhouseEfficiency, efficiency > 20, efficiency < 100,
               recipe.type != .extract, abs(efficiency - recipe.equipment.efficiency) >= 1 {
                Button("Use \(Int(efficiency.rounded()))% Efficiency in Recipe") {
                    applyEfficiency(efficiency.rounded())
                }
            }
            if let rate = results.boilOffLPerHour, abs(rate - recipe.equipment.boilOffLPerHour) >= 0.1 {
                Button("Use Measured Boil-off Rate in Recipe") {
                    recipe.equipment.boilOffLPerHour = (rate * 10).rounded() / 10
                    appliedMessage = "Boil-off rate set to \(units.formatVolume(liters: recipe.equipment.boilOffLPerHour))/hr."
                }
            }
            if results.brewhouseEfficiency != nil || results.boilOffLPerHour != nil {
                Button("Save as Default Equipment") {
                    var equipment = store.defaultEquipment
                    if let e = results.brewhouseEfficiency, e > 20, e < 100 { equipment.efficiency = e.rounded() }
                    if let r = results.boilOffLPerHour { equipment.boilOffLPerHour = (r * 10).rounded() / 10 }
                    store.updateDefaultEquipment(equipment)
                    appliedMessage = "New recipes will use \(Int(equipment.efficiency))% efficiency and \(units.formatVolume(liters: equipment.boilOffLPerHour))/hr boil-off."
                }
            }
        } header: {
            Text("Results")
        } footer: {
            Text("Efficiency is calculated from the extract potential of the grain in the recipe when this brew started. Using your measured efficiency makes future predictions match your system.")
        }
    }

    // MARK: - Helpers

    enum Instrument: Hashable { case hydrometer, refractometer }

    /// The reading that "Add Reading" would log, converted to a true gravity.
    private var pendingReading: GravityReading? {
        guard let value = newReading else { return nil }
        switch instrument {
        case .hydrometer:
            guard value > 0.98, value < 1.2 else { return nil }
            if let temp = newReadingTempC {
                let corrected = GravityTools.hydrometerCorrected(reading: value, sampleTempC: temp, calibrationTempC: calibrationC)
                return GravityReading(date: newReadingDate, gravity: corrected, tempC: temp,
                                      note: "Hydrometer \(UnitSystem.gravity(value)) at \(units.formatTemperature(celsius: temp))")
            }
            return GravityReading(date: newReadingDate, gravity: value, note: "Hydrometer")
        case .refractometer:
            guard value > 0, value < 40 else { return nil }
            // Alcohol skews refractometer readings, so correct against the original gravity.
            let og = session.og ?? session.plan.og
            let originalBrix = GravityTools.expectedBrix(sg: og, wortCorrectionFactor: wcf)
            let gravity = value >= originalBrix
                ? GravityTools.refractometerSG(brix: value, wortCorrectionFactor: wcf)
                : GravityTools.refractometerFermentingSG(originalBrix: originalBrix, currentBrix: value, wortCorrectionFactor: wcf)
            return GravityReading(date: newReadingDate, gravity: gravity,
                                  note: "Refractometer \(UnitSystem.number(value, digits: 1))°Bx")
        }
    }

    private func applyEfficiency(_ efficiency: Double) {
        // Rescale grain so the recipe still hits its target gravity at the real efficiency.
        let batch = recipe.equipment.batchSizeL
        var updated = RecipeScaler.scale(recipe, with: .init(batchSizeL: batch, efficiency: efficiency))
        updated.sessions = recipe.sessions
        recipe = updated
        appliedMessage = "Efficiency set to \(Int(efficiency))%. Grain amounts were adjusted so the recipe still targets OG \(UnitSystem.gravity(recipe.stats.og))."
    }

    private func pointsDelta(_ delta: Double) -> String {
        let points = delta * 1000
        return String(format: "%@%.0f pts", points >= 0 ? "+" : "", points)
    }

    private func volumeField(_ label: String, _ value: Binding<Double?>, planned: Double?) -> some View {
        MeasurementField(label: label,
                         value: value.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                         unit: units.volumeUnit, digits: units == .metric ? 1 : 2,
                         planned: planned.map { units.volume(fromLiters: $0) })
    }

    private func gravityField(_ label: String, _ value: Binding<Double?>, planned: Double?) -> some View {
        MeasurementField(label: label, value: value, unit: "SG", digits: 3, planned: planned)
    }

    private func resultRow(_ label: String, _ value: String?, detail: String? = nil) -> some View {
        HStack {
            Text(label)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value ?? "–")
                    .monospacedDigit()
                    .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Gravity over time, from OG on brew day through each fermentation reading.
struct GravityChart: View {
    let session: BrewSession

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let gravity: Double
    }

    private var points: [Point] {
        var list: [(Date, Double)] = []
        if let og = session.og { list.append((session.brewDate, og)) }
        list += session.readings.map { ($0.date, $0.gravity) }
        return list.sorted { $0.0 < $1.0 }.enumerated().map { Point(id: $0.offset, date: $0.element.0, gravity: $0.element.1) }
    }

    var body: some View {
        let values = points.map(\.gravity) + [session.plan.fg, session.og ?? session.plan.og]
        let low = (values.min() ?? 1.0) - 0.004
        let high = (values.max() ?? 1.06) + 0.004

        Chart {
            RuleMark(y: .value("Target FG", session.plan.fg))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Target FG \(UnitSystem.gravity(session.plan.fg))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Gravity", point.gravity))
                    .foregroundStyle(Color.brewAmber)
                PointMark(x: .value("Date", point.date), y: .value("Gravity", point.gravity))
                    .foregroundStyle(Color.brewAmber)
            }
        }
        .chartYScale(domain: low...high)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(String(format: "%.3f", v)) }
                }
            }
        }
    }
}

struct RatingControl: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = rating == star ? 0 : star
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .foregroundStyle(star <= rating ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
    }
}

/// A brew log entry in the recipe editor.
struct BrewSessionRow: View {
    let session: BrewSession

    private var status: (String, Color) {
        if session.fg != nil { return ("Complete", .green) }
        if session.og != nil { return ("Fermenting", .orange) }
        return ("Brew Day", .blue)
    }

    var body: some View {
        let results = session.results
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.name).foregroundStyle(.primary)
                    Text(status.0)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(status.1.opacity(0.15), in: Capsule())
                        .foregroundStyle(status.1)
                }
                Text(session.brewDate, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let og = session.og {
                    Text("\(UnitSystem.gravity(og)) → \(session.currentGravity.map(UnitSystem.gravity) ?? "…")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                HStack(spacing: 6) {
                    if let abv = results.abv { Text(String(format: "%.1f%%", abv)) }
                    if let eff = results.brewhouseEfficiency { Text(String(format: "%.0f%% eff", eff)) }
                    if session.rating > 0 { Text(String(repeating: "★", count: session.rating)) }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }
}
