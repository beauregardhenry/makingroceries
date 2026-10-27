import SwiftUI

struct WatchListView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.snapshot.groups.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "cart").font(.title2)
                        Text("Open Makin' Groceries on your iPhone to load your list.")
                            .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                } else {
                    List(model.snapshot.groups) { group in
                        NavigationLink(value: group.id) {
                            HStack {
                                Text(group.name)
                                Spacer()
                                Text(group.remaining == 0 ? "Done" : "\(group.remaining)")
                                    .foregroundStyle(group.remaining == 0 ? .green : .orange)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Groceries")
            .navigationDestination(for: String.self) { id in
                if let group = model.snapshot.groups.first(where: { $0.id == id }) {
                    GroupView(group: group)
                }
            }
        }
    }
}

private struct GroupView: View {
    @Environment(WatchModel.self) private var model
    let group: WatchSnapshot.Group

    /// Re-read from the model so a tap shows straight away.
    private var current: WatchSnapshot.Group {
        model.snapshot.groups.first { $0.id == group.id } ?? group
    }

    var body: some View {
        List(current.items) { entry in
            Button {
                model.toggle(entry)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: entry.isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(entry.isChecked ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name).strikethrough(entry.isChecked)
                        if let note = entry.note { Text(note).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                    if entry.quantity > 1 { Text("×\(entry.quantity)").foregroundStyle(.secondary).font(.footnote) }
                }
            }
            .sensoryFeedback(.success, trigger: entry.isChecked)
        }
        .navigationTitle(current.name)
    }
}
