import Charts
import SwiftUI

/// An item's prices over time, one line per store, with what you usually pay marked.
struct PriceHistoryChart: View {
    let trend: PriceTrend
    @Environment(GroceryStore.self) private var store

    private func storeName(_ point: PricePoint) -> String {
        store.shopName(for: point.shopID) ?? "No store"
    }

    var body: some View {
        Chart {
            ForEach(Array(trend.points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.date), y: .value("Price", point.price))
                    .foregroundStyle(by: .value("Store", storeName(point)))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date), y: .value("Price", point.price))
                    .foregroundStyle(by: .value("Store", storeName(point)))
            }
            RuleMark(y: .value("Usual", trend.usual))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary)
                .annotation(position: .top, alignment: .leading) {
                    Text("Usual \(Price.format(trend.usual))").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartYAxis { AxisMarks { value in
            AxisGridLine()
            AxisValueLabel { if let price = value.as(Double.self) { Text(Price.format(price)) } }
        } }
        .frame(height: 180)
        .accessibilityLabel("Price history for \(trend.name)")
        .accessibilityValue("Usually \(Price.format(trend.usual)), latest \(Price.format(trend.latest.price))")
    }
}

/// A short line under the chart: whether the latest price is a deal, and where it's cheapest.
struct PriceTrendSummary: View {
    let trend: PriceTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let off = trend.discount {
                Label("\(Int((off * 100).rounded()))% under what you usually pay", systemImage: "tag.fill")
                    .foregroundStyle(.green)
            }
            if let best = trend.cheapestStore {
                Label("Cheapest at \(best.name), about \(Price.format(best.average))", systemImage: "storefront")
                    .foregroundStyle(.secondary)
            }
            ForEach(trend.stores.filter { $0.shopID != nil }) { summary in
                Text("\(summary.name): average \(Price.format(summary.average)) over \(summary.count) price\(summary.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}

/// Prices across everything you buy: what's on sale now, and where each staple is cheapest.
struct PriceWatchView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let deals = store.priceDeals()
                let cheapest = store.cheapestStores()
                if deals.isEmpty && cheapest.isEmpty {
                    Section {
                        ContentUnavailableView("Not enough prices yet", systemImage: "chart.line.uptrend.xyaxis",
                                               description: Text("Prices you set on items or read from receipts build up here. Once an item has a few, you'll see its history and where it's cheapest."))
                    }
                }
                if !deals.isEmpty {
                    Section {
                        ForEach(deals, id: \.name) { trend in
                            NavigationLink(value: trend.name) {
                                HStack {
                                    Text(trend.name)
                                    Spacer()
                                    Text("\(Price.format(trend.latest.price)), usually \(Price.format(trend.usual))")
                                        .font(.caption).foregroundStyle(.green)
                                }
                            }
                        }
                    } header: {
                        Text("Good prices right now")
                    } footer: {
                        Text("The latest price is at least \(Int(PriceTrend.dealThreshold * 100))% under the middle of what you've paid.")
                    }
                }
                if !cheapest.isEmpty {
                    Section("Where it's cheapest") {
                        ForEach(cheapest, id: \.name) { trend in
                            NavigationLink(value: trend.name) {
                                HStack {
                                    Text(trend.name)
                                    Spacer()
                                    if let best = trend.cheapestStore {
                                        Text("\(best.name), saves \(Price.format(trend.spread))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Price History")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { name in
                if let trend = store.priceTrend(for: name) {
                    List {
                        Section { PriceHistoryChart(trend: trend) }
                        Section { PriceTrendSummary(trend: trend) }
                    }
                    .navigationTitle(trend.name)
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
