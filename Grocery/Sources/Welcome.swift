import SwiftUI

/// The first launch: pick the stores you shop at, so the aisle-order idea makes sense from the start.
struct WelcomeView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [String] = []
    @State private var custom = ""
    @State private var keepSample = true

    private var choices: [String] {
        Shop.presetNames + picked.filter { !Shop.presetNames.contains($0) }
    }

    private func toggle(_ name: String) {
        if let i = picked.firstIndex(of: name) { picked.remove(at: i) } else { picked.append(name) }
    }

    private func addCustom() {
        let name = custom.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !picked.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { picked.append(name) }
        custom = ""
    }

    private func finish() {
        addCustom()
        store.finishSetup(storeNames: picked, keepSample: keepSample)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image("IconPreview-Orange")
                            .resizable()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityHidden(true)
                        Text("Welcome to Makin' Groceries")
                            .font(.largeTitle.weight(.bold))
                        Text("A list for each store you shop at, in the order you walk its aisles.")
                            .font(.title3).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Where do you shop?").font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(choices, id: \.self) { name in
                                let on = picked.contains(name)
                                Button { toggle(name) } label: {
                                    Label(name, systemImage: on ? "checkmark" : "plus")
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .foregroundStyle(on ? Color.white : Color.primary)
                                        .background(on ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.fill.tertiary), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        HStack {
                            TextField("Another store", text: $custom)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.done)
                                .onSubmit(addCustom)
                            Button("Add", action: addCustom)
                                .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        Text(picked.isEmpty
                             ? "You can skip this. Everything goes under Anywhere until you add stores."
                             : "Each store gets its own list. You can change these any time in Settings › Stores.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        tip("arrow.up.arrow.down", "Drag a store's aisles into the order you walk them, and its list follows.")
                        tip("figure.walk", "Or just shop: it learns your route from the order you check things off.")
                        tip("square.grid.2x2", "Meals, Kitchen and Money fill in as you shop and add prices.")
                    }

                    Toggle("Start with a few sample items", isOn: $keepSample)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: finish) {
                    Text("Get Started").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        .interactiveDismissDisabled()
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(Color.brand)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text).font(.subheadline)
        }
    }
}

/// Lays chips out in rows, wrapping to the next line when one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
