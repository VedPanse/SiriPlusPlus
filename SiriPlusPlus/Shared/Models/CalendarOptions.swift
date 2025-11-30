import Foundation

public enum AlertOption: CaseIterable {
    case none, atTime, fiveMin, fifteenMin, thirtyMin, oneHour, oneDay

    public var text: String {
        switch self {
        case .none: return "None"
        case .atTime: return "At time of event"
        case .fiveMin: return "5 minutes before"
        case .fifteenMin: return "15 minutes before"
        case .thirtyMin: return "30 minutes before"
        case .oneHour: return "1 hour before"
        case .oneDay: return "1 day before"
        }
    }

    public var minutesBefore: Int? {
        switch self {
        case .none: return nil
        case .atTime: return 0
        case .fiveMin: return 5
        case .fifteenMin: return 15
        case .thirtyMin: return 30
        case .oneHour: return 60
        case .oneDay: return 1440
        }
    }
}

public enum RepeatFrequency: CaseIterable {
    case none, daily, weekly, monthly, yearly

    public var text: String {
        switch self {
        case .none: return "None"
        case .daily: return "Every Day"
        case .weekly: return "Every Week"
        case .monthly: return "Every Month"
        case .yearly: return "Every Year"
        }
    }
}

public enum TravelTimeOption: CaseIterable {
    case none, five, fifteen, thirty, oneHour

    public var text: String {
        switch self {
        case .none: return "None"
        case .five: return "5 minutes"
        case .fifteen: return "15 minutes"
        case .thirty: return "30 minutes"
        case .oneHour: return "1 hour"
        }
    }

    public var minutes: Int? {
        switch self {
        case .none: return nil
        case .five: return 5
        case .fifteen: return 15
        case .thirty: return 30
        case .oneHour: return 60
        }
    }
}
