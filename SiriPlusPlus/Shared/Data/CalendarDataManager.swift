import Foundation
import EventKit

public final class CalendarDataManager {
    public static let shared = CalendarDataManager()
    private let eventStore = EKEventStore()

    private init() {}

    public func requestAccessIfNeeded() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized:
            return true
        case .fullAccess:
            return true
        case .writeOnly:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                #if os(macOS)
                if #available(macOS 14.0, *) {
                    eventStore.requestFullAccessToEvents { granted, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                } else {
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
                #else
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
                #endif
            }
            return granted
        @unknown default:
            return false
        }
    }

    public func fetchEventsForCurrentMonth() async throws -> [UserCalendarEvent] {
        let start = Date.now.startOfMonth()
        let end = Date.now.endOfMonth()
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        return ekEvents.map { ekEvent in
            UserCalendarEvent(
                title: ekEvent.title,
                startDate: ekEvent.startDate,
                endDate: ekEvent.endDate,
                location: ekEvent.location
            )
        }
    }
}

// MARK: - Date Helpers
private extension Date {
    func startOfMonth() -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }

    func endOfMonth() -> Date {
        let start = startOfMonth()
        return Calendar.current.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? self
    }
}
