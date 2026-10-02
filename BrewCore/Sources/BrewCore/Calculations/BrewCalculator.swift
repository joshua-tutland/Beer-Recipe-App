import Foundation

/// Everything the app shows about a recipe's predicted numbers.
public struct RecipeStats: Hashable, Sendable {
    public struct FermentableShare: Hashable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var percent: Double
        public var gravityPoints: Double
    }

    public struct HopBitterness: Hashable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var ibu: Double
    }

    public var og: Double
    public var fg: Double
    public var abv: Double
    public var abvAlternate: Double
    public var ibu: Double
    public var srm: Double
    public var ebc: Double
    public var buGuRatio: Double
    public var apparentAttenuation: Double
    public var realAttenuation: Double
    public var ogPlato: Double
    public var fgPlato: Double
    public var caloriesPer12oz: Double

    public var preBoilGravity: Double
    public var preBoilVolumeL: Double
    public var postBoilVolumeL: Double
    public var totalGrainKg: Double
    public var mashedGrainKg: Double
    public var strikeWaterL: Double
    public var strikeTempC: Double
    public var spargeWaterL: Double
    public var totalWaterL: Double

    public var primingDextroseGrams: Double
    public var primingSucroseGrams: Double
    public var yeastCellsNeededBillions: Double

    public var fermentableShares: [FermentableShare]
    public var hopBitterness: [HopBitterness]

    public var colorHex: String { BrewMath.srmToHex(srm) }
}

public enum BrewCalculator {
    /// Attenuation assumed when no yeast has been chosen yet.
    public static let defaultAttenuation = 75.0

