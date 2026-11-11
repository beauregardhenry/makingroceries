import SwiftUI

/// The people clothing is bought for. Each gets a header on the Clothing list, in this order.
struct FamilyMembersView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    private func add() {
        if store.addPerson(named: newName) != nil { newName = "" }
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Name (Mom, Emma, Jake…)", text: $newName).textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach($store.people) { $person in
                        TextField("Name", text: $person.name).textInputAutocapitalization(.words)
                    }
                    .onDelete { offsets in offsets.map { store.people[$0].id }.forEach(store.deletePerson) }
                    .onMove { store.people.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Family")
                } footer: {
                    Text("Clothing is listed under each person's name, in this order. Drag to reorder. Deleting someone keeps their clothing under \"No one yet\".")
                }
            }
            .navigationTitle("Family Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
