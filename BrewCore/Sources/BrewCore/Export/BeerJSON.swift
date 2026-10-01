import Foundation

/// Import and export of BeerJSON 1.0 (https://github.com/beerjson/beerjson), the JSON successor
/// to BeerXML.
///
/// BeerJSON has no field for a few things this app models, so they are encoded with standard
/// fields: hop-stand (whirlpool) hops are boil additions made at the end of the boil with a steep
/// duration; first-wort hops are full-length boil additions; Belgian strains export as "ale".
public enum BeerJSON {
    public enum ImportError: LocalizedError {
        case unreadable
        case noRecipes

        public var errorDescription: String? {
            switch self {
            case .unreadable: return "The file isn't valid BeerJSON."
            case .noRecipes: return "No recipes were found in the file."
            }
        }
    }

    typealias JSON = [String: Any]

    // MARK: - Export

    public static func export(_ recipes: [Recipe]) -> Data {
        let root: JSON = ["beerjson": ["version": 1.0, "recipes": recipes.map(recipeJSON)] as JSON]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    static func recipeJSON(_ r: Recipe) -> JSON {
        let eq = r.equipment
        let stats = r.stats
        var json: JSON = [
            "name": r.name.isEmpty ? "Untitled" : r.name,
            "type": r.type.beerJSON,
            "author": r.author.isEmpty ? "Unknown" : r.author,
            "created": dateFormatter.string(from: r.createdAt),
            "batch_size": q(eq.batchSizeL, "l"),
            "efficiency": ["brewhouse": q(eq.efficiency, "%")] as JSON,
            "boil": ["name": "Boil", "boil_time": q(eq.boilTimeMinutes, "min"),
                     "pre_boil_size": q(eq.preBoilVolumeL, "l")] as JSON,
            "carbonation": round(r.fermentation.carbonationVolumes),
            "original_gravity": q(stats.og, "sg"),
            "final_gravity": q(stats.fg, "sg"),
            "alcohol_by_volume": q(stats.abv, "%"),
            "ibu_estimate": ["method": r.ibuFormula == .rager ? "Rager" : "Tinseth"] as JSON,
            "color_estimate": q(stats.srm, "SRM"),
            "ingredients": [
                "fermentable_additions": r.fermentables.map(fermentableJSON),
                "hop_additions": r.hops.map { hopJSON($0, boilMinutes: eq.boilTimeMinutes) },
                "culture_additions": r.yeasts.map(cultureJSON),
                "miscellaneous_additions": r.miscs.map { miscJSON($0, boilMinutes: eq.boilTimeMinutes) }
            ] as JSON
        ]
        if !r.notes.isEmpty { json["notes"] = r.notes }
        if let style = r.style {
            var s: JSON = ["name": style.name, "category": style.category, "style_guide": "BJCP 2021", "type": "beer"]
            let number = style.id.prefix { $0.isNumber }
            if let n = Int(number) { s["category_number"] = n }
            let letter = style.id.dropFirst(number.count)
            if !letter.isEmpty { s["style_letter"] = String(letter) }
            json["style"] = s
        }
        if !r.mashSteps.isEmpty {
            json["mash"] = [
                "name": r.type == .extract ? "Steep" : "Mash",
                "grain_temperature": q(eq.grainTempC, "C"),
                "mash_steps": r.mashSteps.map { step -> JSON in
                    ["name": step.name, "type": step.type.rawValue,
                     "step_temperature": q(step.tempC, "C"), "step_time": q(step.minutes, "min")]
                }
            ] as JSON
        }
        var fermentationSteps: [JSON] = [[
            "name": "Primary",
            "start_temperature": q(r.fermentation.primaryTempC, "C"),
            "step_time": q(r.fermentation.primaryDays, "day")
        ]]
        if r.fermentation.secondaryDays > 0 {
            fermentationSteps.append(["name": "Secondary", "step_time": q(r.fermentation.secondaryDays, "day")])
        }
        json["fermentation"] = ["name": "Fermentation", "fermentation_steps": fermentationSteps] as JSON
        return json
    }

    static func fermentableJSON(_ a: FermentableAddition) -> JSON {
        let f = a.fermentable
        var json: JSON = [
            "name": f.name,
            "type": f.type.beerJSON,
            "yield": ["potential": q(f.potentialSG, "sg")] as JSON,
            "color": q(f.colorLovibond, "Lovi"),
            "amount": q(a.amountKg, "kg")
        ]
        if f.type == .adjunct { json["grain_group"] = "flaked" }
        if let origin = f.origin { json["origin"] = origin }
        if let supplier = f.supplier { json["producer"] = supplier }
        return json
    }

    static func hopJSON(_ h: HopAddition, boilMinutes: Double) -> JSON {
        var timing: JSON
        switch h.use {
        case .boil:
            let minutes = min(max(h.time, 0), boilMinutes)
            timing = ["use": "add_to_boil", "time": q(boilMinutes - minutes, "min"), "duration": q(minutes, "min")]
        case .firstWort:
            timing = ["use": "add_to_boil", "time": q(0, "min"), "duration": q(boilMinutes, "min")]
        case .whirlpool:
            timing = ["use": "add_to_boil", "time": q(boilMinutes, "min"), "duration": q(h.time, "min")]
        case .mash:
            timing = ["use": "add_to_mash"]
        case .dryHop:
            timing = ["use": "add_to_fermentation", "duration": q(h.time, "day")]
        }
        var json: JSON = [
            "name": h.hop.name,
            "alpha_acid": q(h.alphaAcid, "%"),
            "form": h.form.beerJSON,
            "amount": q(h.amountGrams, "g"),
            "timing": timing
        ]
        if let origin = h.hop.origin { json["origin"] = origin }
        if let beta = h.hop.betaAcid { json["beta_acid"] = q(beta, "%") }
        return json
    }

    static func cultureJSON(_ y: YeastAddition) -> JSON {
        var json: JSON = [
            "name": y.yeast.name,
            "type": y.yeast.type.beerJSON,
            "form": y.yeast.form == .dry ? "dry" : "liquid",
            "attenuation": q(y.attenuation, "%"),
            "amount": q(y.packs, "pkg")
        ]
        if let lab = y.yeast.laboratory { json["producer"] = lab }
        if let product = y.yeast.productId { json["product_id"] = product }
        return json
    }

    static func miscJSON(_ m: MiscAddition, boilMinutes: Double) -> JSON {
        let unit = m.unit.lowercased()
        let amount: JSON
        switch unit {
        case "g", "kg", "mg", "oz", "lb": amount = q(m.amount, unit)
        case "ml", "l", "tsp", "tbsp": amount = q(m.amount, unit)
        default: amount = q(m.amount, "each")
        }
        var timing: JSON
        switch m.use {
        case .mash: timing = ["use": "add_to_mash"]
        case .boil: timing = ["use": "add_to_boil", "time": q(boilMinutes - m.timeMinutes, "min"),
                              "duration": q(m.timeMinutes, "min")]
        case .primary, .secondary: timing = ["use": "add_to_fermentation"]
        case .bottling: timing = ["use": "add_to_package"]
        }
        return ["name": m.misc.name, "type": m.misc.type.beerJSON, "amount": amount, "timing": timing]
    }

    // MARK: - Import

    public static func importRecipes(from data: Data) throws -> [Recipe] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { throw ImportError.unreadable }
        let body = root["beerjson"] as? JSON ?? root
        guard let recipes = body["recipes"] as? [JSON], !recipes.isEmpty else { throw ImportError.noRecipes }
        return recipes.map(recipe(from:))
    }

