import SwiftUI
import BrewCore

/// Checks the recipe against its style and offers one-tap fixes for anything out of range.
struct StyleSuggestionsSection: View {
    @Binding var recipe: Recipe
    let units: UnitSystem

    /// Fixes only change fermentables and hops; this keeps both sides of the last fix so it can be
    /// undone, as long as nothing else has changed them since.
    private struct Fix: Equatable {
        var fermentablesBefore: [FermentableAddition]
        var hopsBefore: [HopAddition]
        var fermentablesAfter: [FermentableAddition]
        var hopsAfter: [HopAddition]
    }
    @State private var lastFix: Fix?

    var body: some View {
        if let style = recipe.style {
            let suggestions = StyleAdvisor.suggestions(for: recipe, style: style, units: units)
            Section {
                if suggestions.isEmpty {
                    Label("Everything is within \(style.name) ranges.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                ForEach(suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(suggestion.problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                        Text(suggestion.advice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let action = suggestion.action, let title = suggestion.actionTitle {
                            Button(title) {
                                var fixed = recipe
                                fixed.apply(action)
                                lastFix = Fix(fermentablesBefore: recipe.fermentables, hopsBefore: recipe.hops,
                                              fermentablesAfter: fixed.fermentables, hopsAfter: fixed.hops)
                                withAnimation { recipe = fixed }
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.brewAmber)
                            .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.vertical, 2)
                }
                if let fix = lastFix, recipe.fermentables == fix.fermentablesAfter, recipe.hops == fix.hopsAfter {
                    Button("Undo Last Fix", systemImage: "arrow.uturn.backward") {
                        withAnimation {
                            recipe.fermentables = fix.fermentablesBefore
                            recipe.hops = fix.hopsBefore
                        }
                        lastFix = nil
                    }
                    .font(.caption)
                }
            } header: {
                Text("Style Check")
            } footer: {
                if !suggestions.isEmpty {
                    Text("Fixes aim a little inside the style's range. Apply one at a time: changing the grain also shifts color and bitterness.")
                }
            }
        }
    }
}
