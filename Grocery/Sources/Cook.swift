import SwiftUI

/// What you could cook from what's at home: your saved meals that use it, and, on phones with Apple
/// Intelligence, a few new ideas from the on-device model. Things going off soon come first.
struct CookView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let shopID: UUID?
    @State private var ideas: [CookIdea] = []
    @State private var thinking = false
    @State private var asked = false
    @State private var message: String?

    private var soon: [StockEntry] { store.usingSoon() }

    private func askForIdeas() async {
        thinking = true
        ideas = await CookAI.ideas(have: store.stockByExpiry().map(\.name), useFirst: soon.map(\.name))
        thinking = false
        asked = true
    }

    private func added(_ count: Int) {
        message = count == 0 ? "You have everything already." : "Added \(count) item\(count == 1 ? "" : "s") to your list."
    }

    var body: some View {
        NavigationStack {
            List {
                if store.stock.isEmpty {
                    Section {
                        ContentUnavailableView("Nothing at home yet", systemImage: "refrigerator",
                                               description: Text("Check off groceries and they're tracked in At Home. Then this suggests what to cook with them."))
                    }
                } else {
                    if !soon.isEmpty {
                        Section("Use these first") {
                            Text(soon.map(\.name).formatted(.list(type: .and)))
                                .foregroundStyle(.orange)
                        }
                    }

                    Section {
                        let matches = store.mealsFromHome()
                        if matches.isEmpty {
                            Text("None of your saved meals use what's at home.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(matches) { match in
                            MealMatchRow(match: match) { added(store.addMissing(match, shopID: shopID)) }
                        }
                    } header: {
                        Text("From your meals")
                    }

                    if CookAI.isAvailable {
                        Section {
                            if thinking {
                                HStack { ProgressView(); Text("Thinking of dishes…").foregroundStyle(.secondary) }
                            } else if asked && ideas.isEmpty {
                                Text("No ideas this time. Try again in a moment.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            ForEach(ideas) { idea in
                                IdeaRow(idea: idea,
                                        onAdd: { added(store.addMissing(idea.extras, shopID: shopID)) },
                                        onSave: {
                                            store.saveIdea(idea, planOn: Date())
                                            message = "Saved \(idea.title) and planned it for today."
                                        })
                            }
                            Button(asked ? "Suggest Different Dishes" : "Suggest Dishes", systemImage: "sparkles") {
                                Task { await askForIdeas() }
                            }
                            .disabled(thinking)
                        } header: {
                            Text("New ideas")
                        } footer: {
                            Text("Made up on your iPhone by Apple Intelligence from what's at home. Nothing is sent anywhere.")
                        }
                    }
                }
            }
            .navigationTitle("What Can I Cook?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

private struct MealMatchRow: View {
    let match: MealMatch
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(match.meal.name.isEmpty ? "Untitled meal" : match.meal.name).font(.headline)
                Spacer()
                if match.missing.isEmpty {
                    Label("Ready", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold)).foregroundStyle(.green)
                } else {
                    Button("Add \(match.missing.count)", action: onAdd)
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityLabel("Add \(match.missing.count) missing to the list")
                }
            }
            Text("You have \(match.have.formatted(.list(type: .and)))")
                .font(.caption).foregroundStyle(.secondary)
            if !match.usesSoon.isEmpty {
                Text("Uses up \(match.usesSoon.formatted(.list(type: .and)))")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !match.missing.isEmpty {
                Text("Need \(match.missing.map(\.name).formatted(.list(type: .and)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct IdeaRow: View {
    let idea: CookIdea
    let onAdd: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(idea.title).font(.headline)
            Text(idea.summary).font(.subheadline)
            if !idea.uses.isEmpty {
                Text("Uses \(idea.uses.formatted(.list(type: .and)))").font(.caption).foregroundStyle(.secondary)
            }
            if !idea.extras.isEmpty {
                Text("Buy \(idea.extras.formatted(.list(type: .and)))").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if !idea.extras.isEmpty {
                    Button("Add to List", systemImage: "cart.badge.plus", action: onAdd)
                }
                Button("Save & Plan Today", systemImage: "calendar.badge.plus", action: onSave)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
}
