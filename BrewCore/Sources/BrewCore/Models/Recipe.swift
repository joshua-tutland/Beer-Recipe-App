import Foundation

public enum RecipeType: String, Codable, CaseIterable, Sendable {
    case allGrain, partialMash, extract

    public var displayName: String {
        switch self {
        case .allGrain: return "All Grain"
        case .partialMash: return "Partial Mash"
        case .extract: return "Extract"
        }
    }
}

public struct FermentableAddition: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var fermentable: Fermentable
    public var amountKg: Double

    public init(id: UUID = UUID(), fermentable: Fermentable, amountKg: Double) {
        self.id = id
        self.fermentable = fermentable
        self.amountKg = amountKg
    }
}

public struct HopAddition: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var hop: Hop
    public var amountGrams: Double
    /// Alpha acid of the actual lot being used (defaults to the hop's typical value).
    public var alphaAcid: Double
    public var use: HopUse
    /// Minutes for boil / first wort / whirlpool / mash, days for dry hop.
    public var time: Double
    public var form: HopForm
    /// Whirlpool / hop stand temperature.
    public var whirlpoolTempC: Double

    public init(id: UUID = UUID(),
                hop: Hop,
                amountGrams: Double,
                alphaAcid: Double? = nil,
                use: HopUse = .boil,
                time: Double = 60,
                form: HopForm = .pellet,
                whirlpoolTempC: Double = 80) {
        self.id = id
        self.hop = hop
        self.amountGrams = amountGrams
        self.alphaAcid = alphaAcid ?? hop.alphaAcid
        self.use = use
        self.time = time
        self.form = form
        self.whirlpoolTempC = whirlpoolTempC
    }
}

public struct YeastAddition: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var yeast: Yeast
    /// Expected apparent attenuation, percent (defaults to the strain's average).
    public var attenuation: Double
    /// Number of packs / vials / grams-equivalent packs pitched.
    public var packs: Double

    public init(id: UUID = UUID(), yeast: Yeast, attenuation: Double? = nil, packs: Double = 1) {
        self.id = id
        self.yeast = yeast
        self.attenuation = attenuation ?? yeast.averageAttenuation
        self.packs = packs
    }
}

public struct MiscAddition: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var misc: Misc
    public var amount: Double
    public var unit: String
    public var use: MiscUse
    public var timeMinutes: Double

    public init(id: UUID = UUID(), misc: Misc, amount: Double, unit: String? = nil, use: MiscUse? = nil, timeMinutes: Double = 0) {
        self.id = id
        self.misc = misc
        self.amount = amount
        self.unit = unit ?? misc.defaultUnit
        self.use = use ?? misc.defaultUse
        self.timeMinutes = timeMinutes
    }
}

public enum MashStepType: String, Codable, CaseIterable, Sendable {
    case infusion, temperature, decoction

    public var displayName: String { rawValue.capitalized }
}

public struct MashStep: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var type: MashStepType
    public var tempC: Double
    public var minutes: Double

    public init(id: UUID = UUID(), name: String, type: MashStepType = .infusion, tempC: Double, minutes: Double) {
        self.id = id
        self.name = name
        self.type = type
        self.tempC = tempC
        self.minutes = minutes
    }
}

/// Brewhouse / process settings used by the calculator.
/// How the mash is lautered.
public enum MashMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Mash at a set thickness, then rinse with sparge water (three-vessel, most all-in-ones).
    case sparge
    /// All brewing water goes into the mash and there's no sparge (brew in a bag, no-sparge).
    case fullVolume

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sparge: return "Mash + Sparge"
        case .fullVolume: return "Full Volume (BIAB / No Sparge)"
        }
    }
}

