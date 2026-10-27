import SwiftUI

/// Suggests which items to buy at which of today's stores to spend less.
struct TripPlanView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var moves: [TripMove] = []
    @State private var chosen: Set<UUID> = []
    @State private var loaded = false

    private var totalSaving: Double {
        moves.filter { chosen.contains($0.id) }.reduce(0) { $0 + $1.savings }
    }

    var body: some View {
        NavigationStack {
            List {
                if moves.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("Nothing to move", systemImage: "arrow.left.arrow.right")
                        } description: {
                            Text("When an item you've priced at two stores costs less at one you're already going to, it shows up here. Prices come from receipts and the ones you enter.")
                        }
                    }
                } else {
                    Section {
                        HStack {
                            Text("You could save").foregroundStyle(.secondary)
                            Spacer()
                            Text(Price.format(totalSaving)).font(.title3.bold()).foregroundStyle(.green).monospacedDigit()
                        }
                    } footer: {
                        Text("Only stores you're already visiting are used, so none of this adds a stop.")
                    }

                    Section("Buy these somewhere else") {
                        ForEach(moves) { move in
                            Toggle(isOn: Binding(
                                get: { chosen.contains(move.id) },
                                set: { if $0 { chosen.insert(move.id) } else { chosen.remove(move.id) } }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(move.item.name)
                                        if move.item.quantity > 1 { Text("×\(move.item.quantity)").foregroundStyle(.secondary) }
                                        Spacer()
                                        Text("Save \(Price.format(move.savings))").foregroundStyle(.green).monospacedDigit()
                                    }
                                    Text(detail(move)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan the Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move \(chosen.count)") {
                        store.applyTripMoves(moves.filter { chosen.contains($0.id) })
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                moves = store.tripPlan()
                chosen = Set(moves.map(\.id))
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func detail(_ move: TripMove) -> String {
        let from = store.shopName(for: move.item.shopID) ?? "anywhere"
        let to = store.shopName(for: move.to) ?? "another store"
        let before = move.fromPrice.map(Price.format) ?? "?"
        return "\(from) \(before) → \(to) \(Price.format(move.toPrice))"
    }
}
