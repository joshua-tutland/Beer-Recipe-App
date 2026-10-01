import SwiftUI
import BrewCore

/// Live readings from every Tilt in range, with calibration.
struct TiltLiveView: View {
    @Environment(TiltMonitor.self) private var tilts
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    @State private var offsets: [Tilt.Color: Double] = [:]

    var body: some View {
        Form {
            if let problem = tilts.problem {
                Section { Label(problem, systemImage: "location.slash").foregroundStyle(.orange) }
            }
            Section {
                if tilts.activeReadings.isEmpty {
                    HStack(spacing: 12) {
                        if tilts.isScanning { ProgressView() }
                        Text(tilts.isScanning ? "Looking for Tilts… Keep the phone within Bluetooth range."
                                              : "Not scanning.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(tilts.activeReadings, id: \.color) { reading in
                    TiltReadingRow(reading: reading, offset: offsets[reading.color] ?? 0, units: units)
                }
            } header: {
                Text("In Range")
            } footer: {
                Text("Readings update while this screen is open. To log them, open a brew in the brew log and tap Log Tilt Reading.")
            }
            Section {
                ForEach(tilts.activeReadings, id: \.color) { reading in
                    NumberField(label: "\(reading.color.displayName) offset",
                                value: Binding(get: { (offsets[reading.color] ?? 0) * 1000 },
                                               set: {
                                                   offsets[reading.color] = $0 / 1000
                                                   TiltCalibration.setOffset($0 / 1000, for: reading.color)
                                               }),
                                unit: "pts", digits: 1)
                }
            } header: {
                Text("Calibration")
            } footer: {
                Text("Float the Tilt in plain water at room temperature. If it reads 1.002, enter −2 points.")
            }
        }
        .navigationTitle("Tilt Hydrometer")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .onAppear {
            tilts.start()
            for color in Tilt.Color.allCases { offsets[color] = TiltCalibration.offset(for: color) }
        }
        .onDisappear { tilts.stop() }
    }
}

struct TiltReadingRow: View {
    let reading: Tilt.Reading
    let offset: Double
    let units: UnitSystem

    var body: some View {
        HStack {
            Circle().fill(swatch).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tilt \(reading.color.displayName)\(reading.isPro ? " Pro" : "")")
                Text("Updated \(reading.date.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: reading.isPro ? "%.4f" : "%.3f", reading.gravity + offset))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(units.formatTemperature(celsius: reading.temperatureC))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var swatch: Color {
        switch reading.color {
        case .red: return .red
        case .green: return .green
        case .black: return .black
        case .purple: return .purple
        case .orange: return .orange
        case .blue: return .blue
        case .yellow: return .yellow
        case .pink: return .pink
        }
    }
}

/// Brew log row: shows the live Tilt reading and logs it into the session.
struct TiltLogSection: View {
    @Binding var session: BrewSession
    @Environment(TiltMonitor.self) private var tilts
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    @AppStorage("brewLogTiltColor") private var preferredColor = Tilt.Color.red.rawValue

    var body: some View {
        Section {
            let active = tilts.activeReadings
            if let problem = tilts.problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            } else if active.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking for a Tilt…").foregroundStyle(.secondary)
                }
            } else {
                let reading = active.first { $0.color.rawValue == preferredColor } ?? active[0]
                if active.count > 1 {
                    Picker("Tilt", selection: $preferredColor) {
                        ForEach(active, id: \.color) { Text($0.color.displayName).tag($0.color.rawValue) }
                    }
                }
                let offset = TiltCalibration.offset(for: reading.color)
                TiltReadingRow(reading: reading, offset: offset, units: units)
                Button("Log Tilt Reading", systemImage: "plus.circle.fill") {
                    session.readings.append(Tilt.gravityReading(reading, offset: offset))
                }
            }
        } header: {
            Text("Tilt Hydrometer")
        }
        .onAppear { tilts.start() }
        .onDisappear { tilts.stop() }
    }
}
