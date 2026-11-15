import SwiftUI

/// The people clothing is bought for. Each gets a header on the Clothing list, in this order, and can have their
/// sizes and measurements saved.
struct FamilyMembersView: View {
    @Environment(GroceryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NamedListEditor(
            title: "Family Members", placeholder: "Name (Mom, Emma, Jake…)", header: "Family",
            footer: "Clothing is listed under each person's name, in this order and in the color you pick. Drag to reorder. Tap Sizes & Measurements to save someone's sizes; they're suggested when you add clothing for them. Deleting someone keeps their clothing under \"No one yet\".",
            items: $store.people, name: \.name,
            add: { store.addPerson(named: $0) != nil }, delete: store.deletePerson
        ) { $person in
            NameColorPicker(selected: store.color(ofPerson: person.id)) {
                store.setColor($0, ofPerson: person.id)
            }
            NavigationLink {
                MeasurementsView(personID: person.id)
            } label: {
                let saved = (person.measurements ?? []).filter { !$0.value.isEmpty }
                Label(saved.isEmpty ? "Sizes & Measurements" : saved.prefix(3).map { "\($0.label) \($0.value)" }.joined(separator: " · "),
                      systemImage: "ruler")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityIdentifier("measurements-\(person.name)")
        }
    }
}

/// One person's sizes and measurements: pick a label (Shoes, Inseam…) or type your own, then fill in the value.
struct MeasurementsView: View {
    @Environment(GroceryStore.self) private var store
    let personID: UUID
    @State private var customLabel = ""
    @FocusState private var focused: UUID?

    private var person: Person? { store.person(for: personID) }
    private var measurements: [Measurement] { person?.measurements ?? [] }

    private func add(_ label: String) {
        if let added = store.addMeasurement(label, for: personID) {
            customLabel = ""
            focused = added.id
        }
    }

    var body: some View {
        List {
            if !measurements.isEmpty {
                Section {
                    ForEach(measurements) { measurement in
                        MeasurementRow(measurement: measurement, personID: personID, focus: $focused)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.removeMeasurement(measurement.id, for: personID)
                            }
                        }
                    }
                } footer: {
                    Text("Press and hold one to delete it. Sizes are free text: M, 8, 10 Kids, 32x30, Petite.")
                }
            }

            Section {
                let unused = MeasurementLabels.common.filter { label in
                    !measurements.contains { GroceryStore.same($0.label, label) }
                }
                if !unused.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(unused, id: \.self) { label in
                                Button(label) { add(label) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
                HStack {
                    TextField("Something else (Belt, Bike frame…)", text: $customLabel).titleCase($customLabel)
                        .submitLabel(.done)
                        .onSubmit { add(customLabel) }
                    Button("Add") { add(customLabel) }
                        .disabled(customLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Add a size or measurement")
            } footer: {
                Text("When you add clothing for \(person?.name ?? "them"), a matching size is suggested: Shoes for sneakers, Pants for jeans.")
            }
        }
        .navigationTitle(person.map { "\($0.name)'s Sizes" } ?? "Sizes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One size: its own copy of the text while you type (so fast typing never loses letters to the list redrawing),
/// saved as you go, and given a capital at the start of each word when you press Return or leave it.
private struct MeasurementRow: View {
    @Environment(GroceryStore.self) private var store
    let measurement: Measurement
    let personID: UUID
    var focus: FocusState<UUID?>.Binding
    @State private var text: String

    init(measurement: Measurement, personID: UUID, focus: FocusState<UUID?>.Binding) {
        self.measurement = measurement
        self.personID = personID
        self.focus = focus
        _text = State(initialValue: measurement.value)
    }

    private func finish() {
        let fixed = TitleCase.apply(text)
        if fixed != text { text = fixed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(measurement.label) {
                TextField("Size", text: $text)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .focused(focus, equals: measurement.id)
                    .onSubmit(finish)
            }
            if !measurement.value.isEmpty {
                Text("Updated \(measurement.updated.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: text) { _, typed in
            store.setMeasurement(measurement.id, to: typed, for: personID)
        }
        .onChange(of: focus.wrappedValue) { was, now in
            if was == measurement.id, now != measurement.id { finish() }
        }
        .onChange(of: measurement.value) { _, synced in
            // A change from another phone shows here unless you're in the middle of typing.
            if focus.wrappedValue != measurement.id, synced != text { text = synced }
        }
    }
}
