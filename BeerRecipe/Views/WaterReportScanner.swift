import SwiftUI
import PhotosUI
import Vision
import BrewCore

/// Reads the text in a photo with Apple's on-device text recognition.
enum TextRecognizer {
    /// Recognized text with words on the same row of a table joined into one line, top to bottom.
    static func lines(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false  // keeps chemical symbols like SO4 intact
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            return TextRecognizer.joinRows(request.results ?? [])
        }.value
    }

    /// Groups text boxes whose vertical centers line up into rows, then reads each row left to
    /// right. Water reports are mostly tables, where Vision returns each cell separately.
    static func joinRows(_ observations: [VNRecognizedTextObservation]) -> String {
        struct Cell { var text: String; var box: CGRect }
        let cells = observations.compactMap { o in
            o.topCandidates(1).first.map { Cell(text: $0.string, box: o.boundingBox) }
        }
        // Vision's coordinates start at the bottom left, so higher midY is nearer the top.
        let sorted = cells.sorted { $0.box.midY > $1.box.midY }
        var rows: [[Cell]] = []
        for cell in sorted {
            if let last = rows.last?.first, abs(last.box.midY - cell.box.midY) < max(last.box.height, cell.box.height) * 0.5 {
                rows[rows.count - 1].append(cell)
            } else {
                rows.append([cell])
            }
        }
        return rows
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ") }
            .joined(separator: "\n")
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// The system camera, for photographing a printed report.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

/// Fill in a water profile from a photo, screenshot or pasted text of a water report.
struct WaterReportImportView: View {
    let base: WaterProfile
    let onUse: (WaterProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var text = ""
    @State private var working = false
    @State private var errorMessage: String?
    @State private var profile: WaterProfile?
    @State private var parsed: WaterReportParser.Result?

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose Photo or Screenshot", systemImage: "photo.on.rectangle")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo", systemImage: "camera") { showCamera = true }
                }
                if working {
                    HStack {
                        ProgressView()
                        Text("Reading the report…").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Scan")
            } footer: {
                Text("Photograph the table of minerals, flat and well lit. Text is read on your device; nothing is uploaded.")
            }

            Section {
                TextField("Or paste the report's text here", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .font(.caption.monospaced())
                Button("Read Text", systemImage: "text.viewfinder") { read(text) }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Text")
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.orange)
                }
            }

            if let parsed, profile != nil {
                resultSection(parsed)
            }
        }
        .navigationTitle("Import Water Report")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Use") {
                    if let profile { onUse(profile) }
                    dismiss()
                }
                .disabled(profile == nil)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(isPresented: $showCamera) { image in Task { await recognize(image) } }
                .ignoresSafeArea()
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await recognize(image)
                } else {
                    errorMessage = "Couldn't open that image."
                }
            }
        }
    }

    @ViewBuilder
    private func resultSection(_ parsed: WaterReportParser.Result) -> some View {
        Section {
            ForEach(Ion.allCases) { ion in
                let found = parsed.ions[ion] != nil
                HStack {
                    NumberField(label: "\(ion.displayName) (\(ion.symbol))",
                                value: Binding(get: { profile?[ion] ?? 0 },
                                               set: { profile?[ion] = max(0, $0) }),
                                unit: "ppm", digits: 1)
                    Image(systemName: found ? "checkmark.circle.fill" : "questionmark.circle")
                        .foregroundStyle(found ? Color.green : Color.orange)
                }
            }
            if let pH = parsed.pH {
                LabeledContent("pH", value: UnitSystem.number(pH, digits: 1))
            }
        } header: {
            Text("Found \(parsed.ions.count) of \(Ion.allCases.count)")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Check each value against the report. Values marked ? weren't found and keep what you had before.")
                if parsed.bicarbonateFromAlkalinity {
                    Text("Bicarbonate was worked out from total alkalinity as CaCO₃ (× 1.22).")
                }
                if !parsed.rangedIons.isEmpty {
                    Text("\(parsed.rangedIons.map(\.displayName).sorted().joined(separator: ", ")) used the middle of a range.")
                }
                if let profile, profile.ionBalanceError > 10 {
                    Text("The ions don't balance (\(Int(profile.ionBalanceError))% off), so a value may have been misread.")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func recognize(_ image: UIImage) async {
        working = true
        errorMessage = nil
        defer { working = false }
        do {
            let recognized = try await TextRecognizer.lines(in: image)
            text = recognized
            read(recognized)
        } catch {
            errorMessage = "Couldn't read text from the image: \(error.localizedDescription)"
        }
    }

    private func read(_ text: String) {
        let result = WaterReportParser.parse(text)
        if result.isEmpty {
            errorMessage = "No mineral values found. Try a closer, straighter photo, or type the values in."
            parsed = nil
            profile = nil
        } else {
            errorMessage = nil
            parsed = result
            profile = result.applied(to: base)
        }
    }
}
