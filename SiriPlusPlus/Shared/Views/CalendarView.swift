import SwiftUI
import EventKit
#if os(macOS)
import AppKit
#endif

public struct CalendarView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @State private var showCreateSheet = false
    @State private var newTitle: String = ""
    @State private var newStartDate: Date = Date()
    @State private var newDurationMinutes: Double = 30
    @State private var newLocation: String = ""
    @State private var newURL: String = ""
    @State private var newNotes: String = ""
    @State private var isAllDay: Bool = false
    @State private var newEndDate: Date = Date().addingTimeInterval(3600)
    @State private var selectedAlertOption: AlertOption = .none
    @State private var repeatFrequency: RepeatFrequency = .none
    #if os(macOS)
    @State private var travelTime: TravelTimeOption = .none
    #endif
    @State private var selectedCalendar: EKCalendar?

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
        .sheet(isPresented: $showCreateSheet) {
            createSheet
        }
        .task {
            await viewModel.loadCalendars()
            selectedCalendar = viewModel.availableCalendars.first
        }
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
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                hourGrid
                ForEach(viewModel.events) { event in
                    eventBlock(for: event)
                }
            }
            .frame(height: hourHeight * CGFloat(hourMarkers.count))
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(height: hourHeight * CGFloat(hourMarkers.count))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            CreateEventButton {
                newStartDate = Date()
                showCreateSheet = true
            }
            EditEventButton {
                #if canImport(EventKitUI)
                Task { await viewModel.editFirstEvent() }
                #else
                viewModel.openCalendarApp()
                #endif
            }
            ShowFullCalendarButton {
                viewModel.openCalendarApp()
            }
        }
        .padding(.top, 12)
    }

    private var createSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title", text: $newTitle)
                        .font(.system(size: 18, weight: .semibold))
                    Toggle("All-Day", isOn: $isAllDay)
                        .toggleStyle(.switch)
                }

                Section(header: Text("Starts").font(.headline)) {
                    DatePicker("", selection: $newStartDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                }

                Section(header: Text("Ends").font(.headline)) {
                    DatePicker("", selection: $newEndDate, in: newStartDate...Date.distantFuture, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                }

                Section {
                    Picker("Calendar", selection: Binding(get: {
                        selectedCalendar ?? viewModel.availableCalendars.first
                    }, set: { selectedCalendar = $0 })) {
                        ForEach(viewModel.availableCalendars, id: \.calendarIdentifier) { cal in
                            Text(cal.title).tag(Optional(cal))
                        }
                    }

                    Picker("Alert", selection: $selectedAlertOption) {
                        ForEach(AlertOption.allCases, id: \.self) { option in
                            Text(option.text).tag(option)
                        }
                    }
                }

                Section {
                    Picker("Repeat", selection: $repeatFrequency) {
                        ForEach(RepeatFrequency.allCases, id: \.self) { option in
                            Text(option.text).tag(option)
                        }
                    }
                }

                Section(header: Text("Details")) {
                    TextField("Location", text: $newLocation)
                    TextField("URL", text: $newURL)
                    TextField("Notes", text: $newNotes, axis: .vertical)
                        .lineLimit(3...6)
                }

                #if os(macOS)
                Section {
                    Picker("Travel Time", selection: $travelTime) {
                        ForEach(TravelTimeOption.allCases, id: \.self) { option in
                            Text(option.text).tag(option)
                        }
                    }
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(
                Group {
                    #if os(macOS)
                    VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    #else
                    Color(UIColor.systemGroupedBackground)
                    #endif
                }
                .ignoresSafeArea()
            )
            .navigationTitle("New Event")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showCreateSheet = false
                        resetCreateFields()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let location = newLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                        let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        let notes = newNotes.trimmingCharacters(in: .whitespacesAndNewlines)

                        Task {
                            await viewModel.createEvent(
                                title: title,
                                startDate: newStartDate,
                                endDate: newEndDate,
                                isAllDay: isAllDay,
                                durationMinutes: newDurationMinutes,
                                calendar: selectedCalendar ?? viewModel.availableCalendars.first,
                                alert: selectedAlertOption,
                                repeatRule: repeatFrequency,
                                travelTime: {
                                    #if os(macOS)
                                    travelTime
                                    #else
                                    .none
                                    #endif
                                }(),
                                location: location,
                                urlString: url,
                                notes: notes
                            )
                            showCreateSheet = false
                            resetCreateFields()
                        }
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(minWidth: 460, minHeight: 520)
        }
    }

    private func resetCreateFields() {
        newTitle = ""
        newLocation = ""
        newURL = ""
        newNotes = ""
        newDurationMinutes = 30
        newStartDate = Date()
        newEndDate = Date().addingTimeInterval(3600)
        isAllDay = false
        selectedAlertOption = .none
        repeatFrequency = .none
        #if os(macOS)
        travelTime = .none
        #endif
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
            return Color.accentColor
        } else if let location = event.location, location.lowercased().contains("coffee") {
            return Color.blue
        }
        return Color.gray
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

    private var hourFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter
    }

    private var hourMarkers: [Date] {
        let start = startOfDay(for: Date())
        return (0..<24).compactMap { Calendar.current.date(byAdding: .hour, value: $0, to: start) }
    }

    private var hourHeight: CGFloat { 42 }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(hourMarkers, id: \.self) { mark in
                HStack {
                    Text(hourFormatter.string(from: mark))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .leading)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .padding(.trailing, 8)
                }
                .frame(height: hourHeight, alignment: .top)
            }
        }
    }

    private func eventBlock(for event: UserCalendarEvent) -> some View {
        let offset = offsetForEvent(event)
        let height = blockHeight(for: event)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(eventFill(for: event))
            .overlay(eventLabel(for: event).padding(.horizontal, 12))
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isOngoing(event: event) ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.08),
                                   lineWidth: isOngoing(event: event) ? 2 : 1)
            )
            .padding(.leading, 58)
            .offset(y: offset)
    }

    private func offsetForEvent(_ event: UserCalendarEvent) -> CGFloat {
        let startOfDay = startOfDay(for: event.startDate)
        let minutesFromStart = event.startDate.timeIntervalSince(startOfDay) / 60
        let pointsPerMinute = hourHeight / 60
        return CGFloat(minutesFromStart) * pointsPerMinute
    }
}

func startOfDay(for date: Date) -> Date {
    Calendar.current.startOfDay(for: date)
}

#if os(macOS)
private struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
#endif

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
