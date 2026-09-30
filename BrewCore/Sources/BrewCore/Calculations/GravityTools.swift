import Foundation

/// Hydrometer and refractometer conversions.
public enum GravityTools {
    /// Typical wort correction factor for refractometers (Brix reads high in wort vs. sucrose).
    public static let defaultWortCorrectionFactor = 1.04

    // MARK: Hydrometer

    /// Density of water relative to its value at 4 °C, as a polynomial in °F.
    private static func waterDensityFactor(_ f: Double) -> Double {
        1.00130346 - 0.000134722124 * f + 0.00000204052596 * f * f - 0.00000000232820948 * f * f * f
    }

    /// Corrects a hydrometer reading taken at `sampleTempC` for a hydrometer calibrated at
    /// `calibrationTempC` (commonly 15.6 °C / 60 °F or 20 °C / 68 °F).
    public static func hydrometerCorrected(reading: Double, sampleTempC: Double, calibrationTempC: Double) -> Double {
        let sample = BrewMath.cToF(sampleTempC)
        let calibration = BrewMath.cToF(calibrationTempC)
        return reading * waterDensityFactor(sample) / waterDensityFactor(calibration)
    }

    // MARK: Refractometer

    /// Converts a refractometer reading on unfermented wort to specific gravity.
    public static func refractometerSG(brix: Double, wortCorrectionFactor wcf: Double = defaultWortCorrectionFactor) -> Double {
        guard wcf > 0 else { return 1 }
        return BrewMath.platoToSG(brix / wcf)
    }

    /// The Brix a refractometer would show for wort of gravity `sg` (inverse of `refractometerSG`).
    public static func expectedBrix(sg: Double, wortCorrectionFactor wcf: Double = defaultWortCorrectionFactor) -> Double {
        BrewMath.sgToPlato(sg) * wcf
    }

    /// Final/current gravity from refractometer readings taken before (`originalBrix`) and during or
    /// after fermentation (`currentBrix`). Alcohol skews refractometer readings, so a direct
    /// conversion is wrong once fermentation starts; this uses Sean Terrill's cubic correction.
    public static func refractometerFermentingSG(originalBrix: Double, currentBrix: Double,
                                                 wortCorrectionFactor wcf: Double = defaultWortCorrectionFactor) -> Double {
        guard wcf > 0 else { return 1 }
        let ob = originalBrix / wcf
        let fb = currentBrix / wcf
        return 1.0
            - 0.0044993 * ob + 0.011774 * fb
            + 0.00027581 * ob * ob - 0.0012717 * fb * fb
            - 0.0000072800 * ob * ob * ob + 0.000063293 * fb * fb * fb
    }

    /// Wort correction factor from a paired refractometer and hydrometer reading of the same wort.
    public static func wortCorrectionFactor(brix: Double, hydrometerSG: Double) -> Double? {
        let plato = BrewMath.sgToPlato(hydrometerSG)
        guard plato > 0.5, brix > 0 else { return nil }
        return brix / plato
    }
}
