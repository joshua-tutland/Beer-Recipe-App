import CoreLocation
import Foundation
import Observation
import BrewCore

/// Listens for Tilt hydrometers. Tilts broadcast iBeacons, which iOS only exposes through
/// Core Location beacon ranging, so this needs "When In Use" location permission and works while
/// the app is open.
@Observable
final class TiltMonitor: NSObject, CLLocationManagerDelegate {
    private(set) var readings: [Tilt.Color: Tilt.Reading] = [:]
    private(set) var isScanning = false
    private(set) var problem: String?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var listeners = 0

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Call when a screen that shows Tilt readings appears; pair with `stop()`.
    func start() {
        listeners += 1
        guard listeners == 1 else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginRanging()
        default:
            problem = "Allow location access for Brew Recipes in the Settings app. iOS only shares Tilt broadcasts with apps that have it."
        }
    }

    func stop() {
        listeners = max(0, listeners - 1)
        guard listeners == 0, isScanning else { return }
        for color in Tilt.Color.allCases {
            manager.stopRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: color.uuid))
        }
        isScanning = false
    }

    /// Readings sorted by color, freshest data only (seen in the last 5 minutes).
    var activeReadings: [Tilt.Reading] {
        let cutoff = Date().addingTimeInterval(-300)
        return Tilt.Color.allCases.compactMap { readings[$0] }.filter { $0.date > cutoff }
    }

    private func beginRanging() {
        guard CLLocationManager.isRangingAvailable() else {
            problem = "This device can't detect Bluetooth beacons."
            return
        }
        problem = nil
        for color in Tilt.Color.allCases {
            manager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: color.uuid))
        }
        isScanning = true
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if listeners > 0 && !isScanning { beginRanging() }
        case .denied, .restricted:
            problem = "Allow location access for Brew Recipes in the Settings app. iOS only shares Tilt broadcasts with apps that have it."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon],
                         satisfying constraint: CLBeaconIdentityConstraint) {
        for beacon in beacons {
            guard let color = Tilt.Color(uuid: beacon.uuid),
                  let reading = Tilt.reading(color: color, major: beacon.major.intValue, minor: beacon.minor.intValue)
            else { continue }
            readings[color] = reading
        }
    }
}

/// Per-color calibration offsets (gravity points to add), set from a water test.
enum TiltCalibration {
    static func offset(for color: Tilt.Color) -> Double {
        UserDefaults.standard.double(forKey: "tiltOffset.\(color.rawValue)")
    }

    static func setOffset(_ value: Double, for color: Tilt.Color) {
        UserDefaults.standard.set(value, forKey: "tiltOffset.\(color.rawValue)")
    }
}
