import Foundation
import Combine

@MainActor
public final class CalendarViewModel: ObservableObject {
    @Published public var events: [UserCalendarEvent] = []
    @Published public var isLoading: Bool = false
    @Published public var accessDenied: Bool = false
    @Published public var errorMessage: String?
    private let dataManager: CalendarDataManager

    public init(dataManager: CalendarDataManager? = nil) {
        self.dataManager = dataManager ?? CalendarDataManager.shared
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
                            durationMinutes: Double,
                            location: String?,
                            urlString: String?,
                            notes: String?) async {
        let duration = durationMinutes * 60
        let url = urlString.flatMap { URL(string: $0) }
        do {
            let created = try await dataManager.createEvent(
                title: title.isEmpty ? "New Event" : title,
                date: startDate,
                duration: duration,
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
}
