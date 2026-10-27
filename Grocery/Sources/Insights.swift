import Charts
import SwiftUI

/// Where the money goes: this month against a budget, week by week, by store and by aisle.
struct InsightsView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var days = 30
    @State private var budget = GroceryStore.monthlyBudget
    @State private var editingBudget = false
    @State private var budgetText = ""
    @State private var addingTrip = false
    @State private var tripText = ""
    @State private var tripShop: UUID?

    private var range: (Date, Date) {
        let end = Date().addingTimeInterval(60)
        return (Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end, end)
    }

    var body: some View {
        NavigationStack {
            List {
                monthSection
                if store.spending.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No spending yet", systemImage: "chart.bar")
                        } description: {
                            Text("Scan a receipt, or add a trip total, and your spending shows up here.")
                        }
                    }
                } else {
                    weeklySection
                    Section {
                        Picker("Period", selection: $days) {
                            Text("30 days").tag(30)
                            Text("90 days").tag(90)
                            Text("A year").tag(365)
                        }
                        .pickerStyle(.segmented)
                    }
                    shopSection
                    aisleSection
                    tripsSection
                }
            }
            .navigationTitle("Spending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Add Trip") { tripText = ""; addingTrip = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Monthly Budget", isPresented: $editingBudget) {
                TextField("0.00", text: $budgetText).keyboardType(.decimalPad)
                Button("Save") {
                    budget = Price.parse(budgetText).flatMap { $0 > 0 ? $0 : nil }
                    GroceryStore.monthlyBudget = budget
                }
                Button("Remove Budget", role: .destructive) { budget = nil; GroceryStore.monthlyBudget = nil }
                Button("Cancel", role: .cancel) {}
            } message: { Text("What you'd like to spend on groceries each month.") }
            .alert("Add a Trip", isPresented: $addingTrip) {
                TextField("Total spent", text: $tripText).keyboardType(.decimalPad)
                Button("Save") {
                    if let amount = Price.parse(tripText) { store.recordSpend(amount: amount, shopID: tripShop) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("For a trip you don't have a receipt for.") }
        }
    }

    private var monthSection: some View {
        let spent = store.monthToDate()
        return Section {
            HStack(alignment: .firstTextBaseline) {
                Text(Price.format(spent)).font(.largeTitle.bold()).monospacedDigit()
                Text("this month").foregroundStyle(.secondary)
                Spacer()
                Button(budget == nil ? "Set Budget" : "Edit") {
                    budgetText = budget.map { Price.editText($0) } ?? ""
                    editingBudget = true
                }
                .buttonStyle(.borderless)
            }
            if let budget {
                ProgressView(value: min(spent, budget), total: budget)
                    .tint(spent > budget ? .red : (spent > budget * 0.8 ? .orange : .green))
                Text(spent > budget
                     ? "\(Price.format(spent - budget)) over your \(Price.format(budget)) budget"
                     : "\(Price.format(budget - spent)) left of \(Price.format(budget))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var weeklySection: some View {
        Section("Week by week") {
            Chart(store.weeklyTotals(weeks: 8)) { bucket in
                BarMark(x: .value("Week", bucket.label), y: .value("Spent", bucket.amount))
                    .foregroundStyle(Color.orange.gradient)
            }
            .chartYAxis { AxisMarks(format: .currency(code: Locale.current.currency?.identifier ?? "USD")) }
            .frame(height: 180)
            .accessibilityLabel("Weekly spending, last 8 weeks")
        }
    }

    @ViewBuilder private var shopSection: some View {
        let buckets = store.spendingByShop(from: range.0, to: range.1)
        if !buckets.isEmpty {
            Section("By store") { bars(buckets) }
        }
    }

    @ViewBuilder private var aisleSection: some View {
        let buckets = store.spendingByAisle(from: range.0, to: range.1)
        if !buckets.isEmpty {
            Section("By aisle") { bars(buckets) }
        }
    }

    private func bars(_ buckets: [SpendBucket]) -> some View {
        Chart(buckets) { bucket in
            BarMark(x: .value("Spent", bucket.amount), y: .value("Name", bucket.label))
                .foregroundStyle(Color.orange.gradient)
                .annotation(position: .trailing) { Text(Price.format(bucket.amount)).font(.caption).foregroundStyle(.secondary) }
        }
        .chartXAxis(.hidden)
        .frame(height: CGFloat(max(1, buckets.count)) * 38 + 8)
    }

    private var tripsSection: some View {
        Section("Recent trips") {
            ForEach(store.spending.sorted { $0.date > $1.date }.prefix(12)) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.shopName(for: record.shopID) ?? "Trip")
                        Text(record.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Price.format(record.amount)).monospacedDigit()
                }
            }
            .onDelete { offsets in
                let recent = Array(store.spending.sorted { $0.date > $1.date }.prefix(12))
                let ids = Set(offsets.map { recent[$0].id })
                store.spending.removeAll { ids.contains($0.id) }
            }
        }
    }
}
