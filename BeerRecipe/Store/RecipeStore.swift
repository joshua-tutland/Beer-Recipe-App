import Foundation
import Observation
import SwiftUI
import BrewCore

/// Owns the brewer's recipes and custom ingredients and keeps them saved on device.
@Observable
final class RecipeStore {
    private(set) var recipes: [Recipe] = []
    private(set) var custom = CustomIngredients()
    private(set) var defaultEquipment = Equipment()
    /// The brewer's own tap water report, used as the starting water for new water plans.
    private(set) var myWater: WaterProfile?
    /// Ingredients on hand.
    private(set) var inventory: [InventoryItem] = []

    @ObservationIgnored private let repository: RecipeRepository
    @ObservationIgnored private var pendingSaves: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard

    private var inventoryURL: URL {
        repository.directory.deletingLastPathComponent().appendingPathComponent("inventory.json")
    }

    private var customURL: URL {
        CustomIngredients.fileURL(in: repository.directory.deletingLastPathComponent())
    }

    private static let seededKey = "didSeedSampleRecipes"
    private static let equipmentKey = "defaultEquipment"
    private static let myWaterKey = "myWaterProfile"

    init(repository: RecipeRepository = .documents()) {
        self.repository = repository
        recipes = repository.loadAll()
        custom = CustomIngredients.load(from: customURL)
        if let data = try? Data(contentsOf: inventoryURL),
           let items = try? JSONDecoder().decode([InventoryItem].self, from: data) {
            inventory = items
        }
        if let data = defaults.data(forKey: Self.equipmentKey),
           let equipment = try? JSONDecoder().decode(Equipment.self, from: data) {
            defaultEquipment = equipment
        }
        if let data = defaults.data(forKey: Self.myWaterKey),
           let water = try? JSONDecoder().decode(WaterProfile.self, from: data) {
            myWater = water
        }
        if recipes.isEmpty && !defaults.bool(forKey: Self.seededKey) {
            SampleRecipes.all.reversed().forEach { add($0) }
            defaults.set(true, forKey: Self.seededKey)
        }
    }

    // MARK: Recipes

    func recipe(id: UUID) -> Recipe? { recipes.first { $0.id == id } }

    /// A binding that edits the stored recipe and autosaves it.
    func binding(for id: UUID) -> Binding<Recipe>? {
        guard let current = recipe(id: id) else { return nil }
        return Binding(
            get: { [weak self] in self?.recipe(id: id) ?? current },
            set: { [weak self] in self?.update($0) }
        )
    }

    @discardableResult
    func newRecipe(type: RecipeType = .allGrain) -> Recipe {
        var recipe = Recipe(name: "New Recipe", type: type, equipment: defaultEquipment)
        if type == .extract { recipe.mashSteps = [] }
        add(recipe)
        return recipe
    }

    func add(_ recipe: Recipe) {
        recipes.insert(recipe, at: 0)
        persist(recipe)
    }

    func update(_ recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        guard recipes[index] != recipe else { return }
        var updated = recipe
        updated.modifiedAt = Date()
        recipes[index] = updated
        scheduleSave(updated)
    }

    @discardableResult
    func duplicate(id: UUID) -> Recipe? {
        guard let original = recipe(id: id) else { return nil }
        let copy = original.duplicated()
        add(copy)
        return copy
    }

    func delete(ids: [UUID]) {
        for id in ids {
            pendingSaves[id]?.cancel()
            pendingSaves[id] = nil
            try? repository.delete(id: id)
        }
        recipes.removeAll { ids.contains($0.id) }
    }

    func restoreSamples() {
        SampleRecipes.all.reversed().forEach { add($0) }
    }

