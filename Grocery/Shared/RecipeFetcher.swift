import Foundation

/// Downloads a recipe web page and reads its ingredients. Only the address you give is contacted.
enum RecipeFetcher {
    enum Result {
        case found(RecipeParser.Recipe)
        case noRecipe
        case unreachable
        case badAddress
    }

    static func normalized(_ address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("://") {
            guard text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") else { return nil }
        } else {
            text = "https://" + text
        }
        guard let url = URL(string: text), url.scheme == "https" || url.scheme == "http", url.host() != nil else { return nil }
        return url
    }

    static func fetch(_ url: URL, session: URLSession = .shared) async -> Result {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request) else { return .unreachable }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return .unreachable }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let recipe = RecipeParser.fromHTML(html) else { return .noRecipe }
        return .found(recipe)
    }

    static func fetch(address: String, session: URLSession = .shared) async -> Result {
        guard let url = normalized(address) else { return .badAddress }
        return await fetch(url, session: session)
    }
}
