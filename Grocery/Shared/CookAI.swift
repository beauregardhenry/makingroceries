import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Asks Apple's on-device language model for dishes that use what's at home, the soonest-to-spoil first.
/// Nothing leaves the phone. Without the model, it returns no ideas.
enum CookAI {
    static var isAvailable: Bool { AisleAI.isAvailable }

    static func ideas(have: [String], useFirst: [String]) async -> [CookIdea] {
        #if canImport(FoundationModels)
        guard isAvailable, !have.isEmpty else { return [] }
        let session = LanguageModelSession(instructions: """
            You suggest simple home-cooked dishes. Use the ingredients the person has, especially the ones \
            to use first. Assume basic staples like salt, pepper, oil and water. Keep extra ingredients to \
            buy few and common. Write in plain, friendly English.
            """)
        let prompt = """
            Ingredients at home: \(have.joined(separator: ", ")).
            Use these first: \(useFirst.isEmpty ? "nothing in particular" : useFirst.joined(separator: ", ")).
            Suggest three dishes.
            """
        do {
            let response = try await session.respond(to: prompt, generating: DishList.self)
            return response.content.dishes.prefix(3).map {
                CookIdea(title: $0.name, uses: $0.usesFromHome, extras: $0.toBuy, summary: $0.howTo)
            }
        } catch {
            return []
        }
        #else
        return []
        #endif
    }
}

#if canImport(FoundationModels)
@Generable
struct DishList {
    @Guide(description: "Three dishes", .count(3))
    var dishes: [Dish]
}

@Generable
struct Dish {
    @Guide(description: "A short dish name, like Spinach and Feta Omelet")
    var name: String
    @Guide(description: "Ingredients from the list at home that the dish uses")
    var usesFromHome: [String]
    @Guide(description: "Up to three common ingredients to buy, or none")
    var toBuy: [String]
    @Guide(description: "One or two sentences on how to make it")
    var howTo: String
}
#endif
