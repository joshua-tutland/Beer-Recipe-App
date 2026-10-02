import SwiftUI
import BrewCore

/// Design and print bottle labels for a recipe.
struct LabelDesignerView: View {
    let recipe: Recipe

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var tagline = ""
    @State private var sessionID: UUID?
    @State private var options = BottleLabel.Options()
    @State private var sheet = LabelSheet.avery5163
    @State private var count = 10
    @State private var cutGuides = true
    @State private var shareItem: ShareItem?
    @State private var error: String?

    init(recipe: Recipe) {
        self.recipe = recipe
        _title = State(initialValue: recipe.name)
        _sessionID = State(initialValue: recipe.sessions.first?.id)
    }

    private var label: BottleLabel {
        BottleLabel.make(recipe: recipe, session: recipe.sessions.first { $0.id == sessionID },
                         title: title, tagline: tagline, options: options)
    }

    var body: some View {
        Form {
            Section {
                Image(uiImage: LabelRenderer.image(label, sheet: sheet))
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                    .padding(.vertical, 4)
                    .accessibilityLabel("Label preview")
            }
            Section("Text") {
                TextField("Beer name", text: $title)
                TextField("Tagline (optional)", text: $tagline)
                if !recipe.sessions.isEmpty {
                    Picker("Batch", selection: $sessionID) {
                        Text("None").tag(UUID?.none)
                        ForEach(recipe.sessions) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            Section {
                Toggle("Style", isOn: $options.showStyle)
                Toggle("ABV", isOn: $options.showABV)
                Toggle("IBU", isOn: $options.showIBU)
                Toggle("Color (SRM)", isOn: $options.showColor)
                if sessionID != nil { Toggle("Brew & Bottling Dates", isOn: $options.showDate) }
            } header: {
                Text("Show")
            } footer: {
                Text("ABV uses the batch's measured gravities when both OG and FG are logged; otherwise it's the recipe estimate.")
            }
            Section("Print") {
                Picker("Label Stock", selection: $sheet) {
                    ForEach(LabelSheet.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper("Labels: \(count)", value: $count, in: 1...120)
                Toggle("Cut Guides", isOn: $cutGuides)
                Button("Create PDF", systemImage: "printer") { exportPDF() }
            }
        }
        .navigationTitle("Bottle Labels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .onChange(of: sheet) { _, newSheet in count = newSheet.perSheet }
        .sheet(item: $shareItem) { ActivityView(items: [$0.url]) }
        .alert("Couldn't Create Labels", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func exportPDF() {
        let data = LabelRenderer.pdf(label, sheet: sheet, count: count, cutGuides: cutGuides)
        do {
            let folder = RecipeExporter.exportDirectory
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(RecipeExporter.safeFileName("\(label.title) Labels"))
                .appendingPathExtension("pdf")
            try data.write(to: url, options: [.atomic])
            shareItem = ShareItem(url: url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