    /// Whether `data` looks like BeerJSON rather than BeerXML.
    public static func looksLikeBeerJSON(_ data: Data) -> Bool {
        data.first { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 || $0 == 0xEF || $0 == 0xBB || $0 == 0xBF) } == UInt8(ascii: "{")
    }

    static func recipe(from json: JSON) -> Recipe {
        var r = Recipe(name: json["name"] as? String ?? "Imported Recipe", mashSteps: [])
        r.author = json["author"] as? String ?? ""
        if r.author == "Unknown" { r.author = "" }
        r.type = RecipeType(beerJSON: json["type"] as? String)
        r.notes = json["notes"] as? String ?? ""
        if let created = (json["created"] as? String).flatMap(parseDate) { r.createdAt = created }
        if let v = liters(json["batch_size"]) { r.equipment.batchSizeL = v }
        if let v = number((json["efficiency"] as? JSON)?["brewhouse"]) { r.equipment.efficiency = v }
        if let boil = json["boil"] as? JSON {
            if let boilTime = minutes(boil["boil_time"]) { r.equipment.boilTimeMinutes = boilTime }
            if let pre = liters(boil["pre_boil_size"]), r.equipment.boilTimeMinutes > 0 {
                let rate = (pre - r.equipment.postBoilVolumeL) / (r.equipment.boilTimeMinutes / 60)
                if rate > 0 && rate < pre { r.equipment.boilOffLPerHour = rate }
            }
        }
        if let carbonation = json["carbonation"] as? Double, carbonation > 0 { r.fermentation.carbonationVolumes = carbonation }
        if ((json["ibu_estimate"] as? JSON)?["method"] as? String)?.lowercased() == "rager" { r.ibuFormula = .rager }

        if let style = json["style"] as? JSON {
            let number = (style["category_number"] as? Int).map(String.init) ?? ""
            let id = number + (style["style_letter"] as? String ?? "")
            if StyleCatalog.style(id: id) != nil {
                r.styleId = id
            } else if let name = style["name"] as? String {
                r.styleId = StyleCatalog.all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
            }
        }

        let ingredients = json["ingredients"] as? JSON ?? [:]
        r.fermentables = (ingredients["fermentable_additions"] as? [JSON] ?? []).map(fermentable(from:))
        r.hops = (ingredients["hop_additions"] as? [JSON] ?? []).map { hop(from: $0, boilMinutes: r.equipment.boilTimeMinutes) }
        r.yeasts = (ingredients["culture_additions"] as? [JSON] ?? []).map(culture(from:))
        r.miscs = (ingredients["miscellaneous_additions"] as? [JSON] ?? []).map(misc(from:))

        if let mash = json["mash"] as? JSON {
            if let t = celsius(mash["grain_temperature"]) { r.equipment.grainTempC = t }
            r.mashSteps = (mash["mash_steps"] as? [JSON] ?? []).compactMap { step -> MashStep? in
                guard let temp = celsius(step["step_temperature"]) else { return nil }
                let type = MashStepType(rawValue: step["type"] as? String ?? "") ?? .infusion
                return MashStep(name: step["name"] as? String ?? "Step", type: type, tempC: temp,
                                minutes: minutes(step["step_time"]) ?? 60)
            }
        }
        if r.mashSteps.isEmpty && r.type != .extract {
            r.mashSteps = [MashStep(name: "Saccharification", tempC: 66, minutes: 60)]
        }

        let steps = (json["fermentation"] as? JSON)?["fermentation_steps"] as? [JSON] ?? []
        if let primary = steps.first {
            if let t = celsius(primary["start_temperature"]) { r.fermentation.primaryTempC = t }
            if let d = minutes(primary["step_time"]) { r.fermentation.primaryDays = (d / 1440).rounded() }
        }
        if steps.count > 1, let d = minutes(steps[1]["step_time"]) {
            r.fermentation.secondaryDays = (d / 1440).rounded()
        }
        return r
    }

    static func fermentable(from json: JSON) -> FermentableAddition {
        let name = json["name"] as? String ?? "Fermentable"
        var type = FermentableType(beerJSON: json["type"] as? String)
        if type == .grain && (json["grain_group"] as? String) == "flaked" { type = .adjunct }
        var f = IngredientCatalog.fermentable(named: name)
            ?? Fermentable(name: name, type: type, colorLovibond: 0, potentialPPG: 36,
                           fermentability: type == .sugar ? 100 : nil)
        if let lovibond = lovibond(json["color"]) { f.colorLovibond = lovibond }
        if let ppg = ppg(json["yield"] as? JSON) { f.potentialPPG = ppg }
        if let origin = json["origin"] as? String, !origin.isEmpty { f.origin = origin }
        if let producer = json["producer"] as? String, !producer.isEmpty { f.supplier = producer }
        return FermentableAddition(fermentable: f, amountKg: kilograms(json["amount"]) ?? 0)
    }

    static func hop(from json: JSON, boilMinutes: Double) -> HopAddition {
        let name = json["name"] as? String ?? "Hop"
        let alpha = number(json["alpha_acid"])
        let hop = IngredientCatalog.hop(named: name)
            ?? Hop(name: name, origin: json["origin"] as? String, alphaAcid: alpha ?? 5, betaAcid: number(json["beta_acid"]))
        let timing = json["timing"] as? JSON ?? [:]
        let duration = minutes(timing["duration"])
        let start = minutes(timing["time"])
        var use = HopUse.boil
        var time = boilMinutes
        switch timing["use"] as? String {
        case "add_to_fermentation", "add_to_package":
            use = .dryHop
            time = duration.map { ($0 / 1440).rounded() } ?? 3
        case "add_to_mash":
            use = .mash
            time = duration ?? 60
        default:
            if let start, start >= boilMinutes, let duration, duration > 0 {
                use = .whirlpool
                time = duration
            } else {
                time = duration ?? start.map { max(0, boilMinutes - $0) } ?? boilMinutes
            }
        }
        return HopAddition(hop: hop, amountGrams: (kilograms(json["amount"]) ?? 0) * 1000, alphaAcid: alpha,
                           use: use, time: time, form: HopForm(beerJSON: json["form"] as? String))
    }

    static func culture(from json: JSON) -> YeastAddition {
        let name = json["name"] as? String ?? "Yeast"
        let product = json["product_id"] as? String
        let attenuation = number(json["attenuation"])
        let yeast = product.flatMap(IngredientCatalog.yeast(productId:))
            ?? Yeast(name: name,
                     laboratory: json["producer"] as? String,
                     productId: product,
                     type: YeastType(beerJSON: json["type"] as? String),
                     form: (json["form"] as? String) == "dry" ? .dry : .liquid,
                     attenuationMin: attenuation ?? 75,
                     attenuationMax: attenuation ?? 75,
                     tempMinC: 18, tempMaxC: 22)
        let amount = json["amount"] as? JSON
        let packs = (amount?["unit"] as? String).map { ["pkg", "each", "unit", "1"].contains($0) } == true
            ? (amount?["value"] as? Double ?? 1) : 1
        return YeastAddition(yeast: yeast, attenuation: attenuation, packs: max(packs, 1))
    }

    static func misc(from json: JSON) -> MiscAddition {
        let name = json["name"] as? String ?? "Misc"
        let typeName = json["type"] as? String
        let timing = json["timing"] as? JSON ?? [:]
        let use: MiscUse
        switch timing["use"] as? String {
        case "add_to_mash": use = .mash
        case "add_to_fermentation": use = .primary
        case "add_to_package": use = .bottling
        default: use = .boil
        }
        let amount = json["amount"] as? JSON
        var value = amount?["value"] as? Double ?? 0
        var unit = amount?["unit"] as? String ?? "g"
        if unit == "kg" { value *= 1000; unit = "g" }
        if unit == "l" { value *= 1000; unit = "ml" }
        if unit == "each" || unit == "unit" || unit == "1" { unit = "each" }
        let misc = IngredientCatalog.miscs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? Misc(name: name, type: MiscType(beerJSON: typeName), defaultUse: use, defaultUnit: unit)
        if misc.defaultUnit.lowercased() == "tablet" && unit == "each" { unit = "tablet" }
        return MiscAddition(misc: misc, amount: value, unit: unit, use: use,
                            timeMinutes: use == .boil ? (minutes(timing["duration"]) ?? 0) : 0)
    }

    // MARK: - Units

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func parseDate(_ s: String) -> Date? { dateFormatter.date(from: String(s.prefix(10))) }

    private static func round(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }

    private static func q(_ value: Double, _ unit: String) -> JSON { ["value": round(value), "unit": unit] }

    private static func measure(_ any: Any?) -> (value: Double, unit: String)? {
        guard let json = any as? JSON, let value = json["value"] as? Double else { return nil }
        return (value, (json["unit"] as? String ?? "").lowercased())
    }

    private static func number(_ any: Any?) -> Double? { measure(any)?.value }

    static func kilograms(_ any: Any?) -> Double? {
        guard let m = measure(any) else { return nil }
        switch m.unit {
        case "mg": return m.value / 1_000_000
        case "g": return m.value / 1000
        case "lb": return BrewMath.lbToKg(m.value)
        case "oz": return BrewMath.ouncesToGrams(m.value) / 1000
        default: return m.value
        }
    }

    static func liters(_ any: Any?) -> Double? {
        guard let m = measure(any) else { return nil }
        let perLiter: [String: Double] = [
            "ml": 0.001, "l": 1, "tsp": 0.004_928_92, "tbsp": 0.014_786_8, "floz": 0.029_573_5,
            "cup": 0.236_588, "pt": 0.473_176, "qt": 0.946_353, "gal": 3.785_41, "bbl": 117.348,
            "ifloz": 0.028_413_1, "ipt": 0.568_261, "iqt": 1.136_52, "igal": 4.546_09, "ibbl": 163.659
        ]
        return m.value * (perLiter[m.unit] ?? 1)
    }

    static func celsius(_ any: Any?) -> Double? {
        guard let m = measure(any) else { return nil }
        return m.unit == "f" ? BrewMath.fToC(m.value) : m.value
    }

    static func minutes(_ any: Any?) -> Double? {
        guard let m = measure(any) else { return nil }
        switch m.unit {
        case "sec": return m.value / 60
        case "hr": return m.value * 60
        case "day": return m.value * 1440
        case "week": return m.value * 10_080
        default: return m.value
        }
    }

    static func lovibond(_ any: Any?) -> Double? {
        guard let m = measure(any) else { return nil }
        let srm: Double
        switch m.unit {
        case "lovi": return m.value
        case "ebc": srm = BrewMath.ebcToSRM(m.value)
        default: srm = m.value
        }
        return max(0, (srm + 0.76) / 1.3546)
    }

    static func gravity(_ any: Any?) -> Double? {
        guard let m = measure(any) else { return nil }
        switch m.unit {
        case "plato", "brix": return BrewMath.platoToSG(m.value)
        default: return m.value
        }
    }

    static func ppg(_ yield: JSON?) -> Double? {
        guard let yield else { return nil }
        if let sg = gravity(yield["potential"]), sg > 1 { return (sg - 1) * 1000 }
        if let percent = number(yield["fine_grind"]), percent > 0 { return percent / 100 * BeerXML.sucrosePPG }
        return nil
    }
}

