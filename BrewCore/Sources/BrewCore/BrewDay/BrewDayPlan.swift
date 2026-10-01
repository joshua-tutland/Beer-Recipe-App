import Foundation

public enum BrewPhase: String, CaseIterable, Codable, Sendable {
    case prep, mash, sparge, boil, chill, ferment, later

    public var displayName: String {
        switch self {
        case .prep: return "Prep"
        case .mash: return "Mash"
        case .sparge: return "Lauter & Sparge"
        case .boil: return "Boil"
        case .chill: return "Whirlpool & Chill"
        case .ferment: return "Into the Fermenter"
        case .later: return "After Brew Day"
        }
    }

    public var symbol: String {
        switch self {
        case .prep: return "checklist"
        case .mash: return "thermometer.medium"
        case .sparge: return "drop.fill"
        case .boil: return "flame.fill"
        case .chill: return "snowflake"
        case .ferment: return "flask.fill"
        case .later: return "calendar"
        }
    }
}

/// An alert during a timed step, e.g. "10 min left: add 28 g Cascade".
public struct TimedAlert: Identifiable, Hashable, Sendable {
    public var id: String
    /// Minutes before the end of the step when the alert fires.
    public var minutesRemaining: Double
    public var title: String
}

public struct BrewStep: Identifiable, Hashable, Sendable {
    /// Stable identifier, used to remember which steps are done.
    public var id: String
    public var phase: BrewPhase
    public var title: String
    public var detail: String?
    /// Timer length for timed steps.
    public var durationMinutes: Double?
    /// Additions to make while the timer runs (boil schedule).
    public var alerts: [TimedAlert]

    public init(id: String, phase: BrewPhase, title: String, detail: String? = nil,
                durationMinutes: Double? = nil, alerts: [TimedAlert] = []) {
        self.id = id
        self.phase = phase
        self.title = title
        self.detail = detail
        self.durationMinutes = durationMinutes
        self.alerts = alerts
    }
}

