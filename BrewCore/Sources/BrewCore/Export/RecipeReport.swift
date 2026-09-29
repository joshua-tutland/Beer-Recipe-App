import Foundation

/// A format-neutral description of a printable recipe sheet.
/// Rendered to Word by `DocxWriter` and to PDF by the app.
public struct RecipeReport: Sendable {
    public struct Field: Sendable, Hashable {
        public var label: String
        public var value: String
    }

    public struct Table: Sendable, Hashable {
        public var headers: [String]
        public var rows: [[String]]
        /// Relative column widths.
        public var widths: [Double]
    }

    public enum Block: Sendable, Hashable {
        case heading(String)
        case paragraph(String)
        case fields([Field])
        case table(Table)
    }

    public var title: String
    public var subtitle: String
    public var colorHex: String
    public var blocks: [Block]

    public init(recipe: Recipe, units: UnitSystem) {
        let stats = recipe.stats
        let eq = recipe.equipment
        title = recipe.name.isEmpty ? "Untitled Recipe" : recipe.name
        subtitle = [recipe.style?.displayName, recipe.type.displayName,
                    recipe.author.isEmpty ? nil : "by \(recipe.author)"]
            .compactMap { $0 }.joined(separator: " · ")
        colorHex = stats.colorHex

        var blocks: [Block] = []
        func f(_ label: String, _ value: String) -> Field { Field(label: label, value: value) }
        let n = UnitSystem.number

        blocks.append(.heading("Vital Statistics"))
        blocks.append(.fields([
            f("Original Gravity", "\(UnitSystem.gravity(stats.og)) (\(n(stats.ogPlato, 1))°P)"),
            f("Final Gravity", "\(UnitSystem.gravity(stats.fg)) (\(n(stats.fgPlato, 1))°P)"),
            f("ABV", "\(n(stats.abv, 1))%"),
            f("Bitterness", "\(n(stats.ibu, 0)) IBU (\(recipe.ibuFormula.displayName))"),
            f("Color", "\(n(stats.srm, 1)) SRM / \(n(stats.ebc, 0)) EBC"),
            f("BU:GU", n(stats.buGuRatio, 2)),
            f("Apparent Attenuation", "\(n(stats.apparentAttenuation, 0))%"),
            f("Calories", "\(n(stats.caloriesPer12oz, 0)) per 12 oz / 355 mL")
        ]))

        if let style = recipe.style {
            blocks.append(.heading("Style: \(style.displayName)"))
            let rows = style.compare(stats).map { row -> [String] in
                let status: String
                switch row.fit {
                case .low: status = "Low"
                case .inRange: status = "In range"
                case .high: status = "High"
                }
                return [row.label, row.formatted(row.value),
                        "\(row.formatted(row.min)) – \(row.formatted(row.max))", status]
            }
            blocks.append(.table(Table(headers: ["", "Recipe", "Style Range", ""], rows: rows,
                                       widths: [2, 2, 3, 2])))
        }

        blocks.append(.heading("Batch"))
        blocks.append(.fields([
            f("Batch Size", units.formatVolume(liters: eq.batchSizeL)),
            f("Boil Time", "\(n(eq.boilTimeMinutes, 0)) min"),
            f("Efficiency", "\(n(eq.efficiency, 0))%"),
            f("Pre-Boil Volume", units.formatVolume(liters: stats.preBoilVolumeL)),
            f("Pre-Boil Gravity", UnitSystem.gravity(stats.preBoilGravity))
        ]))

        if !recipe.fermentables.isEmpty {
            blocks.append(.heading("Fermentables"))
            let rows = zip(recipe.fermentables, stats.fermentableShares).map { a, share in
                [a.fermentable.name, a.fermentable.type.displayName, units.formatLargeWeight(kg: a.amountKg),
                 "\(n(share.percent, 1))%", "\(n(a.fermentable.colorLovibond, 0)) °L"]
            }
            blocks.append(.table(Table(headers: ["Name", "Type", "Amount", "%", "Color"], rows: rows,
                                       widths: [5, 2.5, 2, 1.5, 1.5])))
        }

        if !recipe.hops.isEmpty {
            blocks.append(.heading("Hops"))
            let ibuById = Dictionary(uniqueKeysWithValues: stats.hopBitterness.map { ($0.id, $0.ibu) })
            let rows = recipe.hopsInBrewOrder.map { h in
                [h.hop.name, units.formatSmallWeight(grams: h.amountGrams), "\(n(h.alphaAcid, 1))%",
                 h.use.displayName, "\(n(h.time, 0)) \(h.use.timeUnit)", h.form.displayName,
                 n(ibuById[h.id] ?? 0, 1)]
            }
            blocks.append(.table(Table(headers: ["Name", "Amount", "AA", "Use", "Time", "Form", "IBU"],
                                       rows: rows, widths: [4, 2, 1.3, 2, 1.7, 1.6, 1.2])))
        }

        if !recipe.yeasts.isEmpty {
            blocks.append(.heading("Yeast"))
            let rows = recipe.yeasts.map { y in
                [y.yeast.displayName, y.yeast.form.displayName, "\(n(y.attenuation, 0))%",
                 "\(units.formatTemperature(celsius: y.yeast.tempMinC)) – \(units.formatTemperature(celsius: y.yeast.tempMaxC))",
                 n(y.packs, 1)]
            }
            blocks.append(.table(Table(headers: ["Yeast", "Form", "Attenuation", "Temp Range", "Packs"],
                                       rows: rows, widths: [5, 1.5, 2, 3, 1.3])))
        }

        if !recipe.miscs.isEmpty {
            blocks.append(.heading("Other Ingredients"))
            let rows = recipe.miscs.map { m in
                [m.misc.name, "\(n(m.amount, m.amount < 10 ? 1 : 0)) \(m.unit)", m.use.displayName,
                 m.timeMinutes > 0 ? "\(n(m.timeMinutes, 0)) min" : ""]
            }
            blocks.append(.table(Table(headers: ["Name", "Amount", "Use", "Time"], rows: rows,
                                       widths: [5, 2, 2, 2])))
        }

        if recipe.type != .extract || stats.mashedGrainKg > 0 {
            if !recipe.mashSteps.isEmpty {
                blocks.append(.heading(recipe.type == .extract ? "Steep" : "Mash"))
                let rows = recipe.mashSteps.map { s in
                    [s.name, s.type.displayName, units.formatTemperature(celsius: s.tempC), "\(n(s.minutes, 0)) min"]
                }
                blocks.append(.table(Table(headers: ["Step", "Type", "Temperature", "Time"], rows: rows,
                                           widths: [4, 2, 2, 2])))
            }
        }

        blocks.append(.heading("Water"))
        var water = [
            f("Strike Water", "\(units.formatVolume(liters: stats.strikeWaterL)) at \(units.formatTemperature(celsius: stats.strikeTempC))"),
            f("Sparge Water", units.formatVolume(liters: stats.spargeWaterL)),
            f("Total Water", units.formatVolume(liters: stats.totalWaterL))
        ]
        if recipe.type == .extract { water.removeFirst(2) }
        blocks.append(.fields(water))

        let ferm = recipe.fermentation
        blocks.append(.heading("Fermentation & Packaging"))
        var fermentation = [
            f("Primary", "\(n(ferm.primaryDays, 0)) days at \(units.formatTemperature(celsius: ferm.primaryTempC))")
        ]
        if ferm.secondaryDays > 0 { fermentation.append(f("Secondary", "\(n(ferm.secondaryDays, 0)) days")) }
        fermentation += [
            f("Yeast Cells Needed", "\(n(stats.yeastCellsNeededBillions, 0)) billion"),
            f("Carbonation", "\(n(ferm.carbonationVolumes, 1)) vol CO₂"),
            f("Priming Sugar", "\(units.formatSmallWeight(grams: stats.primingDextroseGrams)) corn sugar or \(units.formatSmallWeight(grams: stats.primingSucroseGrams)) table sugar")
        ]
        blocks.append(.fields(fermentation))

        let notes = recipe.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            blocks.append(.heading("Notes"))
            for paragraph in notes.components(separatedBy: .newlines) where !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }
        }

        self.blocks = blocks
    }
}
