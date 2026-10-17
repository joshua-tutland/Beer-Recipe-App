import SwiftUI
import WidgetKit
import BrewCore

// MARK: - Timeline

struct FermentationEntry: TimelineEntry {
    let date: Date
    /// nil when the app hasn't shared anything yet (or the App Group isn't set up).
    let snapshot: BrewingSnapshot?
}

struct FermentationProvider: TimelineProvider {
    func placeholder(in context: Context) -> FermentationEntry {
        FermentationEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (FermentationEntry) -> Void) {
        let saved = load()
        // The widget gallery shows example batches when there's nothing real to show.
        let useSample = context.isPreview && (saved?.batches.isEmpty ?? true)
        completion(FermentationEntry(date: Date(), snapshot: useSample ? .sample : saved))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FermentationEntry>) -> Void) {
        let snapshot = load()
        // The data only changes when the app writes a new snapshot (and reloads the widget), but
        // "Day 6" and "Tomorrow" change at midnight, so add an entry for each of the next days.
        let calendar = Calendar.current
        let now = Date()
        var dates = [now]
        var midnight = calendar.startOfDay(for: now)
        for _ in 0..<7 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: midnight) else { break }
            midnight = next
            dates.append(next)
        }
        completion(Timeline(entries: dates.map { FermentationEntry(date: $0, snapshot: snapshot) }, policy: .atEnd))
    }

    private func load() -> BrewingSnapshot? {
        guard let group = AppGroup.identifier,
              let url = BrewingSnapshot.sharedFileURL(appGroup: group) else { return nil }
        return BrewingSnapshot.read(from: url)
    }
}

// MARK: - Widget

