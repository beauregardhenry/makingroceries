import SwiftUI

/// A sheet for a list of named things: type a name and tap Add, then rename, reorder or delete. Family Members,
/// Registry People and Custom Aisles are all this screen. `extra` adds controls under each name.
struct NamedListEditor<Item: Identifiable, Extra: View>: View {
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    let title: String
    let placeholder: String
    let header: String
    let footer: String
    @Binding var items: [Item]
    let name: WritableKeyPath<Item, String>
    /// Adds a new one; true when it was added (not blank or a duplicate).
    let add: (String) -> Bool
    let delete: (Item.ID) -> Void
    @ViewBuilder let extra: (Binding<Item>) -> Extra

    private func addNew() {
        if add(newName) { newName = "" }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(placeholder, text: $newName).textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(addNew)
                        Button("Add", action: addNew)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach($items) { $item in
                        VStack(alignment: .leading) {
                            TextField("Name", text: $item[dynamicMember: name]).textInputAutocapitalization(.words)
                            extra($item)
                        }
                    }
                    .onDelete { offsets in offsets.map { items[$0].id }.forEach(delete) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text(header)
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

extension NamedListEditor where Extra == EmptyView {
    init(title: String, placeholder: String, header: String, footer: String, items: Binding<[Item]>,
         name: WritableKeyPath<Item, String>, add: @escaping (String) -> Bool, delete: @escaping (Item.ID) -> Void) {
        self.init(title: title, placeholder: placeholder, header: header, footer: footer, items: items, name: name,
                  add: add, delete: delete, extra: { _ in EmptyView() })
    }
}