/// Brewhouse / process settings used by the calculator.
public struct Equipment: Codable, Hashable, Sendable {
    /// Volume into the fermenter, liters.
    public var batchSizeL: Double
    public var boilTimeMinutes: Double
    /// Brewhouse efficiency, percent (applies to mashed ingredients).
    public var efficiency: Double
    public var boilOffLPerHour: Double
    /// Kettle trub + chiller loss, liters.
    public var trubLossL: Double
    public var mashTunDeadspaceL: Double
    public var grainAbsorptionLPerKg: Double
    public var mashThicknessLPerKg: Double
    public var grainTempC: Double
    public var mashMethod: MashMethod

    public init(batchSizeL: Double = 20,
                boilTimeMinutes: Double = 60,
                efficiency: Double = 72,
                boilOffLPerHour: Double = 3.5,
                trubLossL: Double = 1.5,
                mashTunDeadspaceL: Double = 0.5,
                grainAbsorptionLPerKg: Double = 1.0,
                mashThicknessLPerKg: Double = 3.0,
                grainTempC: Double = 20,
                mashMethod: MashMethod = .sparge) {
        self.batchSizeL = batchSizeL
        self.boilTimeMinutes = boilTimeMinutes
        self.efficiency = efficiency
        self.boilOffLPerHour = boilOffLPerHour
        self.trubLossL = trubLossL
        self.mashTunDeadspaceL = mashTunDeadspaceL
        self.grainAbsorptionLPerKg = grainAbsorptionLPerKg
        self.mashThicknessLPerKg = mashThicknessLPerKg
        self.grainTempC = grainTempC
        self.mashMethod = mashMethod
    }

    private enum CodingKeys: String, CodingKey {
        case batchSizeL, boilTimeMinutes, efficiency, boilOffLPerHour, trubLossL, mashTunDeadspaceL
        case grainAbsorptionLPerKg, mashThicknessLPerKg, grainTempC, mashMethod
    }

    /// Tolerates missing keys so equipment saved by earlier versions still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Equipment()
        batchSizeL = try c.decodeIfPresent(Double.self, forKey: .batchSizeL) ?? d.batchSizeL
        boilTimeMinutes = try c.decodeIfPresent(Double.self, forKey: .boilTimeMinutes) ?? d.boilTimeMinutes
        efficiency = try c.decodeIfPresent(Double.self, forKey: .efficiency) ?? d.efficiency
        boilOffLPerHour = try c.decodeIfPresent(Double.self, forKey: .boilOffLPerHour) ?? d.boilOffLPerHour
        trubLossL = try c.decodeIfPresent(Double.self, forKey: .trubLossL) ?? d.trubLossL
        mashTunDeadspaceL = try c.decodeIfPresent(Double.self, forKey: .mashTunDeadspaceL) ?? d.mashTunDeadspaceL
        grainAbsorptionLPerKg = try c.decodeIfPresent(Double.self, forKey: .grainAbsorptionLPerKg) ?? d.grainAbsorptionLPerKg
        mashThicknessLPerKg = try c.decodeIfPresent(Double.self, forKey: .mashThicknessLPerKg) ?? d.mashThicknessLPerKg
        grainTempC = try c.decodeIfPresent(Double.self, forKey: .grainTempC) ?? d.grainTempC
        mashMethod = try c.decodeIfPresent(MashMethod.self, forKey: .mashMethod) ?? .sparge
    }

    public var postBoilVolumeL: Double { batchSizeL + trubLossL }
    public var preBoilVolumeL: Double { postBoilVolumeL + boilOffLPerHour * boilTimeMinutes / 60 }
}

