import Foundation
import EventKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public final class CalendarDataManager {
    public static let shared = CalendarDataManager()
    private let eventStore = EKEventStore()
    #if canImport(EventKitUI)
    public var eventStoreForUI: EKEventStore { eventStore }
    #endif

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

    public func createQuickEvent(title: String, startDate: Date, endDate: Date, location: String?) async throws -> UserCalendarEvent {
        try await ensureAccess()
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.location = location
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent, commit: true)
        return UserCalendarEvent(
            eventIdentifier: event.eventIdentifier,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            location: event.location
        )
    }

    public func openCalendar(at date: Date?) {
        let target = date ?? Date()
        let interval = target.timeIntervalSinceReferenceDate
        guard let url = URL(string: "calshow:\(interval)") else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    #if canImport(EventKitUI)
    public func makeEditableEventForEditing() async throws -> EKEvent {
        try await ensureAccess()
        let event = EKEvent(eventStore: eventStore)
        event.calendar = eventStore.defaultCalendarForNewEvents
        return event
    }
    #endif

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

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access is needed to display events. Please enable it in System Settings."
        }
    }
}
