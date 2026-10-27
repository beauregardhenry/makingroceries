import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Uses Apple's on-device language model, where the phone has one, to file an item the keyword
/// list couldn't place. Nothing leaves the phone. Without the model, every call returns nil.
enum AisleAI {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static func aisle(for itemName: String) async -> Aisle? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You sort grocery items into the section of a supermarket where they are found. \
            Pick exactly one section for the item you are given.
            """)
        do {
            let response = try await session.respond(to: "Which supermarket section is \"\(itemName)\" in?",
                                                     generating: SectionChoice.self)
            return response.content.aisle
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
@Generable
enum SectionChoice {
    case produce, dairyAndEggs, meatAndSeafood, bakery, pantry, frozen, drinks, household, other

    var aisle: Aisle {
        switch self {
        case .produce: .produce
        case .dairyAndEggs: .dairy
        case .meatAndSeafood: .meat
        case .bakery: .bakery
        case .pantry: .pantry
        case .frozen: .frozen
        case .drinks: .drinks
        case .household: .household
        case .other: .other
        }
    }
}
#endif
