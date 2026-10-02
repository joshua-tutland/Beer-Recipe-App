import Foundation

/// Fixes for wort that's off its target gravity, before or after the boil.
///
/// Sugar is conserved: gravity points × volume stays the same when wort is boiled down or
/// watered down, so a measured gravity and volume predict where the boil will end up, and how
/// much water, extract or extra boil time would bring it to the target.
public enum GravityCorrection {
    /// Typical potential of dry malt extract, in points per pound per gallon.
    public static let dryMaltExtractPPG = 44.0

    /// Readings within this many gravity points of the target count as on target.
    public static let tolerancePoints = 1.0

    public struct Result: Hashable, Sendable {
        /// Gravity at the end of the boil (or now, for wort that's already boiled) if nothing changes.
        public var projectedSG: Double
        /// Volume at the end of the boil (or now) if nothing changes.
        public var projectedVolumeL: Double
        public var targetSG: Double

        /// Water to add when the wort is too strong.
        public var waterToAddL: Double?
        /// Dry malt extract to add when the wort is too weak.
        public var dryMaltExtractGrams: Double?
        /// Extra boil time that concentrates weak wort to the target instead (needs a boil-off rate).
        public var extraBoilMinutes: Double?

        /// Volume after adding `waterToAddL`.
        public var volumeAfterWaterL: Double?
        /// Volume after boiling for `extraBoilMinutes` more.
        public var volumeAfterExtraBoilL: Double?

        /// Projected minus target, in gravity points (positive means too strong).
        public var differencePoints: Double { (projectedSG - targetSG) * 1000 }
        public var isOnTarget: Bool { abs(differencePoints) < GravityCorrection.tolerancePoints }
        public var isLow: Bool { !isOnTarget && differencePoints < 0 }
        public var isHigh: Bool { !isOnTarget && differencePoints > 0 }
    }

    /// Gravity points × liters: the amount of dissolved extract.
    public static func extractPoints(sg: Double, volumeL: Double) -> Double {
        max(0, (sg - 1) * 1000) * max(0, volumeL)
    }

    /// Gravity of `points` (gravity points × liters) dissolved in `volumeL`.
    public static func gravity(points: Double, volumeL: Double) -> Double {
        guard volumeL > 0 else { return 1 }
        return 1 + points / volumeL / 1000
    }

    /// Gravity points × liters that one kilogram of an extract with `ppg` adds.
    public static func pointLitersPerKg(ppg: Double) -> Double {
        ppg * BrewMath.poundsPerKilogram / BrewMath.gallonsPerLiter
    }

    /// Works out the fix for wort measured at `measuredSG` and `volumeL`.
    ///
    /// - Parameters:
    ///   - boilOffL: volume still to boil off as planned (0 for wort that's finished boiling).
    ///   - targetSG: the gravity the wort should end up at (the recipe's OG, or its pre-boil
    ///     gravity scaled to the end of the boil).
    ///   - boilOffLPerHour: the kettle's boil-off rate, used for the extra-boil option.
    ///   - extractPPG: potential of the extract that would be added.
    public static func plan(measuredSG: Double, volumeL: Double, boilOffL: Double = 0, targetSG: Double,
                            boilOffLPerHour: Double = 0, extractPPG: Double = dryMaltExtractPPG) -> Result {
        let points = extractPoints(sg: measuredSG, volumeL: volumeL)
        let endVolume = max(0.001, volumeL - max(0, boilOffL))
        let projected = gravity(points: points, volumeL: endVolume)
        var result = Result(projectedSG: projected, projectedVolumeL: endVolume, targetSG: targetSG)
        let targetPoints = (targetSG - 1) * 1000
        guard targetPoints > 0, points > 0, !result.isOnTarget else { return result }

        if result.isHigh {
            // Dilute: the same extract spread through more water.
            let neededVolume = points / targetPoints
            result.waterToAddL = neededVolume - endVolume
            result.volumeAfterWaterL = neededVolume
        } else {
            // Add extract to reach the target at the planned volume…
            let missing = targetPoints * endVolume - points
            if extractPPG > 0 {
                result.dryMaltExtractGrams = missing / pointLitersPerKg(ppg: extractPPG) * 1000
            }
            // …or boil longer to concentrate what's there.
            let neededVolume = points / targetPoints
            if boilOffLPerHour > 0 {
                result.extraBoilMinutes = (endVolume - neededVolume) / boilOffLPerHour * 60
                result.volumeAfterExtraBoilL = neededVolume
            }
        }
        return result
    }

    /// Fix for a pre-boil reading in a brew session: projects the end of the boil using the
    /// planned boil-off and aims for the planned OG.
    public static func preBoil(measuredSG: Double, volumeL: Double, plan: BrewSession.Plan) -> Result {
        let boilOff = max(0, plan.preBoilVolumeL - plan.postBoilVolumeL)
        let rate = plan.boilTimeMinutes > 0 ? boilOff / plan.boilTimeMinutes * 60 : 0
        // OG is measured in the fermenter, but trub loss doesn't change gravity, so the
        // post-boil target is the same as the OG.
        return Self.plan(measuredSG: measuredSG, volumeL: volumeL, boilOffL: boilOff, targetSG: plan.og,
                         boilOffLPerHour: rate)
    }
}