    /// Imports every recipe in a BeerXML file and returns them.
    func importBeerXML(from url: URL) throws -> [Recipe] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let imported = try BeerXML.importRecipes(from: Data(contentsOf: url))
        imported.reversed().forEach { add($0) }
        return imported
    }

    private func persist(_ recipe: Recipe) {
        do {
            try repository.save(recipe)
        } catch {
            print("Failed to save recipe \(recipe.name): \(error)")
        }
    }

    /// Debounces disk writes while the user is typing.
    private func scheduleSave(_ recipe: Recipe) {
        pendingSaves[recipe.id]?.cancel()
        pendingSaves[recipe.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            if let latest = self.recipe(id: recipe.id) { self.persist(latest) }
            self.pendingSaves[recipe.id] = nil
        }
    }

    /// Writes anything still waiting in the debounce window (called when the app backgrounds).
    func flushPendingSaves() {
        for id in pendingSaves.keys {
            pendingSaves[id]?.cancel()
            if let recipe = recipe(id: id) { persist(recipe) }
        }
        pendingSaves.removeAll()
    }

    // MARK: Settings

    func updateDefaultEquipment(_ equipment: Equipment) {
        defaultEquipment = equipment
        if let data = try? JSONEncoder().encode(equipment) {
            defaults.set(data, forKey: Self.equipmentKey)
        }
    }

    func saveMyWater(_ profile: WaterProfile) {
        var water = profile
        water.id = "my-water"
        water.name = "My Water"
        myWater = water
        if let data = try? JSONEncoder().encode(water) {
            defaults.set(data, forKey: Self.myWaterKey)
        }
    }

    /// Starting-water choices: the brewer's own water first, then the bundled profiles.
    var sourceWaterProfiles: [WaterProfile] {
        (myWater.map { [$0] } ?? []) + WaterProfiles.sources
    }

    // MARK: Inventory

    func addInventory(_ item: InventoryItem) {
        // Same ingredient, unit and lot details → top up the existing entry.
        if let i = inventory.firstIndex(where: {
            $0.kind == item.kind && $0.ingredientId == item.ingredientId && $0.unit == item.unit
                && $0.alphaAcid == item.alphaAcid && $0.bestBefore == item.bestBefore
        }) {
            inventory[i].amount += item.amount
        } else {
            inventory.append(item)
        }
        saveInventory()
    }

    func updateInventory(_ item: InventoryItem) {
        guard let i = inventory.firstIndex(where: { $0.id == item.id }) else { return }
        inventory[i] = item
        saveInventory()
    }

    func deleteInventory(ids: [UUID]) {
        inventory.removeAll { ids.contains($0.id) }
        saveInventory()
    }

    func setInventory(_ items: [InventoryItem]) {
        inventory = items
        saveInventory()
    }

    private func saveInventory() {
        do {
            try FileManager.default.createDirectory(at: inventoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(inventory).write(to: inventoryURL, options: [.atomic])
        } catch {
            print("Failed to save inventory: \(error)")
        }
    }

    // MARK: Ingredient library (bundled + custom)

    var allFermentables: [Fermentable] { custom.fermentables + IngredientCatalog.fermentables }
    var allHops: [Hop] { custom.hops + IngredientCatalog.hops }
    var allYeasts: [Yeast] { custom.yeasts + IngredientCatalog.yeasts }
    var allMiscs: [Misc] { custom.miscs + IngredientCatalog.miscs }

    func isCustom(id: String) -> Bool {
        custom.fermentables.contains { $0.id == id } || custom.hops.contains { $0.id == id }
            || custom.yeasts.contains { $0.id == id } || custom.miscs.contains { $0.id == id }
    }

    func addCustom(_ fermentable: Fermentable) { custom.fermentables.insert(fermentable, at: 0); saveCustom() }
    func addCustom(_ hop: Hop) { custom.hops.insert(hop, at: 0); saveCustom() }
    func addCustom(_ yeast: Yeast) { custom.yeasts.insert(yeast, at: 0); saveCustom() }
    func addCustom(_ misc: Misc) { custom.miscs.insert(misc, at: 0); saveCustom() }

    func deleteCustom(id: String) {
        custom.fermentables.removeAll { $0.id == id }
        custom.hops.removeAll { $0.id == id }
        custom.yeasts.removeAll { $0.id == id }
        custom.miscs.removeAll { $0.id == id }
        saveCustom()
    }

    private func saveCustom() {
        try? custom.save(to: customURL)
    }
}
