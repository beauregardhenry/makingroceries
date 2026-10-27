import ActivityKit
import SwiftUI
import WidgetKit

struct ShoppingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingAttributes.self) { context in
            LockScreenView(storeName: context.attributes.storeName, state: context.state)
                .padding()
                .activityBackgroundTint(Color(.secondarySystemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.storeName, systemImage: "cart.fill").font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.remaining) left").font(.headline).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(context.state.total - context.state.remaining), total: Double(max(1, context.state.total)))
                            .tint(.orange)
                        if let next = context.state.nextItem { Text("Next: \(next)").font(.subheadline) }
                    }
                }
            } compactLeading: {
                Image(systemName: "cart.fill").foregroundStyle(.orange)
            } compactTrailing: {
                Text("\(context.state.remaining)").monospacedDigit()
            } minimal: {
                Image(systemName: "cart.fill").foregroundStyle(.orange)
            }
        }
    }
}

private struct LockScreenView: View {
    let storeName: String
    let state: ShoppingAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(storeName, systemImage: "cart.fill").font(.headline)
                Spacer()
                Text(state.remaining == 0 ? "All done" : "\(state.remaining) of \(state.total) left")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: Double(state.total - state.remaining), total: Double(max(1, state.total))).tint(.orange)
            if let next = state.nextItem, state.remaining > 0 {
                Text("Next: \(next)").font(.subheadline)
            }
        }
    }
}