struct FermentationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.fermentationWidgetKind, provider: FermentationProvider()) { entry in
            FermentationWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fermenting")
        .description("Days in, latest gravity and what's due next for each batch.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct FermentationWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FermentationEntry

    private var batches: [BrewingSnapshot.Batch] { entry.snapshot?.batches ?? [] }

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .systemMedium: list(limit: 2)
        case .systemLarge: list(limit: 4)
        default: small
        }
    }

    // MARK: Home Screen

    @ViewBuilder
    private var small: some View {
        if let batch = batches.first {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    BeerDot(srm: batch.srm)
                    Text(batch.recipeName).font(.headline).lineLimit(1)
                }
                Text("Day \(batch.day(on: entry.date))\(batches.count > 1 ? " · +\(batches.count - 1) more" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(gravity(batch.currentGravity))
                    .font(.title.weight(.semibold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                ProgressView(value: batch.progress).tint(Color.widgetAmber)
                NextUp(batch: batch, now: entry.date, compact: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(AppGroup.recipeURL(batch.recipeID))
        } else {
            EmptyFermentation(snapshot: entry.snapshot)
        }
    }

    @ViewBuilder
    private func list(limit: Int) -> some View {
        if batches.isEmpty {
            EmptyFermentation(snapshot: entry.snapshot)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Fermenting", systemImage: "drop.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.widgetAmber)
                    Spacer()
                    if batches.count > limit {
                        Text("+\(batches.count - limit) more").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ForEach(batches.prefix(limit)) { batch in
                    Link(destination: AppGroup.recipeURL(batch.recipeID)) {
                        BatchRow(batch: batch, now: entry.date)
                    }
                }
                Spacer(minLength: 0)
                if family == .systemLarge, let snapshot = entry.snapshot {
                    Text("\(snapshot.brewsThisYear) brew\(snapshot.brewsThisYear == 1 ? "" : "s") this year · \(snapshot.recipeCount) recipes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Lock Screen

    @ViewBuilder
    private var rectangular: some View {
        if let batch = batches.first {
            VStack(alignment: .leading, spacing: 1) {
                Text(batch.recipeName).font(.headline).lineLimit(1).widgetAccentable()
                Text("Day \(batch.day(on: entry.date)) · \(gravity(batch.currentGravity)) · \(abv(batch))")
                    .font(.caption.monospacedDigit())
                NextUp(batch: batch, now: entry.date, compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(AppGroup.recipeURL(batch.recipeID))
        } else {
            Label("Nothing fermenting", systemImage: "drop")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let batch = batches.first {
            Gauge(value: batch.progress) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text("D\(batch.day(on: entry.date))").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .widgetURL(AppGroup.recipeURL(batch.recipeID))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "drop")
            }
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let batch = batches.first {
            Label("\(batch.recipeName) · Day \(batch.day(on: entry.date)) · \(gravity(batch.currentGravity))",
                  systemImage: "drop.fill")
        } else {
            Label("Nothing fermenting", systemImage: "drop")
        }
    }
}

// MARK: - Pieces

private func gravity(_ sg: Double) -> String { String(format: "%.3f", sg) }
private func abv(_ batch: BrewingSnapshot.Batch) -> String { String(format: "%.1f%%", batch.abvSoFar) }

/// "Today", "Tomorrow", "In 3 days" or "Overdue" for a milestone date.
private func dueText(_ date: Date, now: Date) -> String {
    let calendar = Calendar.current
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: date)).day ?? 0
    switch days {
    case ..<0: return "Overdue"
    case 0: return "Today"
    case 1: return "Tomorrow"
    default: return "In \(days) days"
    }
}

private struct NextUp: View {
    let batch: BrewingSnapshot.Batch
    let now: Date
    var compact = false

    var body: some View {
        if batch.isReadyToPackage {
            Label("Ready to package", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .lineLimit(1)
        } else if let next = batch.nextMilestone {
            let due = dueText(next.date, now: now)
            (Text("\(due): ").bold() + Text(next.title))
                .font(.caption2)
                .foregroundStyle(due == "Overdue" || due == "Today" ? Color.orange : Color.secondary)
                .lineLimit(compact ? 1 : 2)
        }
    }
}

private struct BatchRow: View {
    let batch: BrewingSnapshot.Batch
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            BeerDot(srm: batch.srm).padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(batch.recipeName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(gravity(batch.currentGravity)).font(.subheadline.weight(.semibold).monospacedDigit())
                }
                HStack {
                    Text("Day \(batch.day(on: now)) · \(abv(batch)) so far")
                    Spacer()
                    Text("\(Int((batch.progress * 100).rounded()))%")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                ProgressView(value: batch.progress).tint(Color.widgetAmber)
                NextUp(batch: batch, now: now)
            }
        }
    }
}

private struct BeerDot: View {
    let srm: Double

    var body: some View {
        let rgb = BrewMath.srmToRGB(srm)
        Circle()
            .fill(Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255))
            .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
            .frame(width: 12, height: 12)
    }
}

private struct EmptyFermentation: View {
    let snapshot: BrewingSnapshot?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "drop")
                .font(.title2)
                .foregroundStyle(Color.widgetAmber)
            Text(snapshot == nil ? "Open Brew Recipes" : "Nothing fermenting")
                .font(.headline)
            Text(snapshot == nil
                 ? "Batches appear here once the app has shared them."
                 : "Log an OG in a brew day to follow it here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Color {
    static let widgetAmber = Color(red: 0.80, green: 0.52, blue: 0.13)
}

// MARK: - Sample data for the widget gallery

extension BrewingSnapshot {
    static var sample: BrewingSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: today) ?? today }
        return BrewingSnapshot(
            batches: [
                Batch(id: UUID(), recipeID: UUID(), recipeName: "Hazy IPA", batchName: "Batch 3",
                      brewDate: day(-6), og: 1.064, targetFG: 1.014, latestGravity: 1.022,
                      latestReadingDate: day(0), fg: nil, srm: 4.5,
                      milestones: [Milestone(kind: .dryHop, title: "Dry hop 75 g Citra", date: day(1)),
                                   Milestone(kind: .checkFinalGravity, title: "Check final gravity", date: day(8))]),
                Batch(id: UUID(), recipeID: UUID(), recipeName: "Irish Stout", batchName: "Batch 1",
                      brewDate: day(-12), og: 1.042, targetFG: 1.010, latestGravity: 1.011,
                      latestReadingDate: day(-1), fg: nil, srm: 38,
                      milestones: [Milestone(kind: .checkFinalGravity, title: "Check final gravity", date: day(2))]),
            ],
            recipeCount: 12, brewsThisYear: 9)
    }
}
