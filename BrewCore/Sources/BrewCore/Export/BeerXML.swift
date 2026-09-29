import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Import and export of BeerXML 1.0 — the open recipe interchange format understood by
/// BeerSmith, Brewfather, Brewer's Friend, Brewtarget and most other brewing software.
public enum BeerXML {
    public enum ImportError: LocalizedError {
        case unreadable
        case noRecipes

        public var errorDescription: String? {
            switch self {
            case .unreadable: return "The file isn't valid BeerXML."
            case .noRecipes: return "No recipes were found in the file."
            }
        }
    }

    /// PPG of pure sucrose; BeerXML expresses potential as a percentage of this.
    static let sucrosePPG = 46.214

    // MARK: - Export

    public static func export(_ recipes: [Recipe]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<RECIPES>\n"
        for recipe in recipes { xml += export(recipe) }
        return xml + "</RECIPES>\n"
    }

    static func export(_ recipe: Recipe) -> String {
        let eq = recipe.equipment
        let ferm = recipe.fermentation
        var x = XMLBuilder()
        x.open("RECIPE")
        x.leaf("NAME", recipe.name)
        x.leaf("VERSION", 1)
        x.leaf("TYPE", recipe.type.beerXML)
        x.leaf("BREWER", recipe.author.isEmpty ? "Unknown" : recipe.author)
        x.leaf("BATCH_SIZE", eq.batchSizeL)
        x.leaf("BOIL_SIZE", eq.preBoilVolumeL)
        x.leaf("BOIL_TIME", eq.boilTimeMinutes)
        x.leaf("EFFICIENCY", eq.efficiency)
        x.leaf("NOTES", recipe.notes)
        x.leaf("FERMENTATION_STAGES", ferm.secondaryDays > 0 ? 2 : 1)
        x.leaf("PRIMARY_AGE", ferm.primaryDays)
        x.leaf("PRIMARY_TEMP", ferm.primaryTempC)
        x.leaf("SECONDARY_AGE", ferm.secondaryDays)
        x.leaf("CARBONATION", ferm.carbonationVolumes)
        x.leaf("IBU_METHOD", recipe.ibuFormula.displayName)

        if let style = recipe.style {
            x.open("STYLE")
            x.leaf("NAME", style.name)
            x.leaf("CATEGORY", style.category)
            x.leaf("VERSION", 1)
            let number = style.id.prefix { $0.isNumber }
            x.leaf("CATEGORY_NUMBER", String(number))
            x.leaf("STYLE_LETTER", String(style.id.dropFirst(number.count)))
            x.leaf("STYLE_GUIDE", "BJCP 2021")
            x.leaf("TYPE", "Ale")
            x.leaf("OG_MIN", style.ogMin); x.leaf("OG_MAX", style.ogMax)
            x.leaf("FG_MIN", style.fgMin); x.leaf("FG_MAX", style.fgMax)
            x.leaf("IBU_MIN", style.ibuMin); x.leaf("IBU_MAX", style.ibuMax)
            x.leaf("COLOR_MIN", style.srmMin); x.leaf("COLOR_MAX", style.srmMax)
            x.leaf("ABV_MIN", style.abvMin); x.leaf("ABV_MAX", style.abvMax)
            x.close("STYLE")
        }

        x.open("FERMENTABLES")
        for a in recipe.fermentables {
            let f = a.fermentable
            x.open("FERMENTABLE")
            x.leaf("NAME", f.name)
            x.leaf("VERSION", 1)
            x.leaf("TYPE", f.type.beerXML)
            x.leaf("AMOUNT", a.amountKg)
            x.leaf("YIELD", f.potentialPPG / sucrosePPG * 100)
            x.leaf("COLOR", f.colorLovibond)
            if let origin = f.origin { x.leaf("ORIGIN", origin) }
            if let max = f.maxPercent { x.leaf("MAX_IN_BATCH", max) }
            if let notes = f.notes { x.leaf("NOTES", notes) }
            x.close("FERMENTABLE")
        }
        x.close("FERMENTABLES")

        x.open("HOPS")
        for h in recipe.hops {
            x.open("HOP")
            x.leaf("NAME", h.hop.name)
            x.leaf("VERSION", 1)
            x.leaf("ALPHA", h.alphaAcid)
            x.leaf("AMOUNT", h.amountGrams / 1000)
            x.leaf("USE", h.use.beerXML)
            x.leaf("TIME", h.use == .dryHop ? h.time * 1440 : h.time)
            x.leaf("FORM", h.form.beerXML)
            x.leaf("TYPE", h.hop.purpose.beerXML)
            if let origin = h.hop.origin { x.leaf("ORIGIN", origin) }
            if let beta = h.hop.betaAcid { x.leaf("BETA", beta) }
            x.close("HOP")
        }
        x.close("HOPS")

        x.open("YEASTS")
        for y in recipe.yeasts {
            x.open("YEAST")
            x.leaf("NAME", y.yeast.name)
            x.leaf("VERSION", 1)
            x.leaf("TYPE", y.yeast.type.beerXML)
            x.leaf("FORM", y.yeast.form == .dry ? "Dry" : "Liquid")
            x.leaf("AMOUNT", y.yeast.form == .dry ? 0.0115 * y.packs : 0.125 * y.packs)
            x.leaf("AMOUNT_IS_WEIGHT", y.yeast.form == .dry ? "TRUE" : "FALSE")
            if let lab = y.yeast.laboratory { x.leaf("LABORATORY", lab) }
            if let product = y.yeast.productId { x.leaf("PRODUCT_ID", product) }
            x.leaf("MIN_TEMPERATURE", y.yeast.tempMinC)
            x.leaf("MAX_TEMPERATURE", y.yeast.tempMaxC)
            if let floc = y.yeast.flocculation { x.leaf("FLOCCULATION", floc) }
            x.leaf("ATTENUATION", y.attenuation)
            x.close("YEAST")
        }
        x.close("YEASTS")

        x.open("MISCS")
        for m in recipe.miscs {
            x.open("MISC")
            x.leaf("NAME", m.misc.name)
            x.leaf("VERSION", 1)
            x.leaf("TYPE", m.misc.type.displayName)
            x.leaf("USE", m.use.displayName)
            x.leaf("TIME", m.timeMinutes)
            let unit = m.unit.lowercased()
            let isWeight = unit != "ml" && unit != "l" && unit != "tsp" && unit != "tbsp"
            let factor = (unit == "g" || unit == "ml") ? 0.001 : 1
            x.leaf("AMOUNT", m.amount * factor)
            x.leaf("AMOUNT_IS_WEIGHT", isWeight ? "TRUE" : "FALSE")
            x.leaf("DISPLAY_AMOUNT", "\(UnitSystem.number(m.amount, digits: 1)) \(m.unit)")
            x.close("MISC")
        }
        x.close("MISCS")

        x.open("WATERS")
        x.close("WATERS")

        x.open("MASH")
        x.leaf("NAME", "Mash")
        x.leaf("VERSION", 1)
        x.leaf("GRAIN_TEMP", eq.grainTempC)
        x.open("MASH_STEPS")
        for (i, s) in recipe.mashSteps.enumerated() {
            x.open("MASH_STEP")
            x.leaf("NAME", s.name)
            x.leaf("VERSION", 1)
            x.leaf("TYPE", s.type.displayName)
            if i == 0 && s.type == .infusion { x.leaf("INFUSE_AMOUNT", recipe.stats.strikeWaterL) }
            x.leaf("STEP_TEMP", s.tempC)
            x.leaf("STEP_TIME", s.minutes)
            x.close("MASH_STEP")
        }
        x.close("MASH_STEPS")
        x.close("MASH")

        x.close("RECIPE")
        return x.output
    }