/// Builds an ordered brew-day checklist from a recipe.
public enum BrewDayPlan {
    public static func steps(for recipe: Recipe, units u: UnitSystem) -> [BrewStep] {
        let stats = recipe.stats
        let eq = recipe.equipment
        let n = UnitSystem.number
        let mashes = recipe.type != .extract
        let hasMashedGrain = stats.mashedGrainKg > 0
        var steps: [BrewStep] = []

        // MARK: Prep
        steps.append(BrewStep(id: "prep-sanitize", phase: .prep, title: "Clean and sanitize equipment",
                              detail: "Anything that touches wort after the boil must be sanitized."))
        var summary: [String] = []
        let fermentableCount = recipe.fermentables.count
        if fermentableCount > 0 {
            let plural = fermentableCount == 1 ? "" : "s"
            summary.append("\(fermentableCount) fermentable\(plural) (\(u.formatLargeWeight(kg: stats.totalGrainKg)))")
        }
        let hopCount = recipe.hops.count
        if hopCount > 0 {
            summary.append("\(hopCount) hop addition\(hopCount == 1 ? "" : "s")")
        }
        if !recipe.yeasts.isEmpty {
            summary.append(recipe.yeasts.map(\.yeast.displayName).joined(separator: ", "))
        }
        let ingredientSummary = summary.joined(separator: " · ")
        steps.append(BrewStep(id: "prep-gather", phase: .prep, title: "Weigh out ingredients",
                              detail: ingredientSummary.isEmpty ? nil : ingredientSummary))
        if hasMashedGrain {
            steps.append(BrewStep(id: "prep-crush", phase: .prep, title: "Mill the grain",
                                  detail: "\(u.formatLargeWeight(kg: stats.mashedGrainKg)) to mash or steep"))
        }

        // MARK: Water treatment
        if let water = recipe.water, let report = recipe.waterReport, !water.salts.isEmpty || water.acidML > 0 || water.dilutionPercent > 0 {
            var parts: [String] = []
            if water.dilutionPercent > 0 {
                parts.append("Use \(n(water.dilutionPercent, 0))% distilled/RO water")
            }
            if !water.salts.isEmpty {
                let salts = water.salts.map { "\(n($0.grams, 1)) g \($0.salt.shortName)" }.joined(separator: ", ")
                parts.append("Add \(salts) to \(u.formatVolume(liters: report.totalWaterL)) of brewing water (split mash and sparge water proportionally)")
            }
            if water.acidML > 0 {
                parts.append("Add \(n(water.acidML, 1)) mL \(water.acid.displayName) to the mash")
            }
            var detail = parts.joined(separator: ". ") + "."
            if let ph = report.mashPH {
                detail += " Estimated mash pH \(n(ph.pH, 2))."
            }
            steps.append(BrewStep(id: "prep-water", phase: .prep, title: "Treat the brewing water", detail: detail))
        }

        // MARK: Mash / steep
        if mashes && hasMashedGrain {
            let fullVolume = eq.mashMethod == .fullVolume
            steps.append(BrewStep(id: "mash-strike", phase: .mash,
                                  title: "Heat \(u.formatVolume(liters: stats.strikeWaterL)) \(fullVolume ? "water (full volume)" : "strike water") to \(u.formatTemperature(celsius: stats.strikeTempC))",
                                  detail: fullVolume
                                    ? "All the brewing water goes in the mash; no sparge. Grain at \(u.formatTemperature(celsius: eq.grainTempC))"
                                    : "Mash thickness \(n(eq.mashThicknessLPerKg, 1)) L/kg; grain at \(u.formatTemperature(celsius: eq.grainTempC))"))
            let mashHops = recipe.hops.filter { $0.use == .mash }
            for (i, step) in recipe.mashSteps.enumerated() {
                var detail = step.type == .infusion && i == 0 ? "Stir in the grain and check the temperature." : nil
                if i == 0 && !mashHops.isEmpty {
                    let hopText = "Add mash hops: " + mashHops.map { "\(u.formatSmallWeight(grams: $0.amountGrams)) \($0.hop.name)" }.joined(separator: ", ")
                    detail = [detail, hopText].compactMap { $0 }.joined(separator: " ")
                }
                steps.append(BrewStep(id: "mash-\(i)", phase: .mash,
                                      title: "\(i == 0 ? "Mash in" : step.name): hold \(u.formatTemperature(celsius: step.tempC)) for \(n(step.minutes, 0)) min",
                                      detail: detail, durationMinutes: step.minutes > 0 ? step.minutes : nil))
            }
            if fullVolume {
                steps.append(BrewStep(id: "sparge", phase: .sparge, title: "Lift the bag and let it drain",
                                      detail: "A gentle squeeze recovers more wort; no sparge water needed."))
            } else {
                steps.append(BrewStep(id: "sparge", phase: .sparge,
                                      title: "Sparge with \(u.formatVolume(liters: stats.spargeWaterL)) at \(u.formatTemperature(celsius: 76))",
                                      detail: "Vorlauf until the runnings are clear, then lauter slowly."))
            }
        } else if hasMashedGrain {
            let steep = recipe.mashSteps.first
            let temp = steep?.tempC ?? 70
            let minutes = steep?.minutes ?? 30
            steps.append(BrewStep(id: "mash-steep", phase: .mash,
                                  title: "Steep specialty grains at \(u.formatTemperature(celsius: temp)) for \(n(minutes, 0)) min",
                                  detail: "Use a grain bag, then lift and drain; don't squeeze.", durationMinutes: minutes))
        }
        steps.append(BrewStep(id: "preboil", phase: .sparge,
                              title: "Collect \(u.formatVolume(liters: stats.preBoilVolumeL)) in the kettle",
                              detail: mashes && hasMashedGrain
                                ? "Target pre-boil gravity \(UnitSystem.gravity(stats.preBoilGravity)); record it in the brew log."
                                : "Top up with water; stir in extract off the heat so it doesn't scorch."))

        // MARK: Boil
        let firstWort = recipe.hops.filter { $0.use == .firstWort }
        if !firstWort.isEmpty {
            steps.append(BrewStep(id: "boil-fwh", phase: .boil, title: "Add first wort hops",
                                  detail: firstWort.map { "\(u.formatSmallWeight(grams: $0.amountGrams)) \($0.hop.name)" }.joined(separator: ", ")
                                    + " as the kettle fills."))
        }
        steps.append(BrewStep(id: "boil-start", phase: .boil, title: "Bring to a rolling boil",
                              detail: "Watch for boil-over as the hot break forms."))

        var byTime: [Double: [String]] = [:]
        for hop in recipe.hops where hop.use == .boil {
            let t = min(max(hop.time, 0), eq.boilTimeMinutes)
            byTime[t, default: []].append("\(u.formatSmallWeight(grams: hop.amountGrams)) \(hop.hop.name)")
        }
        for misc in recipe.miscs where misc.use == .boil {
            let t = min(max(misc.timeMinutes, 0), eq.boilTimeMinutes)
            byTime[t, default: []].append("\(n(misc.amount, misc.amount < 10 ? 1 : 0)) \(misc.unit) \(misc.misc.name)")
        }
        let alerts = byTime.keys.sorted(by: >).map { t -> TimedAlert in
            let items = byTime[t]!.joined(separator: ", ")
            let when: String
            if t >= eq.boilTimeMinutes {
                when = "Start of boil"
            } else if t == 0 {
                when = "Flameout"
            } else {
                when = "\(n(t, 0)) min left"
            }
            return TimedAlert(id: "boil-\(n(t, 0))", minutesRemaining: t, title: "\(when): add \(items)")
        }
        steps.append(BrewStep(id: "boil", phase: .boil, title: "Boil for \(n(eq.boilTimeMinutes, 0)) min",
                              detail: "Expect about \(u.formatVolume(liters: stats.postBoilVolumeL)) at the end.",
                              durationMinutes: eq.boilTimeMinutes > 0 ? eq.boilTimeMinutes : nil,
                              alerts: alerts))

        // MARK: Whirlpool & chill
        let whirlpool = recipe.hops.filter { $0.use == .whirlpool }
        if !whirlpool.isEmpty {
            let temp = whirlpool.map(\.whirlpoolTempC).max() ?? 80
            let minutes = whirlpool.map(\.time).max() ?? 20
            steps.append(BrewStep(id: "whirlpool", phase: .chill,
                                  title: "Hop stand at \(u.formatTemperature(celsius: temp)) for \(n(minutes, 0)) min",
                                  detail: "Add " + whirlpool.map { "\(u.formatSmallWeight(grams: $0.amountGrams)) \($0.hop.name)" }.joined(separator: ", "),
                                  durationMinutes: minutes))
        }
        steps.append(BrewStep(id: "chill", phase: .chill,
                              title: "Chill to \(u.formatTemperature(celsius: recipe.fermentation.primaryTempC))",
                              detail: "Cool quickly to reduce the chance of infection and DMS."))

        // MARK: Fermenter
        steps.append(BrewStep(id: "transfer", phase: .ferment,
                              title: "Transfer \(u.formatVolume(liters: eq.batchSizeL)) to the fermenter and aerate",
                              detail: "Leave the trub behind (about \(u.formatVolume(liters: eq.trubLossL)))."))
        steps.append(BrewStep(id: "measure-og", phase: .ferment,
                              title: "Measure original gravity (target \(UnitSystem.gravity(stats.og)))",
                              detail: "Record the OG and volume in the brew log."))
        if let yeast = recipe.yeasts.first {
            let packs = recipe.yeasts.reduce(0) { $0 + $1.packs }
            steps.append(BrewStep(id: "pitch", phase: .ferment,
                                  title: "Pitch \(n(packs, 0)) × \(yeast.yeast.displayName)",
                                  detail: "Ferment at \(u.formatTemperature(celsius: recipe.fermentation.primaryTempC)) for about \(n(recipe.fermentation.primaryDays, 0)) days."))
        }
        for misc in recipe.miscs where misc.use == .primary {
            steps.append(BrewStep(id: "primary-\(misc.id.uuidString)", phase: .ferment,
                                  title: "Add \(n(misc.amount, 1)) \(misc.unit) \(misc.misc.name)"))
        }

        // MARK: Later
        for hop in recipe.hops.filter({ $0.use == .dryHop }).sorted(by: { $0.time > $1.time }) {
            let day = max(0, recipe.fermentation.primaryDays - hop.time)
            steps.append(BrewStep(id: "dryhop-\(hop.id.uuidString)", phase: .later,
                                  title: "Day \(n(day, 0)): dry hop \(u.formatSmallWeight(grams: hop.amountGrams)) \(hop.hop.name)",
                                  detail: "\(n(hop.time, 0)) days before packaging"))
        }
        for misc in recipe.miscs where misc.use == .secondary {
            steps.append(BrewStep(id: "secondary-\(misc.id.uuidString)", phase: .later,
                                  title: "Add \(n(misc.amount, 1)) \(misc.unit) \(misc.misc.name)"))
        }
        steps.append(BrewStep(id: "measure-fg", phase: .later, title: "Confirm final gravity",
                              detail: "Stable for 2–3 days; the recipe predicts \(UnitSystem.gravity(stats.fg))."))
        steps.append(BrewStep(id: "package", phase: .later, title: "Package",
                              detail: "Bottling: \(u.formatSmallWeight(grams: stats.primingDextroseGrams)) corn sugar for \(n(recipe.fermentation.carbonationVolumes, 1)) vols CO₂, or keg and carbonate."))
        return steps
    }
}
