import SwiftUI

/// What Clear Done removed, kept briefly so it can be undone.
struct ClearedBatch: Identifiable {
    let id = UUID()
    let items: [ClearedItem]
}

struct UndoBanner: View {
    let count: Int
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Cleared \(count) item\(count == 1 ? "" : "s")")
            Spacer()
            Button("Undo", action: onUndo).fontWeight(.semibold)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }
}
