import SwiftUI
import BrewCore

/// Compact tiles for the top of the editor on iPhone.
struct StatsSummaryGrid: View {
    let stats: RecipeStats

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            StatTile(title: "OG", value: UnitSystem.gravity(stats.og))
            StatTile(title: "FG", value: UnitSystem.gravity(stats.fg))
            StatTile(title: "ABV", value: String(format: "%.1f%%", stats.abv))
            StatTile(title: "IBU", value: String(format: "%.0f", stats.ibu))
            StatTile(title: "SRM", value: String(format: "%.1f", stats.srm), swatch: stats.srm)
            StatTile(title: "BU:GU", value: String(format: "%.2f", stats.buGuRatio))
        }
        .padding(.vertical, 4)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    var swatch: Double?

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if let swatch { BeerSwatch(srm: swatch, size: 16) }
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Full analysis: vital stats, style fit, brew-day volumes, grist and bitterness breakdowns.
struct StatsPanel: View {
    let recipe: Recipe
    let stats: RecipeStats
    let units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            vitals
            if let style = recipe.style { styleFit(style) }
            brewDay
            if !stats.fermentableShares.isEmpty { grist }
            if stats.ibu > 0 { bitterness }
            packaging
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            BeerSwatch(srm: stats.srm, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name.isEmpty ? "Untitled" : recipe.name).font(.title3.bold())
                Text(recipe.style?.displayName ?? "No style selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(units.formatVolume(liters: recipe.equipment.batchSizeL)) · \(recipe.type.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var vitals: some View {
        card("Vital Statistics") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                StatTile(title: "Original Gravity", value: UnitSystem.gravity(stats.og),
                         detail: String(format: "%.1f°P", stats.ogPlato))
                StatTile(title: "Final Gravity", value: UnitSystem.gravity(stats.fg),
                         detail: String(format: "%.1f°P", stats.fgPlato))
                StatTile(title: "ABV", value: String(format: "%.1f%%", stats.abv),
                         detail: String(format: "alt. %.1f%%", stats.abvAlternate))
                StatTile(title: "Bitterness", value: String(format: "%.0f IBU", stats.ibu),
                         detail: recipe.ibuFormula.displayName)
                StatTile(title: "Color", value: String(format: "%.1f SRM", stats.srm),
                         detail: String(format: "%.0f EBC", stats.ebc), swatch: stats.srm)
                StatTile(title: "BU:GU", value: String(format: "%.2f", stats.buGuRatio), detail: balanceLabel)
                StatTile(title: "Attenuation", value: String(format: "%.0f%%", stats.apparentAttenuation),
                         detail: String(format: "real %.0f%%", stats.realAttenuation))
                StatTile(title: "Calories", value: String(format: "%.0f", stats.caloriesPer12oz), detail: "per 12 oz")
            }
        }
    }

    private var balanceLabel: String {
        switch stats.buGuRatio {
        case ..<0.3: return "very malty"
        case ..<0.5: return "malty"
        case ..<0.7: return "balanced"
        case ..<0.9: return "hoppy"
        default: return "very bitter"
        }
    }

    private func styleFit(_ style: BeerStyle) -> some View {
        card("Style: \(style.name)") {
            VStack(spacing: 12) {
                ForEach(style.compare(stats)) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.label).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(row.formatted(row.value)).font(.subheadline.monospacedDigit())
                            Image(systemName: row.fit.symbol)
                                .foregroundStyle(row.fit == .inRange ? Color.green : Color.orange)
                        }
                        RangeBar(value: row.value, min: row.min, max: row.max, inRange: row.fit == .inRange)
                        HStack {
                            Text(row.formatted(row.min))
                            Spacer()
                            Text(row.formatted(row.max))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var brewDay: some View {
        card("Brew Day") {
            VStack(spacing: 8) {
                if stats.mashedGrainKg > 0 && recipe.type != .extract {
                    row("Strike Water", "\(units.formatVolume(liters: stats.strikeWaterL)) at \(units.formatTemperature(celsius: stats.strikeTempC))")
                    row("Sparge Water", units.formatVolume(liters: stats.spargeWaterL))
                }
                row("Total Water", units.formatVolume(liters: stats.totalWaterL))
                row("Pre-Boil Volume", units.formatVolume(liters: stats.preBoilVolumeL))
                row("Pre-Boil Gravity", UnitSystem.gravity(stats.preBoilGravity))
                row("Post-Boil Volume", units.formatVolume(liters: stats.postBoilVolumeL))
                row("Into Fermenter", units.formatVolume(liters: recipe.equipment.batchSizeL))
            }
        }
    }

    private var grist: some View {
        card("Grist") {
            VStack(spacing: 8) {
                ForEach(stats.fermentableShares) { share in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(share.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f%%", share.percent)).font(.subheadline.monospacedDigit())
                        }
                        ProgressView(value: min(max(share.percent, 0), 100), total: 100)
                            .tint(.brewAmber)
                    }
                }
            }
        }
    }

    private var bitterness: some View {
        card("Bitterness by Addition") {
            VStack(spacing: 8) {
                ForEach(stats.hopBitterness.filter { $0.ibu > 0.05 }) { hop in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(hop.name).font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f IBU", hop.ibu)).font(.subheadline.monospacedDigit())
                        }
                        ProgressView(value: hop.ibu, total: max(stats.ibu, 0.01))
                            .tint(.green)
                    }
                }
            }
        }
    }

    private var packaging: some View {
        card("Yeast & Packaging") {
            VStack(spacing: 8) {
                row("Cells Needed", String(format: "%.0f billion", stats.yeastCellsNeededBillions))
                if let yeast = recipe.yeasts.first {
                    // Rough viable-cell counts: an 11.5 g dry sachet ≈ 115 B, a fresh liquid pack ≈ 100 B.
                    let perPack = yeast.yeast.form == .dry ? 115.0 : 100.0
                    let packs = max(1, (stats.yeastCellsNeededBillions / perPack).rounded(.up))
                    row("Suggested Pitch", "\(Int(packs)) \(yeast.yeast.form == .dry ? "sachet" : "pack")\(packs == 1 ? "" : "s")")
                }
                row("Carbonation", String(format: "%.1f vols CO₂", recipe.fermentation.carbonationVolumes))
                row("Corn Sugar", units.formatSmallWeight(grams: stats.primingDextroseGrams))
                row("Table Sugar", units.formatSmallWeight(grams: stats.primingSucroseGrams))
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// A track showing a style range with a marker for the recipe's value.
struct RangeBar: View {
    let value: Double
    let min: Double
    let max: Double
    let inRange: Bool

    var body: some View {
        GeometryReader { geo in
            let span = Swift.max(max - min, 0.0001)
            let lower = min - span * 0.5
            let upper = max + span * 0.5
            let position = { (v: Double) -> CGFloat in
                CGFloat((Swift.min(Swift.max(v, lower), upper) - lower) / (upper - lower)) * geo.size.width
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemFill))
                Capsule()
                    .fill(Color.green.opacity(0.35))
                    .frame(width: position(max) - position(min))
                    .offset(x: position(min))
                Circle()
                    .fill(inRange ? Color.green : Color.orange)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(x: position(value) - 7)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}
