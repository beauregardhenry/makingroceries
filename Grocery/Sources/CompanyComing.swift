import SwiftUI

/// When company is coming: find the dinner or party on your calendar, then pick something that can be made
/// ahead and frozen, planned for a few days before.
struct CompanyComingView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let shopID: UUID?
    @State private var calendar = CalendarAccess()
    @State private var events: [CalendarEvent] = []
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var guests = 8
    @State private var message: String?

    private var makeBy: Date { MakeAhead.makeByDate(for: date) }

    private func loadEvents() {
        events = CompanyEvents.upcoming(calendar.events(days: 21))
    }

    var body: some View {
        NavigationStack {
            List {
                calendarSection
                Section {
                    DatePicker("Company arrives", selection: $date, in: Date()..., displayedComponents: .date)
                    Stepper("Guests: \(guests)", value: $guests, in: 1...40)
                } footer: {
                    Text("Cook by \(makeBy.formatted(.dateTime.weekday(.wide).month().day())), so there's time to freeze and thaw. Recipes are scaled to \(guests) \(guests == 1 ? "guest" : "guests").")
                }
                if let message {
                    Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                Section {
                    ForEach(MakeAhead.suggestions(meals: store.meals)) { idea in
                        ideaRow(idea)
                    }
                } header: {
                    Text("Make ahead, freezes well")
                } footer: {
                    Text("Your own meals marked \"Freezes well\" come first. Mark more in Saved Meals.")
                }
            }
            .navigationTitle("Company Coming")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { loadEvents() }
        }
    }

    @ViewBuilder
    private var calendarSection: some View {
        Section {
            switch calendar.state {
            case .unknown:
                Button("Connect Calendar", systemImage: "calendar.badge.plus") {
                    Task { await calendar.request(); loadEvents() }
                }
            case .denied:
                Text("Calendar access is off. Turn it on in Settings to see your dinners and parties here.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Open Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .ready:
                if events.isEmpty {
                    Text("No dinners or parties on your calendar in the next three weeks.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(events) { event in
                    Button {
                        date = event.start
                        message = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).foregroundStyle(.primary)
                                Text(event.start.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if Calendar.current.isDate(event.start, inSameDayAs: date) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("On your calendar")
        } footer: {
            Text("Uses the calendars on this phone, including Google Calendar if you've added that account in Settings › Calendar › Accounts. Tap an event to plan for it.")
        }
    }

    private func ideaRow(_ idea: MakeAheadIdea) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: idea.category.symbol)
                    .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(idea.category.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(idea.title)
                    Text(idea.note).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button("Plan for \(makeBy.formatted(.dateTime.month(.abbreviated).day()))", systemImage: "calendar.badge.plus") {
                    store.planMakeAhead(idea, for: date)
                    message = "\(idea.title) planned for \(makeBy.formatted(.dateTime.weekday(.wide).month().day()))."
                }
                Button("Add to List", systemImage: "cart.badge.plus") {
                    store.addMakeAheadToList(idea, shopID: shopID, scale: MakeAhead.scale(forGuests: guests))
                    message = "\(idea.title) ingredients added to your list."
                }
            }
            .buttonStyle(.bordered)
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }
}
