import XCTest

/// Dragging chips on the Stores screen: what's saved must put every chip back exactly where it was dropped.
final class StoreOrderTests: XCTestCase {
    private let shops = ["A", "B", "C", "D"].map { Shop(name: $0) }

    /// Does what the Stores screen does on a drop, then rebuilds the chips from what was saved.
    private func drop(_ entries: [ChipEntry], from: Int, to: Int, shops: [Shop]) -> (entries: [ChipEntry], shops: [Shop]) {
        var arranged = entries
        arranged.move(fromOffsets: IndexSet(integer: from), toOffset: to)
        let newShops = ChipOrder.shops(shops, arrangedBy: arranged)
        let positions = Dictionary(uniqueKeysWithValues: SeparateList.allCases.map { ($0, ChipOrder.position(of: arranged, list: $0)) })
        let rebuilt = ChipOrder.entries(shops: newShops, positions: positions)
        XCTAssertEqual(rebuilt, arranged, "the chips stay where they were dropped")
        return (rebuilt, newShops)
    }

    func testStoresStayWhereTheyAreDroppedOverManyMoves() {
        var entries = ChipOrder.entries(shops: shops)
        var current = shops
        for (from, to) in [(3, 0), (1, 5), (0, 7), (6, 1), (2, 4), (5, 0), (4, 2)] {
            (entries, current) = drop(entries, from: from, to: to, shops: current)
        }
        XCTAssertEqual(current.count, 4)
    }

    func testMovingAStoreSeveralPlacesMovesItAllTheWay() {
        let first = drop(ChipOrder.entries(shops: shops), from: 3, to: 0, shops: shops)
        XCTAssertEqual(first.shops.map(\.name), ["D", "A", "B", "C"])
        let second = drop(first.entries, from: 0, to: 4, shops: first.shops)
        XCTAssertEqual(second.shops.map(\.name), ["A", "B", "C", "D"])
    }
}
