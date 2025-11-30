import Foundation
import Combine

@MainActor
public final class CalendarViewModel: ObservableObject {
    @Published public var events: [UserCalendarEvent] = []
    @Published public var isLoading: Bool = false
    @Published public var accessDenied: Bool = false
    @Published public var errorMessage: String?
    #if canImport(EventKitUI)
    public var eventStore: EKEventStore { dataManager.eventStore }
    #endif

    private let dataManager: CalendarDataManager

    public init(dataManager: CalendarDataManager = .shared) {
        self.dataManager = dataManager
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

    public func openFirstEventInCalendar() {
        if let first = events.first {
            dataManager.openCalendar(at: first.startDate)
        } else {
            dataManager.openCalendar(at: Date())
        }
    }

    public func openCalendarApp() {
        dataManager.openCalendar(at: Date())
    }

    #if canImport(EventKitUI)
    public func prepareEventForEditing() async -> EditableEvent? {
        do {
            let event = try await dataManager.makeEditableEventForEditing()
            return EditableEvent(ekEvent: event)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
    #endif
}
