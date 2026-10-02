import Foundation

/// What the Home Screen and Lock Screen widgets show: batches that are fermenting, with their
/// latest gravity and what's due next.
///
/// The app writes this to a folder shared with the widget extension (an App Group), because a
/// widget can't read the app's own files.
public struct BrewingSnapshot: Codable, Hashable, Sendable {
    public struct Milestone: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case dryHop, checkFinalGravity, package
        }

        public var kind: Kind
        public var title: String
        public var date: Date

        public init(kind: Kind, title: String, date: Date) {
            self.kind = kind
            self.title = title
            self.date = date
        }
    }

    public struct Batch: Codable, Hashable, Identifiable, Sendable {
        /// The brew session's id.
        public var id: UUID
        public var recipeID: UUID
        public var recipeName: String
        public var batchName: String
        public var brewDate: Date
        public var og: Double
        /// The recipe's predicted final gravity.
        public var targetFG: Double
        public var latestGravity: Double?
        public var latestReadingDate: Date?
        /// Set once the final gravity is recorded: the batch is ready to package.
        public var fg: Double?
        public var srm: Double
        /// Things still to do, earliest first.
        public var milestones: [Milestone]

        public init(id: UUID, recipeID: UUID, recipeName: String, batchName: String, brewDate: Date,
                    og: Double, targetFG: Double, latestGravity: Double? = nil, latestReadingDate: Date? = nil,
                    fg: Double? = nil, srm: Double, milestones: [Milestone] = []) {
            self.id = id
            self.recipeID = recipeID
            self.recipeName = recipeName
            self.batchName = batchName
            self.brewDate = brewDate
            self.og = og
            self.targetFG = targetFG
            self.latestGravity = latestGravity
            self.latestReadingDate = latestReadingDate
            self.fg = fg
            self.srm = srm
            self.milestones = milestones
        }

        /// Days since brew day (brew day is day 0).
        public func day(on date: Date, calendar: Calendar = .current) -> Int {
            let start = calendar.startOfDay(for: brewDate)
            let end = calendar.startOfDay(for: date)
            return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
        }

        public var currentGravity: Double { fg ?? latestGravity ?? og }

        public var abvSoFar: Double { BrewMath.abv(og: og, fg: currentGravity) }

        /// How far fermentation has got toward the predicted final gravity (0…1).
        public var progress: Double {
            guard og > targetFG else { return 0 }
            return min(1, max(0, (og - currentGravity) / (og - targetFG)))
        }

        public var isReadyToPackage: Bool { fg != nil }

        /// The next thing to do (it may be overdue).
        public var nextMilestone: Milestone? { milestones.first }
    }

    public var generatedAt: Date
    public var batches: [Batch]
    public var recipeCount: Int
    public var brewsThisYear: Int

    public init(generatedAt: Date = Date(), batches: [Batch] = [], recipeCount: Int = 0, brewsThisYear: Int = 0) {
        self.generatedAt = generatedAt
        self.batches = batches
        self.recipeCount = recipeCount
        self.brewsThisYear = brewsThisYear
    }

    /// Batches brewed longer ago than this are treated as forgotten rather than fermenting.
    public static let staleAfterDays = 120
    public static let maxBatches = 8

    /// Builds the snapshot from the recipe library.
    ///
    /// A batch counts as fermenting once its OG is logged and until it's packaged. Milestones come
    /// from the recipe's fermentation schedule: dry hops on the days the brew-day checklist lists,
    /// the final gravity check at the end of primary, and packaging after any secondary. Steps
    /// ticked off in the checklist are left out.
    public static func make(recipes: [Recipe], units: UnitSystem, now: Date = Date(),
                            calendar: Calendar = .current) -> BrewingSnapshot {
        let year = calendar.component(.year, from: now)
        var brewsThisYear = 0
        var batches: [Batch] = []

        for recipe in recipes {
            let stats = recipe.stats
            for session in recipe.sessions {
                if calendar.component(.year, from: session.brewDate) == year { brewsThisYear += 1 }
                guard let og = session.og, session.packagedDate == nil else { continue }
                let age = calendar.dateComponents([.day], from: session.brewDate, to: now).day ?? 0
                guard age <= staleAfterDays else { continue }

                let latest = session.readings.max { $0.date < $1.date }
                batches.append(Batch(
                    id: session.id, recipeID: recipe.id,
                    recipeName: recipe.name.isEmpty ? "Untitled" : recipe.name,
                    batchName: session.name, brewDate: session.brewDate, og: og,
                    targetFG: session.plan.fg, latestGravity: latest?.gravity, latestReadingDate: latest?.date,
                    fg: session.fg, srm: stats.srm,
                    milestones: milestones(for: session, recipe: recipe, units: units, calendar: calendar)))
            }
        }
        batches.sort { $0.brewDate > $1.brewDate }
        return BrewingSnapshot(generatedAt: now, batches: Array(batches.prefix(maxBatches)),
                               recipeCount: recipes.count, brewsThisYear: brewsThisYear)
    }

    static func milestones(for session: BrewSession, recipe: Recipe, units: UnitSystem,
                           calendar: Calendar) -> [Milestone] {
        let start = calendar.startOfDay(for: session.brewDate)
        func day(_ n: Double) -> Date {
            calendar.date(byAdding: .day, value: Int(n.rounded()), to: start) ?? start
        }
        let primary = recipe.fermentation.primaryDays
        var result: [Milestone] = []

        for hop in recipe.hops where hop.use == .dryHop && !session.isStepDone("dryhop-\(hop.id.uuidString)") {
            result.append(Milestone(kind: .dryHop,
                                    title: "Dry hop \(units.formatSmallWeight(grams: hop.amountGrams)) \(hop.hop.name)",
                                    date: day(max(0, primary - hop.time))))
        }
        if session.fg == nil && !session.isStepDone("measure-fg") {
            result.append(Milestone(kind: .checkFinalGravity, title: "Check final gravity", date: day(primary)))
        }
        result.append(Milestone(kind: .package, title: "Package",
                                date: day(primary + recipe.fermentation.secondaryDays)))
        // Stable order: by date, then dry hops before the gravity check before packaging.
        let order: [Milestone.Kind: Int] = [.dryHop: 0, .checkFinalGravity: 1, .package: 2]
        return result.sorted { ($0.date, order[$0.kind] ?? 0) < ($1.date, order[$1.kind] ?? 0) }
    }

    /// The same content, ignoring when it was generated (to skip needless widget reloads).
    public func hasSameContent(as other: BrewingSnapshot) -> Bool {
        var a = self
        var b = other
        a.generatedAt = .distantPast
        b.generatedAt = .distantPast
        return a == b
    }

    // MARK: Shared file

    public static let fileName = "brewing-snapshot.json"

    /// Where the snapshot lives in the App Group container, or nil if the App Group isn't set up
    /// (for example when the app was signed without the App Groups capability).
    public static func sharedFileURL(appGroup: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) -> BrewingSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BrewingSnapshot.self, from: data)
    }
}
