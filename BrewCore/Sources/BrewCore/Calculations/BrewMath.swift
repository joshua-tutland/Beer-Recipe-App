import Foundation

/// Stateless brewing formulas and unit conversions.
public enum BrewMath {
    // MARK: Unit conversions

    public static let poundsPerKilogram = 2.204_622_62
    public static let gallonsPerLiter = 0.264_172_05
    public static let ouncesPerGram = 0.035_273_96

    public static func kgToLb(_ kg: Double) -> Double { kg * poundsPerKilogram }
    public static func lbToKg(_ lb: Double) -> Double { lb / poundsPerKilogram }
    public static func litersToGallons(_ l: Double) -> Double { l * gallonsPerLiter }
    public static func gallonsToLiters(_ gal: Double) -> Double { gal / gallonsPerLiter }
    public static func gramsToOunces(_ g: Double) -> Double { g * ouncesPerGram }
    public static func ouncesToGrams(_ oz: Double) -> Double { oz / ouncesPerGram }
    public static func cToF(_ c: Double) -> Double { c * 9 / 5 + 32 }
    public static func fToC(_ f: Double) -> Double { (f - 32) * 5 / 9 }

    // MARK: Gravity

    /// Specific gravity → degrees Plato (ASBC polynomial).
    public static func sgToPlato(_ sg: Double) -> Double {
        -616.868 + 1111.14 * sg - 630.272 * sg * sg + 135.997 * sg * sg * sg
    }

    /// Degrees Plato → specific gravity.
    public static func platoToSG(_ plato: Double) -> Double {
        1 + plato / (258.6 - (plato / 258.2) * 227.1)
    }

    /// Standard homebrew ABV formula.
    public static func abv(og: Double, fg: Double) -> Double {
        max(0, (og - fg) * 131.25)
    }

    /// More accurate ABV for high gravity beers.
    public static func abvAlternate(og: Double, fg: Double) -> Double {
        max(0, (76.08 * (og - fg) / (1.775 - og)) * (fg / 0.794))
    }

    public static func apparentAttenuation(og: Double, fg: Double) -> Double {
        guard og > 1 else { return 0 }
        return (og - fg) / (og - 1) * 100
    }

    public static func realAttenuation(og: Double, fg: Double) -> Double {
        let oe = sgToPlato(og)
        guard oe > 0 else { return 0 }
        let ae = sgToPlato(fg)
        let re = 0.1808 * oe + 0.8192 * ae
        return (oe - re) / oe * 100
    }

    /// Calories per 12 US fl oz (355 mL) serving.
    public static func caloriesPer12oz(og: Double, fg: Double) -> Double {
        guard og > 1 else { return 0 }
        let alcohol = 1881.22 * fg * (og - fg) / (1.775 - og)
        let carbs = 3550.0 * fg * (0.1808 * og + 0.8192 * fg - 1.0004)
        return max(0, alcohol + carbs)
    }

    // MARK: Color

    /// Morey equation. `mcu` = Σ(lb × °L) / gal.
    public static func moreySRM(mcu: Double) -> Double {
        guard mcu > 0 else { return 0 }
        return 1.4922 * pow(mcu, 0.6859)
    }

    public static func srmToEBC(_ srm: Double) -> Double { srm * 1.97 }
    public static func ebcToSRM(_ ebc: Double) -> Double { ebc / 1.97 }
    public static func lovibondToSRM(_ l: Double) -> Double { max(0, 1.3546 * l - 0.76) }

