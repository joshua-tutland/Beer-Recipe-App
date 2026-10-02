import XCTest
@testable import BrewCore

final class TiltTests: XCTestCase {
    func testColorUUIDs() {
        XCTAssertEqual(Tilt.Color.red.uuid.uuidString, "A495BB10-C5B1-4B44-B512-1370F02D74DE")
        XCTAssertEqual(Tilt.Color.pink.uuid.uuidString, "A495BB80-C5B1-4B44-B512-1370F02D74DE")
        XCTAssertEqual(Set(Tilt.Color.allCases.map(\.uuid)).count, 8)
        XCTAssertEqual(Tilt.Color(uuid: Tilt.Color.blue.uuid), .blue)
        XCTAssertNil(Tilt.Color(uuid: UUID()))
    }

    func testStandardTilt() throws {
        let r = try XCTUnwrap(Tilt.reading(color: .red, major: 68, minor: 1050))
        XCTAssertEqual(r.gravity, 1.050, accuracy: 0.00001)
        XCTAssertEqual(r.temperatureC, 20, accuracy: 0.001)
        XCTAssertFalse(r.isPro)
    }

    func testTiltPro() throws {
        let r = try XCTUnwrap(Tilt.reading(color: .green, major: 684, minor: 10123))
        XCTAssertEqual(r.gravity, 1.0123, accuracy: 0.00001)
        XCTAssertEqual(r.temperatureC, BrewMath.fToC(68.4), accuracy: 0.001)
        XCTAssertTrue(r.isPro)
    }

    func testIgnoresStartupPlaceholders() {
        XCTAssertNil(Tilt.reading(color: .red, major: 999, minor: 1050))
        XCTAssertNil(Tilt.reading(color: .red, major: 68, minor: 0))
    }

    func testBrewLogReadingWithCalibration() throws {
        let r = try XCTUnwrap(Tilt.reading(color: .purple, major: 64, minor: 1012))
        let logged = Tilt.gravityReading(r, offset: -0.002)
        XCTAssertEqual(logged.gravity, 1.010, accuracy: 0.00001)
        XCTAssertEqual(logged.note, "Tilt Purple")
        XCTAssertEqual(logged.tempC ?? 0, r.temperatureC, accuracy: 0.0001)
    }
}
