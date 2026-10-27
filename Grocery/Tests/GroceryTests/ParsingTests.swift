import XCTest

final class QuickAddTests: XCTestCase {
    private func parsed(_ text: String, spoken: Bool = false) -> [String] {
        QuickAdd.parse(text, spoken: spoken).map { "\($0.name)×\($0.quantity)" }
    }

    func testPlainList() {
        XCTAssertEqual(parsed("milk, eggs, rice"), ["Milk×1", "Eggs×1", "Rice×1"])
    }

    func testLeadingAndTrailingCounts() {
        XCTAssertEqual(parsed("6 bananas, eggs x2, 3x limes, Soy Sauce"), ["Bananas×6", "Eggs×2", "Limes×3", "Soy Sauce×1"])
    }

    func testMixedSeparators() {
        XCTAssertEqual(parsed("  ,,milk;  bread\ncheese "), ["Milk×1", "Bread×1", "Cheese×1"])
    }

    func testNumbersInsideNamesAreKept() {
        XCTAssertEqual(parsed("7up"), ["7up×1"])
        XCTAssertEqual(parsed("100 apples"), ["100 apples×1"])
    }

    func testSpokenQuantitiesAndAnd() {
        XCTAssertEqual(parsed("two limes and a dozen eggs", spoken: true), ["Limes×2", "Eggs×12"])
        XCTAssertEqual(parsed("Add milk, bread and 3 bananas.", spoken: true), ["Milk×1", "Bread×1", "Bananas×3"])
    }

    func testSpokenArticlesAndTrailingPhrase() {
        XCTAssertEqual(parsed("add an apple to my grocery list", spoken: true), ["Apple×1"])
        XCTAssertEqual(parsed("a loaf of bread", spoken: true), ["Loaf of bread×1"])
    }

    func testWrittenListsKeepAnd() {
        XCTAssertEqual(parsed("mac and cheese"), ["Mac and cheese×1"])
    }

    func testSpokenWrittenForm() {
        XCTAssertEqual(QuickAdd.written(fromSpoken: "two limes and milk"), "2 Limes, Milk")
    }
}

final class AmountTests: XCTestCase {
    func testParsesFractions() {
        XCTAssertEqual(Amount.parse("1 1/2"), 1.5)
        XCTAssertEqual(Amount.parse("1/2"), 0.5)
        XCTAssertEqual(Amount.parse("½"), 0.5)
        XCTAssertEqual(Amount.parse("1½"), 1.5)
        XCTAssertEqual(Amount.parse("2-3"), 2.0)
    }

    func testFormatsFractions() {
        XCTAssertEqual(Amount.format(1.5), "1½")
        XCTAssertEqual(Amount.format(2), "2")
        XCTAssertEqual(Amount.format(1.0 / 3), "⅓")
        XCTAssertEqual(Amount.format(2.6667), "2⅔")
        XCTAssertEqual(Amount.format(3.98), "4")
        XCTAssertEqual(Amount.format(0.2), "0.2")
    }

    func testUnitLabels() {
        XCTAssertEqual(Amount.text(1, unit: "cup"), "1 cup")
        XCTAssertEqual(Amount.text(2, unit: "cup"), "2 cups")
        XCTAssertEqual(Amount.text(2, unit: "tbsp"), "2 tbsp")
        XCTAssertEqual(Amount.text(2, unit: "bunch"), "2 bunches")
        XCTAssertEqual(Amount.text(0.5, unit: "cup"), "½ cup")
    }

    func testScalingIngredients() {
        let flour = MealIngredient(name: "Flour", quantity: 1, amount: 2, unit: "cup")
        XCTAssertEqual(flour.scaled(by: 2).note, "4 cups")
        XCTAssertEqual(flour.scaled(by: 0.5).note, "1 cup")
        XCTAssertEqual(flour.scaled(by: 3).quantity, 1)
        let eggs = MealIngredient(name: "Eggs", quantity: 3)
        XCTAssertEqual(eggs.scaled(by: 2).quantity, 6)
        XCTAssertEqual(eggs.scaled(by: 0.5).quantity, 2)
        XCTAssertEqual(MealIngredient(name: "Lime", quantity: 1).scaled(by: 0.5).quantity, 1)
    }
}

final class RecipeParserTests: XCTestCase {
    private func summary(_ lines: [RecipeLine]) -> [String] {
        lines.map { $0.unit != nil ? "\($0.name)|\(Amount.text($0.amount!, unit: $0.unit!))" : "\($0.name)×\($0.quantity)" }
    }

    func testIngredientsKeepAmountsAndSkipHeadingsAndSteps() {
        let text = """
        Ingredients
        2 cups all-purpose flour
        1 1/2 tsp baking powder
        1/2 cup (120 ml) milk, warmed
        3 eggs
        1 can (14 oz) diced tomatoes
        Salt to taste
        ½ cup sugar
        2-3 cloves garlic
        Olive oil
        Serves 4
        Directions
        1. Preheat the oven to 400 degrees.
        """
        XCTAssertEqual(summary(RecipeParser.fromText(text)), [
            "All-purpose flour|2 cups", "Baking powder|1½ tsp", "Milk|½ cup", "Eggs×3", "Diced tomatoes|1 can",
            "Salt×1", "Sugar|½ cup", "Garlic|2 cloves", "Olive oil×1",
        ])
    }

    func testWrappedLinesAreJoined() {
        XCTAssertEqual(RecipeParser.joinWrappedLines(["1/2 cup olive oil,", "divided", "4 cloves garlic"]),
                       ["1/2 cup olive oil, divided", "4 cloves garlic"])
    }

    func testWebPageRecipeData() {
        let html = """
        <script type="application/ld+json">{"@type":"Recipe","name":"Mom&#39;s Pancakes","recipeIngredient":["1 cup flour","2 eggs","1 &amp; 1/2 cups milk","Ingredients:"]}</script>
        """
        let recipe = RecipeParser.fromHTML(html)
        XCTAssertEqual(recipe?.name, "Mom's Pancakes")
        XCTAssertEqual(recipe?.lines.count, 3)
        XCTAssertNil(RecipeParser.fromHTML("<html>no recipe</html>"))
    }

    func testRecipeFetcherAddressChecks() {
        XCTAssertEqual(RecipeFetcher.normalized("example.com/recipe")?.absoluteString, "https://example.com/recipe")
        XCTAssertNil(RecipeFetcher.normalized("ftp://x.com"))
        XCTAssertNil(RecipeFetcher.normalized("   "))
    }
}

final class AisleGuessTests: XCTestCase {
    func testKeywordsPickTheRightAisle() {
        XCTAssertEqual(Aisle.guess(fromCategories: ["en:frozen-vegetables"]), .frozen)
        XCTAssertEqual(Aisle.guess(fromCategories: ["en:sweet-spreads"]), .pantry)
        XCTAssertEqual(Aisle.guess(fromCategories: ["en:Spinach"]), .produce)
        XCTAssertNil(Aisle.guess(fromCategories: ["en:mystery"]))
    }

    func testStemmingCatchesPluralsAndTypos() {
        XCTAssertEqual(GroceryStore.stem("Tomatoes"), "tomato")
        XCTAssertEqual(GroceryStore.stem("berries"), "berry")
        XCTAssertEqual(GroceryStore.distance("tomato", "tomatos"), 1)
    }
}