    public static func calculate(_ recipe: Recipe) -> RecipeStats {
        let eq = recipe.equipment
        let batchGal = BrewMath.litersToGallons(max(eq.batchSizeL, 0.001))
        let efficiency = eq.efficiency / 100

        let attenuation = (recipe.yeasts.map(\.attenuation).max() ?? defaultAttenuation) / 100

        // Gravity & color
        var totalPoints = 0.0      // gravity points × gallons
        var residualPoints = 0.0   // points left unfermented × gallons
        var mcu = 0.0
        var pointsById: [UUID: Double] = [:]
        for addition in recipe.fermentables {
            let f = addition.fermentable
            let lb = BrewMath.kgToLb(addition.amountKg)
            let yield = f.type.isMashed ? efficiency : 1.0
            let points = lb * f.potentialPPG * yield
            totalPoints += points
            pointsById[addition.id] = points / batchGal

            let fermentability = f.fermentability.map { $0 / 100 } ?? attenuation
            residualPoints += points * (1 - fermentability)
            mcu += lb * f.colorLovibond / batchGal
        }

        let ogPoints = totalPoints / batchGal
        let fgPoints = residualPoints / batchGal
        let og = 1 + ogPoints / 1000
        let fg = 1 + fgPoints / 1000
        let srm = BrewMath.moreySRM(mcu: mcu)

        let preBoilVolume = eq.preBoilVolumeL
        let postBoilVolume = eq.postBoilVolumeL
        let preBoilGravity = 1 + ogPoints * postBoilVolume / max(preBoilVolume, 0.001) / 1000
        let boilGravity = (preBoilGravity + og) / 2

        // Bitterness
        var hopIBUs: [RecipeStats.HopBitterness] = []
        var ibu = 0.0
        for hop in recipe.hops {
            let value = bitterness(of: hop, formula: recipe.ibuFormula, boilGravity: boilGravity,
                                   volumeL: postBoilVolume, boilMinutes: eq.boilTimeMinutes)
            ibu += value
            hopIBUs.append(.init(id: hop.id, name: hop.hop.name, ibu: value))
        }

        // Grist
        let totalKg = recipe.fermentables.reduce(0) { $0 + $1.amountKg }
        let shares = recipe.fermentables.map { a in
            RecipeStats.FermentableShare(id: a.id,
                                         name: a.fermentable.name,
                                         percent: totalKg > 0 ? a.amountKg / totalKg * 100 : 0,
                                         gravityPoints: pointsById[a.id] ?? 0)
        }

        // Water
        let mashedKg = recipe.fermentables.filter { $0.fermentable.type.isMashed }.reduce(0) { $0 + $1.amountKg }
        var strikeWater = mashedKg * eq.mashThicknessLPerKg
        let mashTemp = recipe.mashSteps.first?.tempC ?? 66
        let totalWater: Double
        let spargeWater: Double
        if mashedKg > 0 && recipe.type != .extract {
            totalWater = preBoilVolume + mashedKg * eq.grainAbsorptionLPerKg + eq.mashTunDeadspaceL
            if eq.mashMethod == .fullVolume {
                // Brew in a bag / no sparge: every drop of water goes into the mash.
                strikeWater = totalWater
                spargeWater = 0
            } else {
                spargeWater = max(0, totalWater - strikeWater)
            }
        } else {
            // Extract brewing (optionally steeping grains): top up to the pre-boil volume.
            totalWater = preBoilVolume + mashedKg * eq.grainAbsorptionLPerKg
            spargeWater = 0
        }
        let strikeTemp = BrewMath.strikeTemperature(
            targetC: mashTemp, grainC: eq.grainTempC,
            ratioLPerKg: mashedKg > 0 && strikeWater > 0 ? strikeWater / mashedKg : eq.mashThicknessLPerKg)

        // Packaging & yeast
        let dextrose = BrewMath.primingDextroseGrams(volumeL: eq.batchSizeL,
                                                     targetVolumes: recipe.fermentation.carbonationVolumes,
                                                     beerTempC: recipe.fermentation.bottlingTempC)
        let ogPlato = BrewMath.sgToPlato(og)
        let pitchRate = recipe.yeasts.first?.yeast.type.pitchRate ?? YeastType.ale.pitchRate
        let cellsBillions = pitchRate * eq.batchSizeL * 1000 * max(ogPlato, 0) / 1000

        return RecipeStats(
            og: og,
            fg: fg,
            abv: BrewMath.abv(og: og, fg: fg),
            abvAlternate: BrewMath.abvAlternate(og: og, fg: fg),
            ibu: ibu,
            srm: srm,
            ebc: BrewMath.srmToEBC(srm),
            buGuRatio: ogPoints > 0 ? ibu / ogPoints : 0,
            apparentAttenuation: BrewMath.apparentAttenuation(og: og, fg: fg),
            realAttenuation: BrewMath.realAttenuation(og: og, fg: fg),
            ogPlato: ogPlato,
            fgPlato: BrewMath.sgToPlato(fg),
            caloriesPer12oz: BrewMath.caloriesPer12oz(og: og, fg: fg),
            preBoilGravity: preBoilGravity,
            preBoilVolumeL: preBoilVolume,
            postBoilVolumeL: postBoilVolume,
            totalGrainKg: totalKg,
            mashedGrainKg: mashedKg,
            strikeWaterL: strikeWater,
            strikeTempC: strikeTemp,
            spargeWaterL: spargeWater,
            totalWaterL: totalWater,
            primingDextroseGrams: dextrose,
            primingSucroseGrams: dextrose * 0.91,
            yeastCellsNeededBillions: cellsBillions,
            fermentableShares: shares,
            hopBitterness: hopIBUs
        )
    }

    /// IBUs contributed by a single hop addition.
    public static func bitterness(of hop: HopAddition, formula: IBUFormula, boilGravity: Double,
                                  volumeL: Double, boilMinutes: Double) -> Double {
        let minutes: Double
        var multiplier = 1.0
        switch hop.use {
        case .boil:
            minutes = min(hop.time, boilMinutes)
        case .firstWort:
            // First wort hops sit in the wort for the whole boil and are commonly rated ~10% higher.
            minutes = boilMinutes
            multiplier = 1.1
        case .whirlpool:
            // Treat the hop stand as an equivalent boil time scaled by how fast alpha acids
            // isomerize at the stand temperature.
            minutes = hop.time * BrewMath.relativeIsomerizationRate(tempC: hop.whirlpoolTempC)
        case .mash:
            minutes = boilMinutes
            multiplier = 0.2
        case .dryHop:
            return 0
        }
        if hop.form != .leaf { multiplier *= 1.1 }

        let base: Double
        switch formula {
        case .tinseth:
            base = BrewMath.tinsethIBU(grams: hop.amountGrams, alphaAcidPercent: hop.alphaAcid,
                                       minutes: minutes, boilGravity: boilGravity, volumeL: volumeL)
        case .rager:
            base = BrewMath.ragerIBU(grams: hop.amountGrams, alphaAcidPercent: hop.alphaAcid,
                                     minutes: minutes, boilGravity: boilGravity, volumeL: volumeL)
        }
        return base * multiplier
    }
}