    // MARK: - Import

    public static func importRecipes(from data: Data) throws -> [Recipe] {
        guard let root = XMLTree.parse(data) else { throw ImportError.unreadable }
        let recipeNodes = root.name == "RECIPE" ? [root] : root.descendants(named: "RECIPE")
        guard !recipeNodes.isEmpty else { throw ImportError.noRecipes }
        return recipeNodes.map(recipe(from:))
    }

    static func recipe(from node: XMLTree) -> Recipe {
        var r = Recipe(name: node.text("NAME") ?? "Imported Recipe", mashSteps: [])
        r.author = node.text("BREWER") ?? ""
        r.type = RecipeType(beerXML: node.text("TYPE"))
        r.notes = [node.text("NOTES"), node.text("TASTE_NOTES")].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if let v = node.double("BATCH_SIZE") { r.equipment.batchSizeL = v }
        if let v = node.double("BOIL_TIME") { r.equipment.boilTimeMinutes = v }
        if let v = node.double("EFFICIENCY") { r.equipment.efficiency = v }
        if let v = node.double("PRIMARY_AGE") { r.fermentation.primaryDays = v }
        if let v = node.double("PRIMARY_TEMP") { r.fermentation.primaryTempC = v }
        if let v = node.double("SECONDARY_AGE") { r.fermentation.secondaryDays = v }
        if let v = node.double("CARBONATION"), v > 0 { r.fermentation.carbonationVolumes = v }
        if node.text("IBU_METHOD")?.lowercased() == "rager" { r.ibuFormula = .rager }

        if let style = node.child("STYLE") {
            let id = (style.text("CATEGORY_NUMBER") ?? "") + (style.text("STYLE_LETTER") ?? "")
            if StyleCatalog.style(id: id) != nil {
                r.styleId = id
            } else if let name = style.text("NAME") {
                r.styleId = StyleCatalog.all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
            }
        }

        r.fermentables = node.child("FERMENTABLES")?.children(named: "FERMENTABLE").map { (n: XMLTree) -> FermentableAddition in
            let name = n.text("NAME") ?? "Fermentable"
            var f = IngredientCatalog.fermentable(named: name)
                ?? Fermentable(name: name, type: FermentableType(beerXML: n.text("TYPE")), colorLovibond: 0, potentialPPG: 36)
            if let color = n.double("COLOR") { f.colorLovibond = color }
            if let yield = n.double("YIELD"), yield > 0 { f.potentialPPG = yield / 100 * sucrosePPG }
            if let origin = n.text("ORIGIN"), !origin.isEmpty { f.origin = origin }
            return FermentableAddition(fermentable: f, amountKg: n.double("AMOUNT") ?? 0)
        } ?? []

        r.hops = node.child("HOPS")?.children(named: "HOP").map { (n: XMLTree) -> HopAddition in
            let name = n.text("NAME") ?? "Hop"
            let alpha = n.double("ALPHA")
            let hop = IngredientCatalog.hop(named: name)
                ?? Hop(name: name, origin: n.text("ORIGIN"), alphaAcid: alpha ?? 5, betaAcid: n.double("BETA"),
                       purpose: HopPurpose(beerXML: n.text("TYPE")))
            let use = HopUse(beerXML: n.text("USE"))
            let minutes = n.double("TIME") ?? 0
            return HopAddition(hop: hop,
                               amountGrams: (n.double("AMOUNT") ?? 0) * 1000,
                               alphaAcid: alpha,
                               use: use,
                               time: use == .dryHop ? (minutes / 1440).rounded() : minutes,
                               form: HopForm(beerXML: n.text("FORM")))
        } ?? []

        r.yeasts = node.child("YEASTS")?.children(named: "YEAST").map { (n: XMLTree) -> YeastAddition in
            let name = n.text("NAME") ?? "Yeast"
            let attenuation = n.double("ATTENUATION")
            let yeast = n.text("PRODUCT_ID").flatMap(IngredientCatalog.yeast(productId:))
                ?? Yeast(name: name,
                         laboratory: n.text("LABORATORY"),
                         productId: n.text("PRODUCT_ID"),
                         type: YeastType(beerXML: n.text("TYPE")),
                         form: n.text("FORM")?.lowercased() == "dry" ? .dry : .liquid,
                         attenuationMin: attenuation ?? 75,
                         attenuationMax: attenuation ?? 75,
                         tempMinC: n.double("MIN_TEMPERATURE") ?? 18,
                         tempMaxC: n.double("MAX_TEMPERATURE") ?? 22,
                         flocculation: n.text("FLOCCULATION"))
            return YeastAddition(yeast: yeast, attenuation: attenuation)
        } ?? []

        r.miscs = node.child("MISCS")?.children(named: "MISC").map { (n: XMLTree) -> MiscAddition in
            let name = n.text("NAME") ?? "Misc"
            let isWeight = n.text("AMOUNT_IS_WEIGHT")?.uppercased() == "TRUE"
            let misc = IngredientCatalog.miscs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                ?? Misc(name: name, type: MiscType(beerXML: n.text("TYPE")), defaultUse: MiscUse(beerXML: n.text("USE")),
                        defaultUnit: isWeight ? "g" : "ml")
            var amount = (n.double("AMOUNT") ?? 0) * 1000
            var unit = isWeight ? "g" : "ml"
            // Prefer the human-readable amount (e.g. "1 tablet") when the file has one.
            if let display = n.text("DISPLAY_AMOUNT") {
                let parts = display.split(separator: " ", maxSplits: 1).map(String.init)
                if parts.count == 2, let value = Double(parts[0]) {
                    amount = value
                    unit = parts[1]
                }
            }
            return MiscAddition(misc: misc,
                                amount: amount,
                                unit: unit,
                                use: MiscUse(beerXML: n.text("USE")),
                                timeMinutes: n.double("TIME") ?? 0)
        } ?? []

        if let mash = node.child("MASH") {
            if let grainTemp = mash.double("GRAIN_TEMP") { r.equipment.grainTempC = grainTemp }
            r.mashSteps = mash.child("MASH_STEPS")?.children(named: "MASH_STEP").map { (n: XMLTree) -> MashStep in
                MashStep(name: n.text("NAME") ?? "Step",
                         type: MashStepType(rawValue: (n.text("TYPE") ?? "").lowercased()) ?? .infusion,
                         tempC: n.double("STEP_TEMP") ?? 66,
                         minutes: n.double("STEP_TIME") ?? 60)
            } ?? []
        }
        if r.mashSteps.isEmpty && r.type != .extract {
            r.mashSteps = [MashStep(name: "Saccharification", tempC: 66, minutes: 60)]
        }
        if let boil = node.double("BOIL_SIZE"), r.equipment.boilTimeMinutes > 0 {
            // Back out the boil-off rate from the stated pre-boil volume.
            let rate = (boil - r.equipment.postBoilVolumeL) / (r.equipment.boilTimeMinutes / 60)
            if rate > 0 && rate < boil { r.equipment.boilOffLPerHour = rate }
        }
        return r
    }
}

