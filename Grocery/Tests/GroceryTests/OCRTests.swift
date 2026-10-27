import XCTest
import UIKit

/// Draws a receipt and a recipe into an image and reads them back with the on-device text recognition.
final class OCRTests: XCTestCase {
    private func render(_ lines: [(String, String?)]) -> CGImage {
        let size = CGSize(width: 700, height: CGFloat(lines.count) * 50 + 80)
        let font = UIFont.monospacedSystemFont(ofSize: 28, weight: .regular)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (i, line) in lines.enumerated() {
                let y = 40 + CGFloat(i) * 50
                (line.0 as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: font, .foregroundColor: UIColor.black])
                if let price = line.1 {
                    let width = (price as NSString).size(withAttributes: [.font: font]).width
                    (price as NSString).draw(at: CGPoint(x: size.width - 40 - width, y: y), withAttributes: [.font: font, .foregroundColor: UIColor.black])
                }
            }
        }
        return image.cgImage!
    }

    func testReceiptRowsJoinItemsToPrices() throws {
        let image = render([("KROGER", nil), ("BANANAS", "1.74"), ("6 @ 0.29", nil), ("BNLS CHKN THIGH", "7.99"),
                            ("MILK 2% GAL", "3.49 F"), ("SUBTOTAL", "13.22"), ("TOTAL", "13.22"), ("VISA ****1234", "13.22")])
        let rows = try RecipeOCR.rows(in: image)
        let entries = ReceiptParser.parse(rows: rows)
        XCTAssertEqual(entries.map(\.name), ["Bananas", "Bnls Chkn Thigh", "Milk 2% Gal"], "rows: \(rows)")
        XCTAssertEqual(entries.first?.quantity, 6)
        XCTAssertEqual(ReceiptParser.total(rows: rows), 13.22)
    }

    func testRecipePageGivesJustTheIngredients() throws {
        let image = render([("Lemon Garlic Chicken", nil), ("Serves 4", nil), ("INGREDIENTS", nil), ("2 cups all-purpose flour", nil),
                            ("3 chicken breasts, boned", nil), ("4 cloves garlic", nil), ("DIRECTIONS", nil), ("1. Preheat the oven to 400 degrees.", nil)])
        let lines = RecipeParser.joinWrappedLines(try RecipeOCR.lines(in: image))
        let parsed = RecipeParser.fromText(lines.joined(separator: "\n"))
        XCTAssertEqual(parsed.map(\.name), ["All-purpose flour", "Chicken breasts", "Garlic"], "lines: \(lines)")
        XCTAssertEqual(parsed.first?.amount, 2)
    }
}
