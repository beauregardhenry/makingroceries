import Foundation

struct ScannedProduct {
    let name: String
    /// Nil when the product's categories don't map to one of our aisles.
    let aisle: Aisle?
    /// Package size as printed, like "16 oz" or "500 g".
    var size: String? = nil
    /// Allergen tags such as "en:peanuts".
    var allergens: [String] = []
    var ingredients: String? = nil
}

/// Looks up a product in the Open Food Facts database.
/// The barcode is the only thing sent.
enum ProductLookup {
    private struct Response: Decodable {
        struct Product: Decodable {
            var product_name: String?
            var categories_tags: [String]?
            var quantity: String?
            var allergens_tags: [String]?
            var ingredients_text: String?
        }
        var product: Product?
    }

    static func product(for barcode: String) async throws -> ScannedProduct? {
        guard barcode.allSatisfy(\.isNumber),
              var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")
        else { return nil }
        components.queryItems = [URLQueryItem(name: "fields", value: "product_name,categories_tags,quantity,allergens_tags,ingredients_text")]
        guard let url = components.url else { return nil }

        let (data, _) = try await URLSession.shared.data(from: url)
        let product = try JSONDecoder().decode(Response.self, from: data).product
        guard let name = product?.product_name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        return ScannedProduct(name: name, aisle: Aisle.guess(fromCategories: product?.categories_tags ?? []),
                              size: product?.quantity, allergens: product?.allergens_tags ?? [],
                              ingredients: product?.ingredients_text)
    }
}

extension Aisle {
    /// Keyword rules (matched against the start of each word in the category tags) checked in order, so "frozen vegetables" lands in Frozen, not Produce.
    private static let rules: [(Aisle, [String])] = [
        (.frozen, ["frozen", "ice-cream"]),
        (.drinks, ["beverage", "water", "juice", "soda", "tea", "coffee", "beer", "wine"]),
        (.dairy, ["dair", "milk", "cheese", "yogurt", "yoghurt", "egg", "butter", "cream"]),
        (.meat, ["meat", "fish", "seafood", "poultry", "sausage", "ham", "chicken", "beef", "pork"]),
        (.bakery, ["bread", "bakery", "pastr", "viennoiserie", "baguette"]),
        (.produce, ["fruit", "vegetable", "salad", "herb", "apple", "banana", "lime", "lemon", "orange", "tomato",
                    "onion", "potato", "garlic", "carrot", "lettuce", "spinach", "avocado", "cucumber",
                    "broccoli", "grape", "berr", "mango", "celery", "cabbage", "mushroom"]),
        (.pantry, ["spread", "cereal", "pasta", "rice", "canned", "snack", "sauce", "chocolate",
                   "biscuit", "cookie", "condiment", "oil", "flour", "sugar", "legume", "soup", "jam"]),
        (.household, ["cleaning", "household", "paper", "detergent"]),
    ]

    static func guess(fromCategories tags: [String]) -> Aisle? {
        let words = tags.flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter }) }
        for (aisle, keywords) in rules where words.contains(where: { word in keywords.contains(where: word.hasPrefix) }) {
            return aisle
        }
        return nil
    }
}
