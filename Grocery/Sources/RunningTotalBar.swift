import SwiftUI

/// The total at the bottom of the list: everything priced on screen, what's in the cart so far, and, when one
/// store or Travel is showing, the total across all the everyday lists.
struct RunningTotalBar: View {
    let total: RunningTotal

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Total").font(.caption).foregroundStyle(.secondary)
                Text(Price.format(total.all)).font(.title3.weight(.semibold)).monospacedDigit()
            }
            if total.inCart > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    Text("In cart").font(.caption).foregroundStyle(.secondary)
                    Text(Price.format(total.inCart)).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Color.positive)
                }
            }
            Spacer(minLength: 0)
            if let everywhere = total.everywhere {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("All lists").font(.caption).foregroundStyle(.secondary)
                    Text(Price.format(everywhere)).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            } else if total.pricedCount < total.count {
                Text("\(total.pricedCount) of \(total.count) priced").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("runningTotal")
    }
}
