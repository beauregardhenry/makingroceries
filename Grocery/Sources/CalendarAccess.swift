import EventKit
import Observation

/// Reads upcoming events from the phone's calendars, which include Google Calendar when that account is
/// added in Settings › Calendar › Accounts. Events are read on this phone and never sent anywhere.
@MainActor @Observable
final class CalendarAccess {
    enum State { case unknown, denied, ready }

    private(set) var state: State = .unknown
    @ObservationIgnored private let eventStore = EKEventStore()

    init() { refresh() }

    func refresh() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: state = .ready
        case .notDetermined: state = .unknown
        default: state = .denied
        }
    }

    func request() async {
        _ = try? await eventStore.requestFullAccessToEvents()
        refresh()
    }

    func events(days: Int, now: Date = Date()) -> [CalendarEvent] {
        guard state == .ready, let end = Calendar.current.date(byAdding: .day, value: days, to: now) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: nil)
        return eventStore.events(matching: predicate).map { event in
            CalendarEvent(id: "\(event.eventIdentifier ?? "event")-\(event.startDate.timeIntervalSince1970)",
                          title: event.title ?? "", start: event.startDate,
                          attendeeCount: event.attendees?.count ?? 0, isAllDay: event.isAllDay,
                          calendarName: event.calendar?.title)
        }
    }
}