/// A saved brewing system (e.g. "Garage BIAB kettle") whose settings new recipes start from.
public struct EquipmentProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var equipment: Equipment
    public var notes: String

    public init(id: UUID = UUID(), name: String, equipment: Equipment, notes: String = "") {
        self.id = id
        self.name = name
        self.equipment = equipment
        self.notes = notes
    }

    /// Typical starting points for common systems. Brewers should measure their own losses.
    public static let presets: [EquipmentProfile] = [
        EquipmentProfile(name: "Three-Vessel (5 gal)",
                         equipment: Equipment(batchSizeL: 20, efficiency: 72, boilOffLPerHour: 3.8, trubLossL: 1.5,
                                              mashTunDeadspaceL: 1.0, grainAbsorptionLPerKg: 1.0, mashThicknessLPerKg: 3.0),
                         notes: "Cooler or kettle mash tun with batch or fly sparging."),
        EquipmentProfile(name: "Brew in a Bag (5 gal)",
                         equipment: Equipment(batchSizeL: 20, efficiency: 68, boilOffLPerHour: 3.8, trubLossL: 1.5,
                                              mashTunDeadspaceL: 0, grainAbsorptionLPerKg: 0.6,
                                              mashThicknessLPerKg: 3.0, mashMethod: .fullVolume),
                         notes: "Full-volume mash in the kettle; squeezing the bag lowers absorption."),
        EquipmentProfile(name: "Grainfather G30",
                         equipment: Equipment(batchSizeL: 23, efficiency: 75, boilOffLPerHour: 2.5, trubLossL: 2.0,
                                              mashTunDeadspaceL: 3.5, grainAbsorptionLPerKg: 0.8, mashThicknessLPerKg: 2.7),
                         notes: "Malt pipe with sparge; dead space is the water below the pipe."),
        EquipmentProfile(name: "BrewZilla 35 L",
                         equipment: Equipment(batchSizeL: 23, efficiency: 70, boilOffLPerHour: 2.5, trubLossL: 2.0,
                                              mashTunDeadspaceL: 4.0, grainAbsorptionLPerKg: 0.8, mashThicknessLPerKg: 3.0),
                         notes: "Malt pipe with sparge."),
        EquipmentProfile(name: "Anvil Foundry 10.5 gal",
                         equipment: Equipment(batchSizeL: 21, efficiency: 70, boilOffLPerHour: 2.8, trubLossL: 1.8,
                                              mashTunDeadspaceL: 0, grainAbsorptionLPerKg: 0.8,
                                              mashThicknessLPerKg: 3.0, mashMethod: .fullVolume),
                         notes: "Usually brewed full volume (no sparge) with the basket.")
    ]
}

public struct Fermentation: Codable, Hashable, Sendable {
    public var primaryTempC: Double
    public var primaryDays: Double
    public var secondaryDays: Double
    public var carbonationVolumes: Double
    /// Highest temperature the beer reached after fermentation (for residual CO2).
    public var bottlingTempC: Double

    public init(primaryTempC: Double = 19, primaryDays: Double = 14, secondaryDays: Double = 0,
                carbonationVolumes: Double = 2.4, bottlingTempC: Double = 20) {
        self.primaryTempC = primaryTempC
        self.primaryDays = primaryDays
        self.secondaryDays = secondaryDays
        self.carbonationVolumes = carbonationVolumes
        self.bottlingTempC = bottlingTempC
    }
}

public enum IBUFormula: String, Codable, CaseIterable, Sendable {
    case tinseth, rager

    public var displayName: String { rawValue.capitalized }
}

