import AppIntents
import SwiftUI
import WidgetKit

struct SelectShopIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Store"
    static let description = IntentDescription("Show one store's list, or everything.")

    @Parameter(title: "Store")
    var shop: ShopEntity?

    @Parameter(title: "Switch to the store I'm at", default: false)
    var followLocation: Bool
}

struct ListEntry: TimelineEntry {
    let date: Date
    let title: String
    let items: [GroceryItem]
}

struct ListProvider: AppIntentTimelineProvider {
    private func entry(for configuration: SelectShopIntent) -> ListEntry {
        let store = GroceryStore()
        let nearbyID = configuration.followLocation ? NearbyStore.currentShopID(among: store.shops) : nil
        let shop = store.shop(for: nearbyID ?? configuration.shop?.id)
        return ListEntry(date: Date(), title: shop?.name ?? "Groceries",
                         items: store.widgetItems(shopID: shop?.id))
    }

    func placeholder(in context: Context) -> ListEntry {
        ListEntry(date: Date(), title: "Groceries", items: [
            GroceryItem(name: "Bananas", quantity: 6, aisle: .produce),
            GroceryItem(name: "Milk", aisle: .dairy),
            GroceryItem(name: "Sourdough", aisle: .bakery),
        ])
    }

    func snapshot(for configuration: SelectShopIntent, in context: Context) async -> ListEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectShopIntent, in context: Context) async -> Timeline<ListEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(Date().addingTimeInterval(60 * 60)))
    }
}

struct ListWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ListEntry

    private var limit: Int {
        switch family {
        case .systemSmall: 4
        case .systemMedium: 4
        case .systemLarge: 11
        case .accessoryRectangular: 2
        default: 4
        }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.items.isEmpty ? "List is empty" : "\(entry.items.count) to buy")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.title) · \(entry.items.count)").font(.headline)
                if entry.items.isEmpty {
                    Text("All done")
                } else {
                    ForEach(entry.items.prefix(limit)) { Text($0.name).lineLimit(1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text("\(entry.items.count)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                if entry.items.isEmpty {
                    Spacer()
                    Label("All done", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                } else {
                    ForEach(entry.items.prefix(limit)) { item in
                        Button(intent: ToggleItemIntent(itemID: item.id.uuidString)) {
                            HStack(spacing: 6) {
                                Image(systemName: "circle").foregroundStyle(.secondary)
                                Text(item.name).lineLimit(1)
                                Spacer(minLength: 0)
                                if item.quantity > 1 {
                                    Text("×\(item.quantity)").foregroundStyle(.secondary).font(.caption)
                                }
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                    }
                    if entry.items.count > limit {
                        Text("+\(entry.items.count - limit) more").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct ListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ListWidget", intent: SelectShopIntent.self, provider: ListProvider()) { entry in
            ListWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Grocery List")
        .description("Your list, one tap to check things off. Choose a store to see its aisle order.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct GroceryWidgets: WidgetBundle {
    var body: some Widget {
        ListWidget()
        ShoppingLiveActivity()
    }
}
