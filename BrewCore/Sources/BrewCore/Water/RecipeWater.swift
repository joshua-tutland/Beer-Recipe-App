import Foundation

/// Water chemistry results for a recipe.
public struct WaterReport: Hashable, Sendable {
    /// Treated brewing water.
    public var profile: WaterProfile
    public var mashPH: MashPH.Estimate?
    public var balance: SulfateChlorideBalance?
    /// Liters the salt amounts are dosed for.
    public var totalWaterL: Double
    public var mashWaterL: Double
}

public extension Recipe {
    /// Total brewing water the water plan treats, and the share of it in the mash.
    var waterVolumes: (total: Double, mash: Double) {
        let s = stats
        let mash = s.mashedGrainKg > 0 ? (type == .extract ? s.mashedGrainKg * equipment.mashThicknessLPerKg : s.strikeWaterL) : 0
        return (max(s.totalWaterL, mash), mash)
    }

    var waterReport: WaterReport? {
        guard let water else { return nil }
        let volumes = waterVolumes
        let profile = water.resultingProfile(totalWaterL: volumes.total)
        let estimate = volumes.mash > 0
            ? MashPH.estimate(fermentables: fermentables, water: profile, mashWaterL: volumes.mash,
                              acidMEq: water.acidML * water.acid.mEqPerML)
            : nil
        return WaterReport(profile: profile,
                           mashPH: estimate,
                           balance: profile.sulfateToChloride.map(SulfateChlorideBalance.init(ratio:)),
                           totalWaterL: volumes.total,
                           mashWaterL: volumes.mash)
    }
}

public extension WaterTreatment {
    /// Adjustment that moves the estimated mash pH to the target: more acid, or baking soda
    /// when the mash is too acidic (common with dark beers and soft water).
    enum PHAdjustment: Hashable, Sendable {
        case none
        case acid(totalML: Double)
        case bakingSoda(addGrams: Double)
    }

    func suggestedPHAdjustment(for report: WaterReport) -> PHAdjustment {
        guard let estimate = report.mashPH else { return .none }
        let needed = estimate.acidNeededMEq
        if abs(needed) < 0.5 { return .none }
        let currentAcidMEq = acidML * acid.mEqPerML
        if needed > 0 || currentAcidMEq + needed >= 0 {
            let total = max(0, (currentAcidMEq + needed) / acid.mEqPerML)
            return .acid(totalML: (total * 10).rounded() / 10)
        }
        // Remove all acid, then add baking soda for the rest. Salts are spread over all the
        // brewing water, so only the mash share of the baking soda counts.
        let alkalinityNeeded = -(currentAcidMEq + needed)
        guard report.mashWaterL > 0, report.totalWaterL > 0 else { return .none }
        let mashShare = report.mashWaterL / report.totalWaterL
        let grams = alkalinityNeeded * 0.084 / mashShare
        return .bakingSoda(addGrams: (grams * 10).rounded() / 10)
    }
}
