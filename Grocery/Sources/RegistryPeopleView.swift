import SwiftUI

/// The people gifts are kept for. Each gets a header on the Registry list, in this order.
struct RegistryPeopleView: View {
    @Environment(GroceryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NamedListEditor(
            title: "Registry People", placeholder: "Name (Grandma, Emma, Mr. Lee…)", header: "People",
            footer: "Gifts are listed under each person's name, in this order. These names sync with your family on iCloud. Deleting someone keeps their gifts under \"Not assigned yet\".",
            items: $store.registryPeople, name: \.name,
            add: { store.addRegistryPerson(named: $0) != nil }, delete: store.deleteRegistryPerson
        ) { $person in
            Toggle("Birthday", isOn: Binding(
                get: { person.birthday != nil },
                set: { person.birthday = $0 ? (person.birthday ?? Date()) : nil }
            ))
            .font(.subheadline)
            if person.birthday != nil {
                DatePicker("Date", selection: Binding(get: { person.birthday ?? Date() }, set: { person.birthday = $0 }),
                           displayedComponents: .date)
                    .font(.subheadline)
            }
        }
    }
}
