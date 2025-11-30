import Foundation

public struct UserCalendarEvent: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let location: String?

    public init(title: String, startDate: Date, endDate: Date, location: String?) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
    }
}
