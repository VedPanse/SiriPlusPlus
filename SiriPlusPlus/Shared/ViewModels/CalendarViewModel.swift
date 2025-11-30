import Foundation
import Combine

@MainActor
public final class CalendarViewModel: ObservableObject {
    @Published public var events: [UserCalendarEvent] = []
    @Published public var isLoading: Bool = false
    @Published public var accessDenied: Bool = false
    @Published public var errorMessage: String?

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

            let fetched = try await dataManager.fetchEventsForCurrentMonth()
            events = fetched
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
