import Foundation
import Combine
import EventKit

@MainActor
public final class CalendarViewModel: ObservableObject {
    @Published public var events: [UserCalendarEvent] = []
    @Published public var isLoading: Bool = false
    @Published public var accessDenied: Bool = false
    @Published public var errorMessage: String?
    @Published public var availableCalendars: [EKCalendar] = []
    @Published public var selectedCalendar: EKCalendar?
    @Published public var selectedAlertOption: AlertOption = .none
    @Published public var repeatFrequency: RepeatFrequency = .none
    @Published public var travelTime: TravelTimeOption = .none
    @Published public var isAllDay: Bool = false
    @Published public var newEndDate: Date = Date().addingTimeInterval(3600)
    private let dataManager: CalendarDataManager

    public init(dataManager: CalendarDataManager? = nil) {
        self.dataManager = dataManager ?? CalendarDataManager.shared
        Task { await loadCalendars() }
    }

    public func loadCalendarEvents() async {
        guard !isLoading else { return }
        isLoading = true
        accessDenied = false
        errorMessage = nil

        do {
            let granted = try await dataManager.requestAccessIfNeeded()
            guard granted else {
                accessDenied = true
                isLoading = false
                return
            }

            let fetched = try await dataManager.fetchEventsForToday()
            events = fetched
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    public func createEvent(title: String,
                            startDate: Date,
                            endDate: Date,
                            isAllDay: Bool,
                            durationMinutes: Double,
                            calendar: EKCalendar?,
                            alert: AlertOption,
                            repeatRule: RepeatFrequency,
                            travelTime: TravelTimeOption,
                            location: String?,
                            urlString: String?,
                            notes: String?) async {
        let duration = durationMinutes * 60
        let url = urlString.flatMap { URL(string: $0) }
        do {
            let created = try await dataManager.createEvent(
                title: title.isEmpty ? "New Event" : title,
                startDate: startDate,
                endDate: endDate > startDate ? endDate : startDate.addingTimeInterval(duration),
                isAllDay: isAllDay,
                calendar: calendar,
                alert: alert,
                repeatRule: repeatRule,
                travelTime: travelTime,
                location: location?.isEmpty == true ? nil : location,
                url: url,
                notes: notes?.isEmpty == true ? nil : notes
            )
            events.append(created)
            events.sort { $0.startDate < $1.startDate }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func openFirstEventInCalendar() {
        dataManager.openCalendar(at: events.first?.startDate)
    }

    public func openCalendarApp() {
        dataManager.openCalendar(at: Date())
    }

    public func editEvent(eventID: String, newTitle: String, newDate: Date, newDuration: TimeInterval) async throws {
        let updated = try await dataManager.editEvent(eventID: eventID, newTitle: newTitle, newDate: newDate, newDuration: newDuration)
        if let idx = events.firstIndex(where: { $0.eventIdentifier == eventID }) {
            events[idx] = updated
        } else {
            events.append(updated)
        }
        events.sort { $0.startDate < $1.startDate }
    }

    public func deleteEvents(eventIDs: [String]) async throws {
        try await dataManager.deleteEvents(eventIDs: eventIDs)
        events.removeAll { event in
            guard let id = event.eventIdentifier else { return false }
            return eventIDs.contains(id)
        }
    }

    public func matchingEvent(forTitle title: String) -> UserCalendarEvent? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let lowered = title.lowercased()
        return events.first { $0.title.lowercased().contains(lowered) }
    }

    #if canImport(EventKitUI)
    public func editFirstEvent() async {
        guard let first = events.first, let id = first.eventIdentifier else {
            errorMessage = "No event to edit."
            return
        }
        let newStart = first.startDate
        do {
            let updated = try await dataManager.editEvent(eventID: id, newTitle: first.title, newDate: newStart, newDuration: first.endDate.timeIntervalSince(first.startDate))
            if let idx = events.firstIndex(where: { $0.eventIdentifier == id }) {
                events[idx] = updated
            }
            events.sort { $0.startDate < $1.startDate }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif

    public func loadCalendars() async {
        do {
            let calendars = try await dataManager.fetchCalendars()
            availableCalendars = calendars
            if selectedCalendar == nil {
                selectedCalendar = calendars.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refreshEventsCache() async {
        await loadCalendarEvents()
    }
}