// MARK: - Vocabulary mapping

extension RecipeType {
    var beerJSON: String {
        switch self {
        case .allGrain: return "all grain"
        case .partialMash: return "partial mash"
        case .extract: return "extract"
        }
    }

    init(beerJSON: String?) {
        switch beerJSON?.lowercased() {
        case "extract": self = .extract
        case "partial mash": self = .partialMash
        default: self = .allGrain
        }
    }
}

extension FermentableType {
    var beerJSON: String {
        switch self {
        case .grain, .adjunct: return "grain"
        case .extract: return "extract"
        case .dryExtract: return "dry extract"
        case .sugar: return "sugar"
        }
    }

    init(beerJSON: String?) {
        switch beerJSON?.lowercased() {
        case "extract": self = .extract
        case "dry extract": self = .dryExtract
        case "sugar", "honey", "fruit", "juice": self = .sugar
        case "other": self = .adjunct
        default: self = .grain
        }
    }
}

extension HopForm {
    var beerJSON: String {
        switch self {
        case .pellet: return "pellet"
        case .leaf: return "leaf"
        case .cryo: return "powder"
        }
    }

    init(beerJSON: String?) {
        switch beerJSON?.lowercased() {
        case "leaf", "leaf (wet)", "plug": self = .leaf
        case "powder", "extract": self = .cryo
        default: self = .pellet
        }
    }
}

extension YeastType {
    var beerJSON: String {
        switch self {
        case .ale, .belgian: return "ale"
        case .lager: return "lager"
        case .wheat: return "wheat"
        case .kveik: return "kveik"
        case .wild: return "brett"
        case .wine: return "wine"
        }
    }

    init(beerJSON: String?) {
        switch beerJSON?.lowercased() {
        case "lager": self = .lager
        case "wheat": self = .wheat
        case "kveik": self = .kveik
        case "brett", "lacto", "pedio", "bacteria", "mixed-culture", "spontaneous": self = .wild
        case "wine", "champagne", "malolactic": self = .wine
        default: self = .ale
        }
    }
}

extension MiscType {
    var beerJSON: String {
        switch self {
        case .spice: return "spice"
        case .fining: return "fining"
        case .waterAgent: return "water agent"
        case .herb: return "herb"
        case .flavor: return "flavor"
        case .other: return "other"
        }
    }

    init(beerJSON: String?) {
        self = MiscType.allCases.first { $0.beerJSON == beerJSON?.lowercased() } ?? .other
    }
}
