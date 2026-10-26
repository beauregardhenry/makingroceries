import Foundation

/// Looks up a product name for a barcode in the Open Food Facts database.
/// The barcode is the only thing sent.
enum ProductLookup {
    private struct Response: Decodable {
        struct Product: Decodable { var product_name: String? }
        var status: Int?
        var product: Product?
    }

    static func name(for barcode: String) async throws -> String? {
        guard barcode.allSatisfy(\.isNumber),
              var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")
        else { return nil }
        components.queryItems = [URLQueryItem(name: "fields", value: "product_name")]
        guard let url = components.url else { return nil }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(Response.self, from: data)
        let name = response.product?.product_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false) ? name : nil
    }
}
