import SwiftUI

public struct CalendarView: View {
    @ObservedObject var viewModel: CalendarViewModel
    #if canImport(EventKitUI)
    @State private var editingEvent: EditableEvent?
    #endif

    public init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if viewModel.accessDenied {
                Text("Calendar access is needed to display events. Please enable it in System Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else if viewModel.events.isEmpty && viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if viewModel.events.isEmpty {
                Text("No events found for this month.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                availabilitySection
                timeline
                actions
                footer
            }
        }
        .padding(14)
        .glassTile()
        .task {
            await viewModel.loadCalendarEvents()
        }
        #if canImport(EventKitUI)
        .sheet(item: $editingEvent) { wrapper in
            EventEditView(event: wrapper.ekEvent, store: viewModel.eventStore) {
                editingEvent = nil
                Task { await viewModel.loadCalendarEvents() }
            }
        }
        #endif
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
            Text("See my availability: today")
                .font(.footnote.weight(.semibold))
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(availabilityHeadline)
                .font(.title3.weight(.bold))
            Text(availabilitySubheadline)
                .font(.subheadline)
        }
    }

    private var timeline: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(timeMarkers, id: \.self) { marker in
                        Text(marker)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Rectangle()
                    .frame(width: 1)
                    .foregroundStyle(Color.secondary.opacity(0.25))

                VStack(spacing: 6) {
                    ForEach(viewModel.events) { event in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(eventFill(for: event))
                            .overlay(eventLabel(for: event).padding(.horizontal, 12))
                            .frame(height: blockHeight(for: event))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(isOngoing(event: event) ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.08),
                                                   lineWidth: isOngoing(event: event) ? 2 : 1)
                            )
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                #if canImport(EventKitUI)
                Task {
                    if let wrapper = await viewModel.prepareEventForEditing() {
                        editingEvent = wrapper
                    }
                }
                #else
                viewModel.openCalendarApp()
                #endif
            } label: { calendarActionLabel("Create Event") }
            .buttonStyle(.plain)

            Button {
                viewModel.openFirstEventInCalendar()
            } label: { calendarActionLabel("Edit Event") }
            .buttonStyle(.plain)

            Button {
                viewModel.openCalendarApp()
            } label: { calendarActionLabel("Full Calendar") }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        HStack {
            Image(systemName: "asterisk.circle")
                .font(.caption)
            Text("More actions")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private func eventFill(for event: UserCalendarEvent) -> some ShapeStyle {
        if isOngoing(event: event) {
            return Color.accentColor.opacity(0.45)
        } else if let location = event.location, location.lowercased().contains("coffee") {
            return Color.blue.opacity(0.45)
        }
        return Color.gray.opacity(0.25)
    }

    private func eventLabel(for event: UserCalendarEvent) -> some View {
        HStack {
            Text(event.title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let location = event.location {
                Text(location)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(timeRange(for: event))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func blockHeight(for event: UserCalendarEvent) -> CGFloat {
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let minutes = max(duration / 60, 15) // minimum block time
        return CGFloat(min(max(minutes * 0.8, 32), 90))
    }

    private var timeMarkers: [String] {
        guard let first = viewModel.events.first?.startDate else {
            return ["9:00 AM", "11:00 AM", "1:00 PM", "3:00 PM"]
        }
        let calendar = Calendar.current
        let baseHour = calendar.component(.hour, from: first)
        let markers = [0, 2, 4, 6].compactMap { offset -> String? in
            guard let date = calendar.date(byAdding: .hour, value: offset, to: first) else { return nil }
            return timeFormatter.string(from: date)
        }
        return markers
    }

    private var availabilityHeadline: String {
        guard let next = viewModel.events.first else { return "Available today" }
        let start = timeFormatter.string(from: next.startDate)
        return "Available until \(start)"
    }

    private var availabilitySubheadline: String {
        guard let next = viewModel.events.first else {
            return "Would you like to create an event?"
        }
        return "Would you like to create an event for \(next.title) at \(timeFormatter.string(from: next.startDate))?"
    }

    private func timeRange(for event: UserCalendarEvent) -> String {
        "\(timeFormatter.string(from: event.startDate)) – \(timeFormatter.string(from: event.endDate))"
    }

    private func calendarActionLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }

    private func isOngoing(event: UserCalendarEvent) -> Bool {
        let now = Date()
        return now >= event.startDate && now <= event.endDate
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}

#if canImport(EventKitUI)
import EventKitUI

public struct EditableEvent: Identifiable {
    public let id = UUID()
    public let ekEvent: EKEvent
}

private struct EventEditView: UIViewControllerRepresentable {
    let event: EKEvent
    let store: EKEventStore
    var onComplete: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onComplete: () -> Void
        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true) { self.onComplete() }
        }
    }
}
#endif
