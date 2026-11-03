import SwiftUI

/// The top of the list in Shopping Mode: how much is in the cart, and which aisle to head to next.
struct ShoppingHeader: View {
    let progress: ShoppingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.isDone ? "Everything's in the cart" : "\(progress.inCart) of \(progress.total) in the cart")
                    .font(.headline)
                Spacer()
                Text("\(Int((progress.fraction * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress.fraction)
                .tint(progress.isDone ? .green : .brand)
            if let next = progress.nextText {
                Label(next, systemImage: "arrow.right.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.brand)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .animation(.default, value: progress)
    }
}
