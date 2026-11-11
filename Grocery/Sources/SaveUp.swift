import SwiftUI

/// Purchases to save up for, in priority order, each with a cost. Drag to reorder, put money aside as you
/// go, and cover a surprise expense without losing track of everything else.
struct SaveUpView: View {
    @Environment(GroceryStore.self) private var store
    @AppStorage("savePerMonth") private var monthly = 0.0
    @State private var sheet: SaveUpSheet?

    enum SaveUpSheet: Identifiable {
        case add, unexpected, monthly
        case aside(UUID), edit(UUID)

        var id: String {
            switch self {
            case .add: "add"
            case .unexpected: "unexpected"
            case .monthly: "monthly"
            case .aside(let id): "aside-\(id)"
            case .edit(let id): "edit-\(id)"
            }
        }
    }

    private var forecasts: [UUID: GoalForecast] {
        Dictionary(uniqueKeysWithValues: GoalPlanner.forecast(store.goals, monthly: monthly).map { ($0.goalID, $0) })
    }

    private static let ranks: [Color] = [.red, .orange, .yellow, .green, .blue]

    var body: some View {
        NavigationStack {
            List {
                summarySection
                let active = store.activeGoals
                Section {
                    if active.isEmpty {
                        Text("Nothing to save for yet. Tap + to add the van repair, a new computer, or anything with a price.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(Array(active.enumerated()), id: \.element.id) { index, goal in
                        row(goal, rank: index)
                    }
                    .onMove { store.moveGoals(from: $0, to: $1) }
                    .onDelete { offsets in offsets.map { active[$0].id }.forEach(store.deleteGoal) }
                } header: {
                    Text("Priority order")
                } footer: {
                    if active.count > 1 { Text("Tap Edit, then drag to move the most important to the top. Money goes to the first one first.") }
                }
                let done = store.doneGoals
                if !done.isEmpty {
                    Section("Bought") {
                        ForEach(done) { goal in
                            HStack {
                                Label(goal.name, systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                                Spacer()
                                Text(Price.format(goal.cost)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .swipeActions {
                                Button("Put Back", systemImage: "arrow.uturn.backward") { store.reopen(goal.id) }.tint(.blue)
                                Button("Delete", systemImage: "trash", role: .destructive) { store.deleteGoal(goal.id) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Save Up")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Goal", systemImage: "plus") { sheet = .add }
                }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .add: AddGoalSheet(monthly: monthly)
                case .unexpected: UnexpectedSheet(monthly: monthly)
                case .monthly: MonthlySheet(monthly: $monthly)
                case .aside(let id): AsideSheet(goalID: id)
                case .edit(let id): EditGoalSheet(goalID: id)
                }
            }
        }
    }

    // MARK: Summary

    private var summarySection: some View {
        Section {
            let totals = store.goalTotals
            VStack(alignment: .leading, spacing: 8) {
                Text("Still to save").font(.subheadline).foregroundStyle(.secondary)
                Text(Price.format(totals.remaining)).font(.largeTitle.weight(.semibold)).monospacedDigit()
                if totals.cost > 0 {
                    ProgressView(value: min(totals.saved, totals.cost), total: totals.cost).tint(Color.positive)
                    Text("\(Price.format(totals.saved)) set aside of \(Price.format(totals.cost))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            Button { sheet = .monthly } label: {
                HStack {
                    Label("Put aside each month", systemImage: "calendar")
                    Spacer()
                    Text(monthly > 0 ? Price.format(monthly) : "Set").foregroundStyle(.secondary)
                }
            }
            if monthly > 0, let last = GoalPlanner.forecast(store.goals, monthly: monthly).last(where: { !$0.isFunded })?.date {
                Label("Everything funded by \(last.formatted(.dateTime.month(.wide).year()))", systemImage: "flag.checkered")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button { sheet = .unexpected } label: {
                Label("Something unexpected came up", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.brand)
            }
            .accessibilityIdentifier("Unexpected expense")
        }
    }

    // MARK: Rows

    private func row(_ goal: Goal, rank: Int) -> some View {
        let forecast = forecasts[goal.id]
        return Button { sheet = .edit(goal.id) } label: {
            HStack(spacing: 12) {
                Group {
                    if goal.reserve {
                        Image(systemName: "umbrella.fill")
                    } else {
                        Text("\(rank + 1)").font(.subheadline.weight(.bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background((goal.reserve ? Color.teal : Self.ranks[min(rank, Self.ranks.count - 1)]).gradient, in: Circle())
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name).font(.headline).foregroundStyle(.primary)
                    ProgressView(value: goal.progress).tint(goal.remaining <= 0 ? Color.positive : Color.brand)
                    Text(detail(goal, forecast: forecast)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Price.format(goal.cost)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("goal-\(goal.name)")
        .swipeActions(edge: .leading) {
            Button("Set Aside", systemImage: "plus.circle") { sheet = .aside(goal.id) }.tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { store.deleteGoal(goal.id) }
            Button("Bought", systemImage: "checkmark") { store.markBought(goal.id) }.tint(.green)
        }
        .contextMenu {
            if rank > 0 { Button("Make Top Priority", systemImage: "arrow.up.to.line") { store.makeTopPriority(goal.id) } }
            Button("Set Money Aside", systemImage: "plus.circle") { sheet = .aside(goal.id) }
            Button("Bought It", systemImage: "checkmark") { store.markBought(goal.id) }
        }
    }

    private func detail(_ goal: Goal, forecast: GoalForecast?) -> String {
        var text = "\(Price.format(goal.saved)) of \(Price.format(goal.cost))"
        if goal.remaining <= 0 {
            text += " · ready to buy"
        } else if let date = forecast?.date {
            text += " · by \(date.formatted(.dateTime.month(.abbreviated).year()))"
        }
        return text
    }
}

// MARK: Sheets

private struct AddGoalSheet: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let monthly: Double
    @State private var name = ""
    @State private var costText = ""
    @State private var savedText = ""
    @State private var priority = GoalPriority.normal
    @State private var isReserve = false

    private var cost: Double? { Price.parse(costText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What are you saving for?", text: $name).textInputAutocapitalization(.words)
                    LabeledContent("Cost") {
                        TextField("$0.00", text: $costText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Already saved") {
                        TextField("Optional", text: $savedText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(GoalPriority.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if store.reserveGoal == nil {
                        Toggle("This is my rainy-day fund", isOn: $isReserve)
                    }
                } footer: {
                    Text(store.reserveGoal == nil
                         ? "A rainy-day fund is money kept back for surprises. When something unexpected comes up, it can pay for it without moving your other goals."
                         : "Urgent goals go to the top. You can drag them into any order later.")
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addGoal(name: name, cost: cost ?? 0, saved: Price.parse(savedText) ?? 0,
                                      priority: priority, isReserve: isReserve)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (cost ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct UnexpectedSheet: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let monthly: Double
    @State private var name = ""
    @State private var costText = ""
    @State private var priority = GoalPriority.urgent
    @State private var useReserve = true

    private var cost: Double { Price.parse(costText) ?? 0 }
    private var reserveCovers: Bool { (store.reserveGoal?.saved ?? 0) >= cost && cost > 0 }
    private var paysFromReserve: Bool { useReserve && reserveCovers }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What came up? (van repair, vet bill…)", text: $name).textInputAutocapitalization(.words)
                    LabeledContent("Cost") {
                        TextField("$0.00", text: $costText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                if let reserve = store.reserveGoal {
                    Section {
                        Toggle("Pay from rainy-day fund", isOn: $useReserve)
                    } footer: {
                        Text(reserveCovers
                             ? "\(Price.format(reserve.saved)) in the fund covers it, and nothing else moves."
                             : "The fund has \(Price.format(reserve.saved)), which isn't enough, so this becomes a goal.")
                    }
                }
                if !paysFromReserve {
                    Section {
                        Picker("Priority", selection: $priority) {
                            ForEach(GoalPriority.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } footer: {
                        if priority == .urgent, let days = GoalPlanner.delayDays(adding: cost, monthly: monthly),
                           !store.activeGoals.isEmpty {
                            Text("Doing this first pushes your other goals back \(GoalPlanner.delayText(days: days)).")
                        } else if monthly <= 0 {
                            Text("Set how much you put aside each month, and this shows how far it pushes your other goals back.")
                        }
                    }
                }
            }
            .navigationTitle("Unexpected Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addUnexpected(name: name, cost: cost, priority: priority, useReserve: useReserve)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || cost <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AsideSheet: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID
    @State private var amountText = ""

    var body: some View {
        NavigationStack {
            if let goal = store.goals.first(where: { $0.id == goalID }) {
                Form {
                    Section {
                        LabeledContent("Saved so far", value: "\(Price.format(goal.saved)) of \(Price.format(goal.cost))")
                        LabeledContent("Amount") {
                            TextField("$0.00", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        HStack {
                            ForEach([10, 25, 50, 100], id: \.self) { value in
                                Button("+\(value)") { amountText = String(value) }.buttonStyle(.bordered)
                            }
                        }
                    }
                    Section {
                        Button("Put Aside", systemImage: "plus.circle.fill") {
                            store.setAside(Price.parse(amountText) ?? 0, for: goalID)
                            dismiss()
                        }
                        .disabled((Price.parse(amountText) ?? 0) <= 0)
                        Button("Take Out", systemImage: "minus.circle") {
                            store.setAside(-(Price.parse(amountText) ?? 0), for: goalID)
                            dismiss()
                        }
                        .disabled((Price.parse(amountText) ?? 0) <= 0)
                    }
                }
                .navigationTitle(goal.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct EditGoalSheet: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID
    @State private var name = ""
    @State private var costText = ""
    @State private var savedText = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).textInputAutocapitalization(.words)
                    LabeledContent("Cost") {
                        TextField("$0.00", text: $costText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Saved") {
                        TextField("$0.00", text: $savedText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Button("Bought It", systemImage: "checkmark.circle.fill") {
                        save()
                        store.markBought(goalID)
                        dismiss()
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        store.deleteGoal(goalID)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (Price.parse(costText) ?? 0) <= 0)
                }
            }
            .onAppear {
                guard !loaded, let goal = store.goals.first(where: { $0.id == goalID }) else { return }
                loaded = true
                name = goal.name
                costText = Price.editText(goal.cost)
                savedText = Price.editText(goal.saved)
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let i = store.goals.firstIndex(where: { $0.id == goalID }), let cost = Price.parse(costText), cost > 0 else { return }
        store.goals[i].name = name.trimmingCharacters(in: .whitespaces)
        store.goals[i].cost = cost
        store.goals[i].saved = min(max(Price.parse(savedText) ?? 0, 0), cost)
    }
}

private struct MonthlySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var monthly: Double
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Each month") {
                        TextField("$0.00", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("How much you can put toward these goals every month. The app uses it to estimate when each one will be funded, in priority order.")
                }
            }
            .navigationTitle("Monthly Savings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { monthly = max(Price.parse(text) ?? 0, 0); dismiss() }
                }
            }
            .onAppear { text = Price.editText(monthly > 0 ? monthly : nil) }
        }
        .presentationDetents([.medium])
    }
}