    /// Approximate beer color for an SRM value as 8-bit RGB.
    public static func srmToRGB(_ srm: Double) -> (red: Int, green: Int, blue: Int) {
        let table: [(Double, Int, Int, Int)] = [
            (1, 255, 230, 153), (2, 255, 216, 120), (3, 255, 202, 90), (4, 255, 191, 66),
            (5, 251, 177, 35), (6, 248, 166, 0), (7, 243, 156, 0), (8, 234, 143, 0),
            (9, 229, 133, 0), (10, 222, 124, 0), (11, 215, 114, 0), (12, 207, 105, 0),
            (13, 203, 98, 0), (14, 195, 89, 0), (15, 187, 81, 0), (16, 181, 76, 0),
            (17, 176, 69, 0), (18, 166, 62, 0), (19, 161, 55, 0), (20, 155, 50, 0),
            (22, 142, 42, 0), (24, 131, 35, 0), (26, 121, 29, 0), (28, 111, 23, 0),
            (30, 102, 17, 0), (33, 91, 12, 0), (36, 79, 9, 0), (40, 64, 7, 0),
            (50, 45, 5, 0), (60, 30, 3, 0), (80, 18, 2, 0)
        ]
        let s = max(0, srm)
        if s <= table[0].0 { return (table[0].1, table[0].2, table[0].3) }
        for i in 1..<table.count where s <= table[i].0 {
            let (s0, r0, g0, b0) = table[i - 1]
            let (s1, r1, g1, b1) = table[i]
            let t = (s - s0) / (s1 - s0)
            func lerp(_ a: Int, _ b: Int) -> Int { Int((Double(a) + (Double(b) - Double(a)) * t).rounded()) }
            return (lerp(r0, r1), lerp(g0, g1), lerp(b0, b1))
        }
        let last = table[table.count - 1]
        return (last.1, last.2, last.3)
    }

    public static func srmToHex(_ srm: Double) -> String {
        let c = srmToRGB(srm)
        return String(format: "#%02X%02X%02X", c.red, c.green, c.blue)
    }

    // MARK: Bitterness

    /// Tinseth utilization for a boil of `minutes` in wort of gravity `boilGravity`.
    public static func tinsethUtilization(minutes: Double, boilGravity: Double) -> Double {
        guard minutes > 0 else { return 0 }
        let bigness = 1.65 * pow(0.000125, boilGravity - 1)
        let timeFactor = (1 - exp(-0.04 * minutes)) / 4.15
        return bigness * timeFactor
    }

    /// Tinseth IBU for one addition.
    public static func tinsethIBU(grams: Double, alphaAcidPercent: Double, minutes: Double,
                                  boilGravity: Double, volumeL: Double) -> Double {
        guard volumeL > 0 else { return 0 }
        let mgPerL = alphaAcidPercent / 100 * grams * 1000 / volumeL
        return tinsethUtilization(minutes: minutes, boilGravity: boilGravity) * mgPerL
    }

    /// Rager utilization (fraction) for a boil of `minutes`.
    public static func ragerUtilization(minutes: Double) -> Double {
        guard minutes > 0 else { return 0 }
        return (18.11 + 13.86 * tanh((minutes - 31.32) / 18.27)) / 100
    }

    /// Rager IBU for one addition.
    public static func ragerIBU(grams: Double, alphaAcidPercent: Double, minutes: Double,
                                boilGravity: Double, volumeL: Double) -> Double {
        guard volumeL > 0 else { return 0 }
        let adjustment = boilGravity > 1.050 ? (boilGravity - 1.050) / 0.2 : 0
        return grams * ragerUtilization(minutes: minutes) * (alphaAcidPercent / 100) * 1000
            / (volumeL * (1 + adjustment))
    }

    /// Alpha-acid isomerization rate at `tempC` relative to a rolling boil (Malowicki).
    public static func relativeIsomerizationRate(tempC: Double) -> Double {
        min(1, 2.39e11 * exp(-9773 / (tempC + 273.15)))
    }

    // MARK: Mash & water

    /// Strike water temperature for a single infusion.
    /// `ratioLPerKg` is liters of water per kilogram of grain.
    public static func strikeTemperature(targetC: Double, grainC: Double, ratioLPerKg: Double) -> Double {
        guard ratioLPerKg > 0 else { return targetC }
        return (0.41 / ratioLPerKg) * (targetC - grainC) + targetC
    }

    // MARK: Carbonation

    /// Dissolved CO2 left in beer after fermentation at `tempC` (volumes).
    public static func residualCO2(tempC: Double) -> Double {
        let f = cToF(tempC)
        return 3.0378 - 0.050062 * f + 0.00026555 * f * f
    }

    /// Grams of corn sugar (dextrose) needed to bottle-prime `volumeL` liters.
    public static func primingDextroseGrams(volumeL: Double, targetVolumes: Double, beerTempC: Double) -> Double {
        let needed = targetVolumes - residualCO2(tempC: beerTempC)
        return max(0, 15.195 * litersToGallons(volumeL) * needed)
    }
}
