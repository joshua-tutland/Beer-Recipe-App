import Foundation

// MARK: - Fermentables

public enum FermentableType: String, Codable, CaseIterable, Sendable {
    case grain
    case adjunct
    case extract
    case dryExtract
    case sugar

    public var displayName: String {
        switch self {
        case .grain: return "Grain"
        case .adjunct: return "Adjunct"
        case .extract: return "Liquid Extract"
        case .dryExtract: return "Dry Extract"
        case .sugar: return "Sugar"
        }
    }

    /// Mashed ingredients are subject to brewhouse efficiency; extracts and sugars are not.
    public var isMashed: Bool {
        switch self {
        case .grain, .adjunct: return true
        case .extract, .dryExtract, .sugar: return false
        }
    }
}

public struct Fermentable: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var type: FermentableType
    /// Color in degrees Lovibond.
    public var colorLovibond: Double
    /// Gravity points per pound per US gallon (e.g. 37 for pale malt).
    public var potentialPPG: Double
    /// Percentage of this ingredient's sugars that yeast can ferment.
    /// `nil` means "use the yeast's attenuation" (normal malt sugars).
    /// Simple sugars are 100, lactose and maltodextrin are 0.
    public var fermentability: Double?
    public var origin: String?
    public var supplier: String?
    /// Recommended maximum share of the grist, in percent.
    public var maxPercent: Double?
    public var notes: String?

    public init(id: String = UUID().uuidString,
                name: String,
                type: FermentableType,
                colorLovibond: Double,
                potentialPPG: Double,
                fermentability: Double? = nil,
                origin: String? = nil,
                supplier: String? = nil,
                maxPercent: Double? = nil,
                notes: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.colorLovibond = colorLovibond
        self.potentialPPG = potentialPPG
        self.fermentability = fermentability
        self.origin = origin
        self.supplier = supplier
        self.maxPercent = maxPercent
        self.notes = notes
    }

    /// Potential as a specific gravity (1 lb in 1 gal), e.g. 1.037.
    public var potentialSG: Double { 1 + potentialPPG / 1000 }

    public var colorEBC: Double { BrewMath.srmToEBC(BrewMath.lovibondToSRM(colorLovibond)) }
}

// MARK: - Hops

public enum HopPurpose: String, Codable, CaseIterable, Sendable {
    case bittering, aroma, dualPurpose

    public var displayName: String {
        switch self {
        case .bittering: return "Bittering"
        case .aroma: return "Aroma"
        case .dualPurpose: return "Dual Purpose"
        }
    }
}

public struct Hop: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var origin: String?
    /// Typical alpha acid, percent.
    public var alphaAcid: Double
    public var betaAcid: Double?
    public var purpose: HopPurpose
    public var aroma: String?
    public var substitutes: String?

    public init(id: String = UUID().uuidString,
                name: String,
                origin: String? = nil,
                alphaAcid: Double,
                betaAcid: Double? = nil,
                purpose: HopPurpose = .dualPurpose,
                aroma: String? = nil,
                substitutes: String? = nil) {
        self.id = id
        self.name = name
        self.origin = origin
        self.alphaAcid = alphaAcid
        self.betaAcid = betaAcid
        self.purpose = purpose
        self.aroma = aroma
        self.substitutes = substitutes
    }
}

public enum HopUse: String, Codable, CaseIterable, Sendable {
    case boil
    case firstWort
    case whirlpool
    case dryHop
    case mash

    public var displayName: String {
        switch self {
        case .boil: return "Boil"
        case .firstWort: return "First Wort"
        case .whirlpool: return "Whirlpool"
        case .dryHop: return "Dry Hop"
        case .mash: return "Mash"
        }
    }

    /// Dry hop additions are timed in days, everything else in minutes.
    public var timeUnit: String { self == .dryHop ? "days" : "min" }
}

public enum HopForm: String, Codable, CaseIterable, Sendable {
    case pellet, leaf, cryo

    public var displayName: String {
        switch self {
        case .pellet: return "Pellet"
        case .leaf: return "Leaf"
        case .cryo: return "Cryo / Lupulin"
        }
    }
}

// MARK: - Yeast

public enum YeastType: String, Codable, CaseIterable, Sendable {
    case ale, lager, wheat, belgian, kveik, wild, wine

    public var displayName: String {
        switch self {
        case .ale: return "Ale"
        case .lager: return "Lager"
        case .wheat: return "Wheat"
        case .belgian: return "Belgian / Saison"
        case .kveik: return "Kveik"
        case .wild: return "Wild / Sour"
        case .wine: return "Wine / Champagne"
        }
    }

    /// Recommended pitch rate in million cells / mL / °Plato.
    public var pitchRate: Double { self == .lager ? 1.5 : 0.75 }
}

public enum YeastForm: String, Codable, CaseIterable, Sendable {
    case dry, liquid

    public var displayName: String { self == .dry ? "Dry" : "Liquid" }
}

public struct Yeast: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var laboratory: String?
    public var productId: String?
    public var type: YeastType
    public var form: YeastForm
    public var attenuationMin: Double
    public var attenuationMax: Double
    public var tempMinC: Double
    public var tempMaxC: Double
    public var flocculation: String?
    public var alcoholTolerance: Double?
    public var notes: String?

    public init(id: String = UUID().uuidString,
                name: String,
                laboratory: String? = nil,
                productId: String? = nil,
                type: YeastType = .ale,
                form: YeastForm = .dry,
                attenuationMin: Double,
                attenuationMax: Double,
                tempMinC: Double,
                tempMaxC: Double,
                flocculation: String? = nil,
                alcoholTolerance: Double? = nil,
                notes: String? = nil) {
        self.id = id
        self.name = name
        self.laboratory = laboratory
        self.productId = productId
        self.type = type
        self.form = form
        self.attenuationMin = attenuationMin
        self.attenuationMax = attenuationMax
        self.tempMinC = tempMinC
        self.tempMaxC = tempMaxC
        self.flocculation = flocculation
        self.alcoholTolerance = alcoholTolerance
        self.notes = notes
    }

    public var averageAttenuation: Double { (attenuationMin + attenuationMax) / 2 }

    public var displayName: String {
        [laboratory, productId, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Misc

public enum MiscType: String, Codable, CaseIterable, Sendable {
    case spice, fining, waterAgent, herb, flavor, other

    public var displayName: String {
        switch self {
        case .spice: return "Spice"
        case .fining: return "Fining"
        case .waterAgent: return "Water Agent"
        case .herb: return "Herb"
        case .flavor: return "Flavor"
        case .other: return "Other"
        }
    }
}

public enum MiscUse: String, Codable, CaseIterable, Sendable {
    case mash, boil, primary, secondary, bottling

    public var displayName: String { rawValue.capitalized }
}

public struct Misc: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var type: MiscType
    public var defaultUse: MiscUse
    public var defaultUnit: String
    public var notes: String?

    public init(id: String = UUID().uuidString,
                name: String,
                type: MiscType,
                defaultUse: MiscUse,
                defaultUnit: String = "g",
                notes: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.defaultUse = defaultUse
        self.defaultUnit = defaultUnit
        self.notes = notes
    }
}
