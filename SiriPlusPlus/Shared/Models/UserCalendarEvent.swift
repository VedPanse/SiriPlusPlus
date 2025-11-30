import Foundation

public struct UserCalendarEvent: Identifiable, Equatable {
    public let id = UUID()
    public let eventIdentifier: String?
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let location: String?

    public init(eventIdentifier: String?, title: String, startDate: Date, endDate: Date, location: String?) {
        self.eventIdentifier = eventIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
    }
}