// MARK: - BeerXML vocabulary mapping

extension RecipeType {
    var beerXML: String {
        switch self {
        case .allGrain: return "All Grain"
        case .partialMash: return "Partial Mash"
        case .extract: return "Extract"
        }
    }

    init(beerXML: String?) {
        switch beerXML?.lowercased() {
        case "extract": self = .extract
        case "partial mash": self = .partialMash
        default: self = .allGrain
        }
    }
}

extension FermentableType {
    var beerXML: String {
        switch self {
        case .grain: return "Grain"
        case .adjunct: return "Adjunct"
        case .extract: return "Extract"
        case .dryExtract: return "Dry Extract"
        case .sugar: return "Sugar"
        }
    }

    init(beerXML: String?) {
        switch beerXML?.lowercased() {
        case "sugar": self = .sugar
        case "extract": self = .extract
        case "dry extract": self = .dryExtract
        case "adjunct": self = .adjunct
        default: self = .grain
        }
    }
}

extension HopUse {
    var beerXML: String {
        switch self {
        case .boil: return "Boil"
        case .firstWort: return "First Wort"
        case .whirlpool: return "Aroma"
        case .dryHop: return "Dry Hop"
        case .mash: return "Mash"
        }
    }

    init(beerXML: String?) {
        switch beerXML?.lowercased() {
        case "dry hop": self = .dryHop
        case "first wort": self = .firstWort
        case "aroma": self = .whirlpool
        case "mash": self = .mash
        default: self = .boil
        }
    }
}

