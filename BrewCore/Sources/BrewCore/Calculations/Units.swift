import Foundation

public enum UnitSystem: String, Codable, CaseIterable, Sendable, Identifiable {
    case metric, imperial

    public var id: String { rawValue }
    public var displayName: String { self == .metric ? "Metric (kg, L, °C)" : "US (lb, gal, °F)" }

    // MARK: Labels

    public var largeWeightUnit: String { self == .metric ? "kg" : "lb" }
    public var smallWeightUnit: String { self == .metric ? "g" : "oz" }
    public var volumeUnit: String { self == .metric ? "L" : "gal" }
    public var temperatureUnit: String { self == .metric ? "°C" : "°F" }

    // MARK: Converting stored (metric) values to display values and back

    public func largeWeight(fromKg kg: Double) -> Double { self == .metric ? kg : BrewMath.kgToLb(kg) }
    public func kg(fromLargeWeight v: Double) -> Double { self == .metric ? v : BrewMath.lbToKg(v) }

    public func smallWeight(fromGrams g: Double) -> Double { self == .metric ? g : BrewMath.gramsToOunces(g) }
    public func grams(fromSmallWeight v: Double) -> Double { self == .metric ? v : BrewMath.ouncesToGrams(v) }

    public func volume(fromLiters l: Double) -> Double { self == .metric ? l : BrewMath.litersToGallons(l) }
    public func liters(fromVolume v: Double) -> Double { self == .metric ? v : BrewMath.gallonsToLiters(v) }

    public func temperature(fromC c: Double) -> Double { self == .metric ? c : BrewMath.cToF(c) }
    public func celsius(fromTemperature v: Double) -> Double { self == .metric ? v : BrewMath.fToC(v) }

    // MARK: Formatting

    public func formatLargeWeight(kg: Double) -> String {
        "\(Self.number(largeWeight(fromKg: kg), digits: 2)) \(largeWeightUnit)"
    }

    public func formatSmallWeight(grams: Double) -> String {
        let v = smallWeight(fromGrams: grams)
        return "\(Self.number(v, digits: self == .metric ? 0 : 2)) \(smallWeightUnit)"
    }

    public func formatVolume(liters: Double) -> String {
        "\(Self.number(volume(fromLiters: liters), digits: self == .metric ? 1 : 2)) \(volumeUnit)"
    }

    public func formatTemperature(celsius: Double) -> String {
        "\(Self.number(temperature(fromC: celsius), digits: 0))\(temperatureUnit)"
    }

    public static func number(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return "–" }
        return String(format: "%.\(digits)f", value)
    }

    public static func gravity(_ sg: Double) -> String { String(format: "%.3f", sg) }
}
