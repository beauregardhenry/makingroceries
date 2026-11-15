import XCTest

@MainActor
final class AllergyTests: StoreTestCase {
    func testAllergiesAreGroupedByCategoryAndAlphabetized() {
        for name in ["walnuts", "Shrimp", "milk", "Peanuts", "Sulfites", "Cashews", "Glitter"] { store.addAllergy(named: name) }
        let groups = store.allergyGroups
        XCTAssertEqual(groups.map(\.category), [.nuts, .dairy, .seafood, .additives, .other])
        XCTAssertEqual(groups[0].allergies.map(\.name), ["Cashews", "Peanuts", "Walnuts"])
        XCTAssertEqual(groups[1].allergies.map(\.name), ["Milk"])
    }

    func testEveryCategoryAndReactionHasAnIconAndAName() {
        for category in AllergyCategory.allCases {
            XCTAssertFalse(category.symbol.isEmpty)
            XCTAssertEqual(category.id, category.rawValue)
        }
        for reaction in AllergyReaction.allCases {
            XCTAssertFalse(reaction.symbol.isEmpty)
            XCTAssertEqual(reaction.id, reaction.rawValue)
        }
        XCTAssertEqual(AllergyReaction.allCases.filter(\.isSevere), [.anaphylaxis, .breathing])
    }

    func testChangesToAMissingAllergyAreIgnored() {
        store.toggleReaction(.hives, for: UUID())
        store.setCategory(.meat, for: UUID())
        XCTAssertTrue(store.allergies.isEmpty)
    }

    func testCategoriesAreGuessedFromTheName() {
        let expected: [String: AllergyCategory] = [
            "Tree Nuts": .nuts, "Coconut": .produce, "Nutmeg": .seeds, "Eggs": .eggs, "Oats": .grains,
            "Clams": .seafood, "Chickpeas": .soy, "Sesame": .seeds, "Strawberries": .produce, "Gelatin": .meat,
            "Red Dye": .additives, "MSG": .additives, "Chocolate": .other,
        ]
        for (name, category) in expected {
            XCTAssertEqual(AllergyCategory.guess(for: name), category, name)
        }
    }

    func testAddingIsTitleCasedAndSkipsDuplicates() {
        XCTAssertEqual(store.addAllergy(named: "tree nuts")?.name, "Tree Nuts")
        XCTAssertNil(store.addAllergy(named: "Tree Nut"))
        XCTAssertNil(store.addAllergy(named: "ab"))
        XCTAssertEqual(store.allergies.count, 1)
    }

    func testReactionsAreToggledAndListedInOrder() throws {
        let peanuts = try XCTUnwrap(store.addAllergy(named: "Peanuts"))
        store.toggleReaction(.hives, for: peanuts.id)
        store.toggleReaction(.anaphylaxis, for: peanuts.id)
        XCTAssertEqual(store.allergies[0].reactionList, [.anaphylaxis, .hives])
        store.toggleReaction(.hives, for: peanuts.id)
        store.toggleReaction(.anaphylaxis, for: peanuts.id)
        XCTAssertNil(store.allergies[0].reactions)
    }

    func testCategoryCanBeChangedAndPutBack() throws {
        let chocolate = try XCTUnwrap(store.addAllergy(named: "Chocolate"))
        store.setCategory(.additives, for: chocolate.id)
        XCTAssertEqual(store.allergies[0].category, .additives)
        store.setCategory(.other, for: chocolate.id)
        XCTAssertNil(store.allergies[0].categoryOverride)
    }

    func testWarningsNameASevereReaction() throws {
        let peanuts = try XCTUnwrap(store.addAllergy(named: "Peanuts"))
        store.addAllergy(named: "Milk")
        XCTAssertEqual(store.allergyWarning(allergens: ["en:milk"], ingredients: nil), "Contains milk")
        store.toggleReaction(.anaphylaxis, for: peanuts.id)
        XCTAssertEqual(store.allergyWarning(allergens: ["en:peanuts"], ingredients: nil),
                       "Contains peanuts. Severe reaction: peanuts")
        XCTAssertNil(store.allergyWarning(allergens: ["en:soybeans"], ingredients: "water"))
    }

    func testTheOldOnPhoneListMovesIntoAllergiesOnce() {
        let defaults = UserDefaults(suiteName: "AllergyTests")!
        defaults.removePersistentDomain(forName: "AllergyTests")
        defaults.set(["gluten", "Peanuts", "peanut"], forKey: "avoidWords")
        store.moveOldAvoidList(defaults: defaults)
        XCTAssertEqual(store.allergies.map(\.name), ["Gluten", "Peanuts"])
        XCTAssertNil(defaults.stringArray(forKey: "avoidWords"))
        store.moveOldAvoidList(defaults: defaults)
        XCTAssertEqual(store.allergies.count, 2)
    }

    func testAllergiesAreBackedUpAndOldBackupsKeepThem() {
        store.addAllergy(named: "Soy")
        var backup = store.makeBackup()
        XCTAssertEqual(backup.allergies?.map(\.name), ["Soy"])
        backup.allergies = nil
        store.restore(backup)
        XCTAssertEqual(store.allergies.map(\.name), ["Soy"])
    }

    func testJoiningAFamilyListDoesNotListAnAllergyTwice() throws {
        store.addAllergy(named: "Peanuts")
        let family = Allergy(name: "peanut")
        let data = try JSONEncoder().encode([family])
        store.adoptFamilyIDs(name: "allergies", remote: data)
        XCTAssertNotNil(store.applyCloudCopy(name: "allergies", remote: data, base: nil))
        XCTAssertEqual(store.allergies.map(\.id), [family.id])
    }
}

@MainActor
final class HouseholdSettingsTests: StoreTestCase {
    func testBudgetAndMonthlySavingsAreSavedAndCleared() {
        XCTAssertNil(store.monthlyBudget)
        XCTAssertEqual(store.savePerMonth, 0)
        store.monthlyBudget = 450
        store.savePerMonth = 75
        XCTAssertEqual(store.monthlyBudget, 450)
        XCTAssertEqual(store.savePerMonth, 75)
        store.monthlyBudget = 0
        XCTAssertNil(store.monthlyBudget)
        store.savePerMonth = 75
        XCTAssertEqual(store.settings.count, 2)
    }

    func testOldOnPhoneSettingsMoveOverOnce() {
        let defaults = UserDefaults(suiteName: "HouseholdSettingsTests")!
        defaults.removePersistentDomain(forName: "HouseholdSettingsTests")
        defaults.set(250.0, forKey: "monthlyBudget")
        defaults.set(0.0, forKey: "savePerMonth")
        store.moveOldSettings(defaults: defaults)
        XCTAssertEqual(store.monthlyBudget, 250)
        XCTAssertEqual(store.savePerMonth, 0)
        XCTAssertNil(defaults.object(forKey: "monthlyBudget"))
        XCTAssertNil(defaults.object(forKey: "savePerMonth"))
    }

    func testSettingsAreBackedUp() {
        store.monthlyBudget = 500
        var backup = store.makeBackup()
        XCTAssertEqual(backup.settings?.first?.number, 500)
        backup.settings = nil
        store.restore(backup)
        XCTAssertEqual(store.monthlyBudget, 500)
    }
}
