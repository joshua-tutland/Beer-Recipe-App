import Foundation

/// The Tilt wireless hydrometer. Each Tilt broadcasts an iBeacon whose UUID identifies its color,
/// with the temperature (°F) in the "major" field and specific gravity × 1000 in "minor". The
/// Tilt Pro sends one more decimal place: temperature × 10 and gravity × 10,000.
public enum Tilt {
    public enum Color: String, CaseIterable, Codable, Sendable, Identifiable {
        case red, green, black, purple, orange, blue, yellow, pink

        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }

        /// The iBeacon UUID this color broadcasts.
        public var uuid: UUID {
            let digit: Int
            switch self {
            case .red: digit = 1
            case .green: digit = 2
            case .black: digit = 3
            case .purple: digit = 4
            case .orange: digit = 5
            case .blue: digit = 6
            case .yellow: digit = 7
            case .pink: digit = 8
            }
            return UUID(uuidString: "A495BB\(digit)0-C5B1-4B44-B512-1370F02D74DE")!
        }

        public init?(uuid: UUID) {
            guard let match = Color.allCases.first(where: { $0.uuid == uuid }) else { return nil }
            self = match
        }
    }

    public struct Reading: Hashable, Sendable {
        public var color: Color
        public var gravity: Double
        public var temperatureC: Double
        public var isPro: Bool
        public var date: Date
    }

    /// Decodes an iBeacon's major/minor values. Returns nil for values that can't be a Tilt reading.
    public static func reading(color: Color, major: Int, minor: Int, date: Date = Date()) -> Reading? {
        // Gravity × 10,000 (≥ 5,000) means a Tilt Pro; a standard Tilt sends gravity × 1,000.
        let isPro = minor >= 5000
        let gravity = Double(minor) / (isPro ? 10_000 : 1000)
        let temperatureF = Double(major) / (isPro ? 10 : 1)
        // Tilts send placeholder values (e.g. 999 °F) while starting up; ignore anything implausible.
        guard (0.98...1.2).contains(gravity), (25...140).contains(temperatureF) else { return nil }
        return Reading(color: color, gravity: gravity, temperatureC: BrewMath.fToC(temperatureF), isPro: isPro, date: date)
    }

    /// A brew log entry for this reading, with an optional calibration offset (e.g. from a water test).
    public static func gravityReading(_ reading: Reading, offset: Double = 0) -> GravityReading {
        GravityReading(date: reading.date, gravity: reading.gravity + offset, tempC: reading.temperatureC,
                       note: "Tilt \(reading.color.displayName)\(reading.isPro ? " Pro" : "")")
    }
}