extension HopForm {
    var beerXML: String {
        switch self {
        case .pellet: return "Pellet"
        case .leaf: return "Leaf"
        case .cryo: return "Plug"
        }
    }

    init(beerXML: String?) {
        self = beerXML?.lowercased() == "leaf" ? .leaf : .pellet
    }
}

extension HopPurpose {
    var beerXML: String {
        switch self {
        case .bittering: return "Bittering"
        case .aroma: return "Aroma"
        case .dualPurpose: return "Both"
        }
    }

    init(beerXML: String?) {
        switch beerXML?.lowercased() {
        case "bittering": self = .bittering
        case "aroma": self = .aroma
        default: self = .dualPurpose
        }
    }
}

extension YeastType {
    var beerXML: String {
        switch self {
        case .lager: return "Lager"
        case .wheat: return "Wheat"
        case .wine: return "Champagne"
        default: return "Ale"
        }
    }

    init(beerXML: String?) {
        switch beerXML?.lowercased() {
        case "lager": self = .lager
        case "wheat": self = .wheat
        case "wine", "champagne": self = .wine
        default: self = .ale
        }
    }
}

extension MiscType {
    init(beerXML: String?) {
        self = MiscType.allCases.first { $0.displayName.lowercased() == beerXML?.lowercased() } ?? .other
    }
}

