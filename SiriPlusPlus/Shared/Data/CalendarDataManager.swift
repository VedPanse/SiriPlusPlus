import Foundation
import EventKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
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

    public func fetchEventsForToday() async throws -> [UserCalendarEvent] {
        let start = Date.now.startOfDay()
        let end = Date.now.endOfDay()
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        return ekEvents.map { ekEvent in
            UserCalendarEvent(
                eventIdentifier: ekEvent.eventIdentifier,
                title: ekEvent.title,
                startDate: ekEvent.startDate,
                endDate: ekEvent.endDate,
                location: ekEvent.location
            )
        }
    }

    public func createEvent(title: String,
                            date: Date,
                            duration: TimeInterval,
                            location: String?,
                            url: URL?,
                            notes: String?) async throws -> UserCalendarEvent {
        try await ensureAccess()
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = date
        event.endDate = date.addingTimeInterval(duration)
        event.location = location
        event.url = url
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent)
        return UserCalendarEvent(
            eventIdentifier: event.eventIdentifier,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            location: event.location
        )
    }

    public func editEvent(eventID: String, newTitle: String, newDate: Date, newDuration: TimeInterval) async throws -> UserCalendarEvent {
        try await ensureAccess()
        guard let ekEvent = eventStore.event(withIdentifier: eventID) else {
            throw CalendarAccessError.eventNotFound
        }
        ekEvent.title = newTitle
        ekEvent.startDate = newDate
        ekEvent.endDate = newDate.addingTimeInterval(newDuration)
        try eventStore.save(ekEvent, span: .thisEvent)
        return UserCalendarEvent(
            eventIdentifier: ekEvent.eventIdentifier,
            title: ekEvent.title,
            startDate: ekEvent.startDate,
            endDate: ekEvent.endDate,
            location: ekEvent.location
        )
    }

    public func openCalendar(at date: Date?) {
        #if os(macOS)
        let appURL = URL(fileURLWithPath: "/System/Applications/Calendar.app")
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        #else
        if let url = URL(string: "calshow://") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func ensureAccess() async throws {
        let granted = try await requestAccessIfNeeded()
        guard granted else { throw CalendarAccessError.accessDenied }
    }
}

// MARK: - Date Helpers
private extension Date {
    func startOfDay() -> Date {
        Calendar.current.startOfDay(for: self)
    }

    func endOfDay() -> Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay()) ?? self
    }
}

// MARK: - Errors
public enum CalendarAccessError: LocalizedError {
    case accessDenied
    case eventNotFound

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access is needed to display events. Please enable it in System Settings."
        case .eventNotFound:
            return "Could not find the calendar event to edit."
        }
    }
}