public struct Recipe: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var author: String
    public var type: RecipeType
    /// BJCP style code, e.g. "21A".
    public var styleId: String?
    public var createdAt: Date
    public var modifiedAt: Date
    public var notes: String
    public var equipment: Equipment
    public var fermentation: Fermentation
    public var ibuFormula: IBUFormula
    public var fermentables: [FermentableAddition]
    public var hops: [HopAddition]
    public var yeasts: [YeastAddition]
    public var miscs: [MiscAddition]
    public var mashSteps: [MashStep]
    /// Brew day logs, newest first.
    public var sessions: [BrewSession]
    /// Water chemistry plan (nil until the brewer sets one up).
    public var water: WaterTreatment?
    /// Saved formulations, newest first.
    public var versions: [RecipeVersion]

    public init(id: UUID = UUID(),
                name: String = "New Recipe",
                author: String = "",
                type: RecipeType = .allGrain,
                styleId: String? = nil,
                createdAt: Date = Date(),
                modifiedAt: Date = Date(),
                notes: String = "",
                equipment: Equipment = Equipment(),
                fermentation: Fermentation = Fermentation(),
                ibuFormula: IBUFormula = .tinseth,
                fermentables: [FermentableAddition] = [],
                hops: [HopAddition] = [],
                yeasts: [YeastAddition] = [],
                miscs: [MiscAddition] = [],
                mashSteps: [MashStep] = [MashStep(name: "Saccharification", tempC: 66, minutes: 60)],
                sessions: [BrewSession] = [],
                water: WaterTreatment? = nil,
                versions: [RecipeVersion] = []) {
        self.id = id
        self.name = name
        self.author = author
        self.type = type
        self.styleId = styleId
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.notes = notes
        self.equipment = equipment
        self.fermentation = fermentation
        self.ibuFormula = ibuFormula
        self.fermentables = fermentables
        self.hops = hops
        self.yeasts = yeasts
        self.miscs = miscs
        self.mashSteps = mashSteps
        self.sessions = sessions
        self.water = water
        self.versions = versions
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, author, type, styleId, createdAt, modifiedAt, notes, equipment, fermentation
        case ibuFormula, fermentables, hops, yeasts, miscs, mashSteps, sessions, water, versions
    }

    /// Tolerates missing keys so recipes saved by earlier versions of the app still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Recipe()
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? defaults.name
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        type = try c.decodeIfPresent(RecipeType.self, forKey: .type) ?? .allGrain
        styleId = try c.decodeIfPresent(String.self, forKey: .styleId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        equipment = try c.decodeIfPresent(Equipment.self, forKey: .equipment) ?? defaults.equipment
        fermentation = try c.decodeIfPresent(Fermentation.self, forKey: .fermentation) ?? defaults.fermentation
        ibuFormula = try c.decodeIfPresent(IBUFormula.self, forKey: .ibuFormula) ?? .tinseth
        fermentables = try c.decodeIfPresent([FermentableAddition].self, forKey: .fermentables) ?? []
        hops = try c.decodeIfPresent([HopAddition].self, forKey: .hops) ?? []
        yeasts = try c.decodeIfPresent([YeastAddition].self, forKey: .yeasts) ?? []
        miscs = try c.decodeIfPresent([MiscAddition].self, forKey: .miscs) ?? []
        mashSteps = try c.decodeIfPresent([MashStep].self, forKey: .mashSteps) ?? []
        sessions = try c.decodeIfPresent([BrewSession].self, forKey: .sessions) ?? []
        water = try c.decodeIfPresent(WaterTreatment.self, forKey: .water)
        versions = try c.decodeIfPresent([RecipeVersion].self, forKey: .versions) ?? []
    }

    public var style: BeerStyle? { styleId.flatMap { StyleCatalog.style(id: $0) } }

    public var stats: RecipeStats { BrewCalculator.calculate(self) }

    /// Hop additions sorted the way a brewer uses them: boil (longest first), whirlpool, dry hop.
    public var hopsInBrewOrder: [HopAddition] {
        func rank(_ use: HopUse) -> Int {
            switch use {
            case .mash: return 0
            case .firstWort: return 1
            case .boil: return 2
            case .whirlpool: return 3
            case .dryHop: return 4
            }
        }
        return hops.sorted { a, b in
            if rank(a.use) != rank(b.use) { return rank(a.use) < rank(b.use) }
            return a.use == .dryHop ? a.time < b.time : a.time > b.time
        }
    }

    /// A copy with fresh identifiers, for "Duplicate recipe".
    public func duplicated() -> Recipe {
        var copy = self
        copy.id = UUID()
        copy.name = name + " (Copy)"
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        copy.sessions = []
        copy.versions = []
        return copy
    }
}