extension MiscUse {
    init(beerXML: String?) {
        self = MiscUse(rawValue: beerXML?.lowercased() ?? "") ?? .boil
    }
}

// MARK: - XML helpers

struct XMLBuilder {
    private(set) var output = ""
    private var depth = 1

    mutating func open(_ tag: String) {
        output += String(repeating: "  ", count: depth) + "<\(tag)>\n"
        depth += 1
    }

    mutating func close(_ tag: String) {
        depth -= 1
        output += String(repeating: "  ", count: depth) + "</\(tag)>\n"
    }

    mutating func leaf(_ tag: String, _ value: String) {
        output += String(repeating: "  ", count: depth) + "<\(tag)>\(DocxWriter.escape(value))</\(tag)>\n"
    }

    mutating func leaf(_ tag: String, _ value: Double) {
        let text = value == value.rounded() ? String(Int(value)) : String(format: "%.4f", value)
        leaf(tag, text)
    }

    mutating func leaf(_ tag: String, _ value: Int) {
        leaf(tag, String(value))
    }
}

/// A tiny DOM built with `XMLParser`.
final class XMLTree {
    let name: String
    var text = ""
    var children: [XMLTree] = []

    init(name: String) { self.name = name }

    func child(_ name: String) -> XMLTree? { children.first { $0.name == name } }
    func children(named name: String) -> [XMLTree] { children.filter { $0.name == name } }

    func descendants(named name: String) -> [XMLTree] {
        children.flatMap { $0.name == name ? [$0] : $0.descendants(named: name) }
    }

    func text(_ childName: String) -> String? {
        child(childName)?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func double(_ childName: String) -> Double? {
        text(childName).flatMap { Double($0) }
    }

    static func parse(_ data: Data) -> XMLTree? {
        let delegate = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLTree?
        var stack: [XMLTree] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = XMLTree(name: elementName.uppercased())
            stack.last?.children.append(node)
            if root == nil { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
        }
    }
}
