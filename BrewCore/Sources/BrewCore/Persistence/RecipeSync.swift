import Foundation

/// Merge rules for syncing recipe files between devices: recipes are matched by id and the
/// most recently modified copy wins.
public enum RecipeSync {
    /// Recipes from `local` that should be written to `remote` because they're missing there or newer.
    public static func recipesToUpload(local: [Recipe], remote: [Recipe]) -> [Recipe] {
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.modifiedAt >= b.modifiedAt ? a : b })
        return local.filter { recipe in
            guard let existing = remoteByID[recipe.id] else { return true }
            return recipe.modifiedAt > existing.modifiedAt
        }
    }

    /// The union of both sides, newest copy of each recipe, newest first.
    public static func merged(_ a: [Recipe], _ b: [Recipe]) -> [Recipe] {
        var byID: [UUID: Recipe] = [:]
        for recipe in a + b {
            if let existing = byID[recipe.id], existing.modifiedAt >= recipe.modifiedAt { continue }
            byID[recipe.id] = recipe
        }
        return byID.values.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Given the contents of conflicting copies of one recipe file (iCloud keeps a version per
    /// device), the index of the copy to keep: the newest readable recipe. Unreadable copies lose.
    public static func winningVersion(_ candidates: [Data]) -> Int? {
        var best: (index: Int, modified: Date)?
        for (index, data) in candidates.enumerated() {
            guard let recipe = try? RecipeRepository.decode(data) else { continue }
            if best == nil || recipe.modifiedAt > best!.modified {
                best = (index, recipe.modifiedAt)
            }
        }
        return best?.index
    }
}
