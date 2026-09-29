import SwiftUI
import UIKit
import BrewCore

extension Color {
    static let brewAmber = Color(red: 0.80, green: 0.52, blue: 0.13)

    init(srm: Double) {
        let c = BrewMath.srmToRGB(srm)
        self.init(red: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255)
    }
}

extension Binding where Value == Double {
    /// Presents a stored (metric) value in display units.
    func converted(_ toDisplay: @escaping (Double) -> Double, _ fromDisplay: @escaping (Double) -> Double) -> Binding<Double> {
        Binding(get: { toDisplay(wrappedValue) }, set: { wrappedValue = fromDisplay($0) })
    }
}

/// A labelled numeric text field with a trailing unit.
struct NumberField: View {
    let label: String
    @Binding var value: Double
    var unit: String = ""
    var digits: Int = 2

    var body: some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            TextField(label, value: $value, format: .number.precision(.fractionLength(0...digits)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
        }
    }
}

/// A beer-colored glass swatch.
struct BeerSwatch: View {
    let srm: Double
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22)
            .fill(Color(srm: srm))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.22)
                    .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
            )
            .frame(width: size * 0.8, height: size)
            .accessibilityLabel("Color \(Int(srm.rounded())) SRM")
    }
}

/// Wraps `UIActivityViewController` so exported files can be shared, saved to Files, AirDropped, printed…
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

extension View {
    /// Adds a "Done" button above the decimal keyboard (which has no return key).
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}
