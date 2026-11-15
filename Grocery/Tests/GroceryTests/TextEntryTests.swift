import XCTest

@MainActor
final class TitleCaseTests: XCTestCase {
    func testEachWordStartsWithACapital() {
        XCTAssertEqual(TitleCase.apply("green apples"), "Green Apples")
        XCTAssertEqual(TitleCase.apply("trader joe's  frozen peas"), "Trader Joe's  Frozen Peas")
        XCTAssertEqual(TitleCase.apply("2% milk (organic)"), "2% Milk (Organic)")
    }

    func testCapitalsAlreadyTypedAreKept() {
        XCTAssertEqual(TitleCase.apply("BBQ sauce"), "BBQ Sauce")
        XCTAssertEqual(TitleCase.apply("McCormick pepper"), "McCormick Pepper")
        XCTAssertEqual(TitleCase.apply(""), "")
    }
}

@MainActor
final class PluralFormsTests: XCTestCase {
    func testSingularAndPluralAreTheSame() {
        for (a, b) in [("Apple", "apples"), ("Cookie", "Cookies"), ("Berry", "berries"), ("Peach", "Peaches"),
                       ("Tomato", "Tomatoes"), ("Green Apple", "green apples "), ("Cheese", "Cheeses"), ("Peas", "pea")] {
            XCTAssertTrue(GroceryStore.same(a, b), "\(a) / \(b)")
        }
    }

    func testDifferentThingsStayDifferent() {
        XCTAssertFalse(GroceryStore.same("Glass", "Gla"))
        XCTAssertFalse(GroceryStore.same("Milk", "Silk"))
        XCTAssertFalse(GroceryStore.same("Bus", "Bu"))
    }
}

@MainActor
final class SingularPluralStoreTests: StoreTestCase {
    func testAddingThePluralRaisesTheSameItem() {
        store.addOrBump(name: "Apple", shopID: nil)
        store.addOrBump(name: "apples", quantity: 2, shopID: nil)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].quantity, 3)
        XCTAssertTrue(store.isOnList("Apples"))
    }

    func testNamesAreSavedInTitleCase() {
        store.addOrBump(name: "frozen peas", shopID: nil)
        XCTAssertEqual(store.items[0].name, "Frozen Peas")
        XCTAssertEqual(store.addShop(named: "corner shop")?.name, "Corner Shop")
        XCTAssertEqual(store.addCustomAisle(named: "bulk bins")?.name, "Bulk Bins")
        XCTAssertEqual(store.addPerson(named: "sam")?.name, "Sam")
        XCTAssertEqual(store.addRegistryPerson(named: "aunt may")?.name, "Aunt May")
        store.addFavorite(name: "oat milk")
        XCTAssertEqual(store.favorites.first?.name, "Oat Milk")
        XCTAssertEqual(store.makeMeal(named: "taco night", fromLines: "2 avocados").ingredients.first?.name, "Avocados")
        XCTAssertEqual(store.makeMeal(named: "taco night", fromLines: "").name, "Taco Night")
    }

    func testAPluralOfSomeoneAlreadyAddedIsNotAddedAgain() {
        XCTAssertNotNil(store.addCustomAisle(named: "Snack"))
        XCTAssertNil(store.addCustomAisle(named: "snacks"))
    }
}

@MainActor
final class SpellingTests: StoreTestCase {
    private static let dictionary = ["bananna": "banana", "brocoli": "broccoli", "pepar": "paper"]
    private static func correct(_ word: String) -> String? { dictionary[word.lowercased()] }

    func testAMisspelledWordGetsASuggestion() {
        XCTAssertEqual(Spelling.suggestion(for: "brocoli", known: [], correct: Self.correct), "Broccoli")
        XCTAssertEqual(Spelling.suggestion(for: "ripe bananna", known: [], correct: Self.correct), "Ripe Banana")
    }

    func testANameYouUsedBeforeWinsOverTheDictionary() {
        XCTAssertEqual(Spelling.suggestion(for: "Clementinez", known: ["Clementines"], correct: Self.correct), "Clementines")
        XCTAssertNil(Spelling.suggestion(for: "clementine", known: ["Clementines"], correct: Self.correct))
    }

    func testWordsYouAlreadyUseAreNeverCorrected() {
        XCTAssertNil(Spelling.suggestion(for: "Pepar Towels", known: ["Pepar Napkins"], correct: Self.correct))
    }

    func testShortOrCorrectNamesGetNothing() {
        XCTAssertNil(Spelling.suggestion(for: "egs", known: [], correct: Self.correct))
        XCTAssertNil(Spelling.suggestion(for: "Milk", known: [], correct: Self.correct))
        XCTAssertNil(Spelling.suggestion(for: "6-pack cola", known: [], correct: Self.correct))
    }

    func testTheStoreChecksTheListAndHistory() {
        store.addOrBump(name: "Asparagus", shopID: nil)
        XCTAssertEqual(store.spellingSuggestion(for: "Asparagos", correct: Self.correct), "Asparagus")
    }

    func testThePhonesDictionaryIsUsed() throws {
        guard let fix = Spelling.systemCorrection("bananna") else { throw XCTSkip("No spelling dictionary on this simulator") }
        XCTAssertEqual(fix.lowercased(), "banana")
        XCTAssertNil(Spelling.systemCorrection("banana"))
    }
}

@MainActor
final class AllergenSuggestionTests: XCTestCase {
    func testBeforeTypingTheMajorAllergensAreOffered() {
        let offered = AllergenSuggestions.matches(for: "", excluding: [])
        XCTAssertEqual(offered.first, "Peanuts")
        XCTAssertEqual(offered.count, 9)
    }

    func testTypingNarrowsTheSuggestions() {
        XCTAssertEqual(AllergenSuggestions.matches(for: "sh", excluding: []).first, "Shellfish")
        let nuts = AllergenSuggestions.matches(for: "nut", excluding: [])
        XCTAssertTrue(nuts.contains("Tree Nuts"))
        XCTAssertTrue(nuts.contains("Peanuts"))
        XCTAssertLessThan(nuts.firstIndex(of: "Tree Nuts")!, nuts.firstIndex(of: "Peanuts")!)
    }

    func testWhatYouAlreadyAvoidIsNotSuggested() {
        XCTAssertFalse(AllergenSuggestions.matches(for: "pea", excluding: ["peanut"]).contains("Peanuts"))
        XCTAssertTrue(AllergenSuggestions.matches(for: "zzz", excluding: []).isEmpty)
    }
}
