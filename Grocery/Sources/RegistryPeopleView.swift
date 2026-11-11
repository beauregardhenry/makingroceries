import SwiftUI

/// The people gifts are kept for. Each gets a header on the Registry list, in this order.
struct RegistryPeopleView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    private func add() {
        if store.addRegistryPerson(named: newName) != nil { newName = "" }
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Name (Grandma, Emma, Mr. Lee…)", text: $newName).textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach($store.registryPeople) { $person in
                        VStack(alignment: .leading) {
                            TextField("Name", text: $person.name).textInputAutocapitalization(.words)
                            HStack {
                                Toggle("Birthday", isOn: Binding(
                                    get: { person.birthday != nil },
                                    set: { person.birthday = $0 ? (person.birthday ?? Date()) : nil }
                                ))
                                .font(.subheadline)
                            }
                            if person.birthday != nil {
                                DatePicker("Date", selection: Binding(get: { person.birthday ?? Date() }, set: { person.birthday = $0 }),
                                           displayedComponents: .date)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .onDelete { offsets in offsets.map { store.registryPeople[$0].id }.forEach(store.deleteRegistryPerson) }
                    .onMove { store.registryPeople.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("People")
                } footer: {
                    Text("Gifts are listed under each person's name, in this order. These names sync with your family on iCloud. Deleting someone keeps their gifts under \"Not assigned yet\".")
                }
            }
            .navigationTitle("Registry People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
