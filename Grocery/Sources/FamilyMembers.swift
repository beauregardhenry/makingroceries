import SwiftUI

/// The people clothing is bought for. Each gets a header on the Clothing list, in this order.
struct FamilyMembersView: View {
    @Environment(GroceryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NamedListEditor(
            title: "Family Members", placeholder: "Name (Mom, Emma, Jake…)", header: "Family",
            footer: "Clothing is listed under each person's name, in this order. Drag to reorder. Deleting someone keeps their clothing under \"No one yet\".",
            items: $store.people, name: \.name,
            add: { store.addPerson(named: $0) != nil }, delete: store.deletePerson)
    }
}
