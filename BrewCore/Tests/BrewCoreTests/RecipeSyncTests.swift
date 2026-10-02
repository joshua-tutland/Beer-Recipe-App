import XCTest
@testable import BrewCore

final class RecipeSyncTests: XCTestCase {
    private func recipe(_ name: String, id: UUID = UUID(), modified: TimeInterval) -> Recipe {
        Recipe(id: id, name: name, modifiedAt: Date(timeIntervalSince1970: modified))
    }

    func testUploadsNewAndNewerRecipesOnly() {
        let shared = UUID()
        let olderShared = UUID()
        let local = [recipe("Only here", modified: 10),
                     recipe("Edited here", id: shared, modified: 50),
                     recipe("Stale here", id: olderShared, modified: 5)]
        let remote = [recipe("Edited elsewhere", id: shared, modified: 40),
                      recipe("Fresh elsewhere", id: olderShared, modified: 60),
                      recipe("Only there", modified: 1)]
        let upload = RecipeSync.recipesToUpload(local: local, remote: remote).map(\.name)
        XCTAssertEqual(Set(upload), ["Only here", "Edited here"])
    }

    func testMergedKeepsNewestCopyOfEach() {
        let id = UUID()
        let merged = RecipeSync.merged([recipe("Old", id: id, modified: 1), recipe("A", modified: 5)],
                                       [recipe("New", id: id, modified: 9)])
        XCTAssertEqual(merged.map(\.name), ["New", "A"])
    }

    func testWinningConflictVersionIsTheNewestReadableCopy() throws {
        let id = UUID()
        let older = try RecipeRepository.encode(recipe("Phone edit", id: id, modified: 100))
        let newer = try RecipeRepository.encode(recipe("iPad edit", id: id, modified: 200))
        XCTAssertEqual(RecipeSync.winningVersion([older, Data("garbage".utf8), newer]), 2)
        XCTAssertEqual(RecipeSync.winningVersion([newer, older]), 0)
        XCTAssertNil(RecipeSync.winningVersion([Data()]))
    }

    func testCoordinatedRepositoryRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Recipes")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let repo = RecipeRepository(directory: dir, usesFileCoordination: true)
        let recipe = SampleRecipes.paleAle
        try repo.save(recipe)
        XCTAssertEqual(repo.loadAll().map(\.id), [recipe.id])

        // Placeholders for files iCloud hasn't downloaded yet are ignored.
        try Data("x".utf8).write(to: dir.appendingPathComponent(".\(UUID().uuidString).json.icloud"))
        XCTAssertEqual(repo.loadAll().count, 1)

        let sidecar = repo.supportDirectory.appendingPathComponent("inventory.json")
        try repo.writeFile(Data("[]".utf8), to: sidecar)
        XCTAssertEqual(repo.readFile(sidecar), Data("[]".utf8))

        try repo.delete(id: recipe.id)
        XCTAssertTrue(repo.loadAll().isEmpty)
    }
}
