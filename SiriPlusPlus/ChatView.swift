import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
import FoundationModels

// MARK: - Local Models (ensure availability in this target)
public enum MessageRole: String, Sendable {
    case user
    case assistant
}

public struct Message: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let role: MessageRole
    public let text: String

    public init(id: UUID = UUID(), role: MessageRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

// MARK: - Local ViewModel (simple placeholder; replace with shared VM if available)
@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public var messages: [Message] = []
    @Published public var inputText: String = ""
    @Published public var isProcessing: Bool = false
    @Published public var errorMessage: String?
    @Published public var quickSuggestions: [String] = ChatViewModel.defaultSuggestions
    @Published public var isLoadingSuggestions: Bool = false
    @Published public var calendarContext: String = ""
    @available(iOS 18.0, macOS 15.0, *)
    private var liveSession: LanguageModelSession?
    @available(iOS 18.0, macOS 15.0, *)
    private var suggestionsSession: LanguageModelSession?
    @available(iOS 18.0, macOS 15.0, *)
    private var calendarIntentSession: LanguageModelSession?

    private static let defaultSuggestions = [
        "Triage my inbox and draft replies for anything urgent",
        "Plan my day: calendar, reminders, and travel buffers",
        "Order my usual lunch from DoorDash at noon"
    ]

    public init() {}

    public func sendMessage(calendarViewModel: CalendarViewModel? = nil) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMessage = Message(role: .user, text: trimmed)
        messages.append(userMessage)
        inputText = ""

        Task {
            if await handleCalendarIntent(prompt: trimmed, calendarViewModel: calendarViewModel) {
                return
            }
            await runSystemModel(prompt: trimmed)
        }
    }

    @MainActor
    private func runSystemModel(prompt: String) async {
        errorMessage = nil

        if #available(iOS 18.0, macOS 15.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                let fallback = "Model not available on this device"
                errorMessage = fallback
                messages.append(Message(role: .assistant, text: fallback))
                return
            }

            isProcessing = true
            defer { isProcessing = false }

            do {
                if liveSession == nil {
                    liveSession = LanguageModelSession()
                }
                let augmentedPrompt: String
                if calendarContext.isEmpty {
                    augmentedPrompt = prompt
                } else {
                    augmentedPrompt = """
                    You have full context of today's calendar:
                    \(calendarContext)

                    User: \(prompt)
                    """
                }

                let response = try await liveSession?.respond(to: augmentedPrompt)
                let text = response?.content ?? "No response"
                messages.append(Message(role: .assistant, text: text))
            } catch {
                let fallback = error.localizedDescription
                errorMessage = fallback
                messages.append(Message(role: .assistant, text: fallback))
            }
        } else {
            let fallback = "On-device model requires iOS 18 / macOS 15."
            errorMessage = fallback
            messages.append(Message(role: .assistant, text: fallback))
        }
    }

    @MainActor
    public func loadQuickSuggestions() async {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        guard SystemLanguageModel.default.isAvailable else { return }
        if isLoadingSuggestions { return }

        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }

        do {
            if suggestionsSession == nil {
                suggestionsSession = LanguageModelSession()
            }

            let prompt = """
            You are a personal AI assistant like an augmented Siri. Generate three concise, proactive suggestions for how you can help the user. Use the following examples as style and tone guidance:
            1) Triage my inbox and draft replies for anything urgent
            2) Plan my day: calendar, reminders, and travel buffers
            3) Order my usual lunch from DoorDash at noon

            Respond with three similar, helpful ideas, numbered 1-3. Keep each under 80 characters.
            """

            let response = try await suggestionsSession?.respond(to: prompt)
            let text = response?.content ?? ""
            let parsed = parseSuggestions(from: text)
            if !parsed.isEmpty {
                quickSuggestions = parsed
            }
        } catch {
            // Keep defaults on failure
        }
    }

    private func parseSuggestions(from text: String) -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var suggestions: [String] = []
        for line in lines {
            let stripped = line
                .replacingOccurrences(of: #"^\d+[\).\-\s]*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                suggestions.append(stripped)
            }
            if suggestions.count == 3 { break }
        }
        return suggestions
    }

    @MainActor
    public func refreshCalendarContext(events: [UserCalendarEvent]) {
        guard !events.isEmpty else {
            calendarContext = "No events scheduled for today."
            return
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let details = events.map { event in
            let start = formatter.string(from: event.startDate)
            let end = formatter.string(from: event.endDate)
            let location = event.location.map { " @ \($0)" } ?? ""
            return "- \(event.title)\(location) from \(start) to \(end)"
        }
        calendarContext = details.joined(separator: "\n")
    }

    @MainActor
    private func handleCalendarIntent(prompt: String, calendarViewModel: CalendarViewModel?) async -> Bool {
        guard let calendarViewModel else { return false }
        guard #available(iOS 18.0, macOS 15.0, *) else { return false }
        guard SystemLanguageModel.default.isAvailable else { return false }

        do {
            if calendarIntentSession == nil {
                calendarIntentSession = LanguageModelSession()
            }

            let intentPrompt = """
            You are a planning agent that converts user requests into structured calendar actions for today's calendar only.
            Use these examples as style guidance: triage inbox, plan my day, order lunch, create/edit/delete calendar items.
            Today's events:
            \(calendarContext.isEmpty ? "No events scheduled for today." : calendarContext)

            Respond ONLY with JSON matching:
            {
              "action": "create" | "edit" | "delete",
              "clarification": "string if you need more info, else empty",
              "events": [
                {
                  "title": "title of event",
                  "newTitle": "optional new title for edit",
                  "startTime": "ISO8601 string for start today, e.g. 2024-09-04T14:00:00Z or HH:mm",
                  "endTime": "ISO8601 string for end or HH:mm",
                  "durationMinutes": 60
                }
              ]
            }
            If details are missing, set "clarification" to the question you need and leave other fields as best-effort.
            """

            let response = try await calendarIntentSession?.respond(to: intentPrompt + "\nUser: \(prompt)")
            let jsonText = response?.content ?? ""
            print("[CalendarIntent] Raw model response: \(jsonText)")
            guard let intent = parseIntent(from: jsonText) else {
                print("[CalendarIntent] Failed to parse intent JSON")
                return false
            }
            print("[CalendarIntent] Parsed intent: \(intent)")

            if let clarification = intent.clarification, !clarification.isEmpty {
                messages.append(Message(role: .assistant, text: clarification))
                return true
            }

            switch intent.action {
            case .create:
                let created = try await applyCreates(intent.events, calendarViewModel: calendarViewModel)
                messages.append(Message(role: .assistant, text: created > 0 ? "Created \(created) event(s) for today." : "No event created."))
                refreshCalendarContext(events: calendarViewModel.events)
                return true
            case .edit:
                let edited = try await applyEdits(intent.events, calendarViewModel: calendarViewModel)
                messages.append(Message(role: .assistant, text: edited > 0 ? "Updated \(edited) event(s) for today." : "No matching events to update today."))
                refreshCalendarContext(events: calendarViewModel.events)
                return true
            case .delete:
                let deleted = try await applyDeletes(intent.events, calendarViewModel: calendarViewModel)
                messages.append(Message(role: .assistant, text: deleted > 0 ? "Deleted \(deleted) event(s) for today." : "No matching events to delete today."))
                refreshCalendarContext(events: calendarViewModel.events)
                return true
            case .unknown:
                return false
            }
        } catch {
            print("[CalendarIntent] Error handling intent: \(error)")
            return false
        }
    }

    private func parseIntent(from jsonText: String) -> CalendarIntent? {
        guard let start = jsonText.firstIndex(of: "{"), let end = jsonText.lastIndex(of: "}") else { return nil }
        let jsonSubstring = jsonText[start...end]
        guard let data = String(jsonSubstring).data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(CalendarIntent.self, from: data)
    }

    private func applyCreates(_ events: [CalendarIntent.EventSpec], calendarViewModel: CalendarViewModel) async throws -> Int {
        var count = 0
        for event in events {
            guard let start = event.startDate(timeline: .today),
                  let end = event.endDate(timeline: .today, fallbackDuration: event.durationMinutes ?? 60) else { continue }
            let title = event.title?.isEmpty == false ? event.title! : "New Event"
            print("[CalendarIntent] Creating event '\(title)' \(start) - \(end)")
            await calendarViewModel.createEvent(
                title: title,
                startDate: start,
                endDate: end,
                isAllDay: false,
                durationMinutes: Double(event.durationMinutes ?? 60),
                calendar: calendarViewModel.selectedCalendar,
                alert: .none,
                repeatRule: .none,
                travelTime: .none,
                location: nil,
                urlString: nil,
                notes: nil
            )
            count += 1
        }
        if count == 0 {
            print("[CalendarIntent] No events created; specs: \(events)")
        }
        await calendarViewModel.loadCalendarEvents()
        return count
    }

    private func applyEdits(_ events: [CalendarIntent.EventSpec], calendarViewModel: CalendarViewModel) async throws -> Int {
        var count = 0
        for spec in events {
            guard let match = calendarViewModel.matchingEvent(forTitle: spec.title ?? spec.newTitle ?? "") else {
                print("[CalendarIntent] No matching event to edit for title: \(spec.title ?? spec.newTitle ?? "")")
                continue
            }
            let start = spec.startDate(timeline: .today) ?? match.startDate
            let end = spec.endDate(timeline: .today, fallbackDuration: spec.durationMinutes ?? match.endDate.timeIntervalSince(match.startDate) / 60) ?? match.endDate
            let duration = end.timeIntervalSince(start)
            let newTitle = spec.newTitle ?? spec.title ?? match.title
            if let id = match.eventIdentifier {
                print("[CalendarIntent] Editing event '\(match.title)' -> '\(newTitle)' \(start) - \(end)")
                try await calendarViewModel.editEvent(eventID: id, newTitle: newTitle, newDate: start, newDuration: duration)
                count += 1
            }
        }
        if count == 0 {
            print("[CalendarIntent] No events edited; specs: \(events)")
        }
        await calendarViewModel.loadCalendarEvents()
        return count
    }

    private func applyDeletes(_ events: [CalendarIntent.EventSpec], calendarViewModel: CalendarViewModel) async throws -> Int {
        let ids = events.compactMap { spec in
            calendarViewModel.matchingEvent(forTitle: spec.title ?? "")?.eventIdentifier
        }
        guard !ids.isEmpty else { return 0 }
        print("[CalendarIntent] Deleting events with IDs: \(ids)")
        try await calendarViewModel.deleteEvents(eventIDs: ids)
        await calendarViewModel.loadCalendarEvents()
        return ids.count
    }

    private struct CalendarIntent: Decodable {
        enum Action: String, Decodable {
            case create, edit, delete, unknown
        }
        struct EventSpec: Decodable {
            let title: String?
            let newTitle: String?
            let startTime: String?
            let endTime: String?
            let durationMinutes: Double?

            func startDate(timeline: TimelineContext) -> Date? {
                guard let startTime else { return nil }
                return Date.fromISO8601(startTime) ?? timeline.dateForToday(timeString: startTime)
            }

            func endDate(timeline: TimelineContext, fallbackDuration: Double) -> Date? {
                if let endTime, let end = Date.fromISO8601(endTime) ?? timeline.dateForToday(timeString: endTime) {
                    return end
                }
                if let start = startDate(timeline: timeline) {
                    return start.addingTimeInterval(fallbackDuration * 60)
                }
                return nil
            }
        }

        let action: Action
        let clarification: String?
        let events: [EventSpec]
    }
}

private extension Date {
    static func fromISO8601(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}

private enum TimelineContext {
    case today

    func dateForToday(timeString: String) -> Date? {
        let formats = ["HH:mm", "H:mm", "HHmm", "h a", "h:mm a", "h.mm a"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var time: Date?
        for format in formats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: timeString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                time = parsed
                break
            }
        }
        guard let time else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let timeComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        return Calendar.current.date(from: components)
    }
}

// MARK: - ChatView
public struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var calendarViewModel = CalendarViewModel()

    public init() {}

    public var body: some View {
        ZStack {
            FullscreenVisualEffect()
                .ignoresSafeArea()

            #if os(macOS)
            macOSLayout
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            #else
            iOSLayout
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 18)
                .padding(.top, 18)
            #endif
        }
        .task {
            await viewModel.loadQuickSuggestions()
            await calendarViewModel.loadCalendarEvents()
            viewModel.refreshCalendarContext(events: calendarViewModel.events)
        }
        .onChange(of: calendarViewModel.events) { _, newValue in
            viewModel.refreshCalendarContext(events: newValue)
        }
    }

    @ViewBuilder
    private var macOSLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            mainColumnWithInput
                .frame(maxWidth: .infinity, alignment: .center)

            Divider()
                .frame(maxHeight: .infinity)
                .background(Color.white.opacity(0.18))

            ScrollView {
                sidePanel
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .frame(width: 480, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.trailing, 12)
        .background(Color.clear)
    }

    @ViewBuilder
    private var iOSLayout: some View {
        mainColumnWithInput
    }

    // MARK: - Main Column with Input
    private var mainColumnWithInput: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    mainGlassCard
                        .frame(maxWidth: 640, alignment: .center)
                        .padding(.bottom, 180) // leave room under scroll content
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                let bottomInset = max(proxy.size.height * 0.02, 20)
                inputBar
                    .padding(.horizontal, 32)
                    .padding(.bottom, bottomInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Main Glass Card
    private var mainGlassCard: some View {
        VStack(spacing: 18) {
            headerHero
            quickPrompts
            messageList
                .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, minHeight: 820, alignment: .topLeading)
        .padding(12)
    }

    // MARK: - Header
    private var headerHero: some View {
        VStack(spacing: 12) {
            Image("siripp")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)

            Text("Transform Your Ideas with Siri++")
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("Ask, summarize, and generate with an on-device model. Your data stays private.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick Prompts
    private var quickPrompts: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.quickSuggestions, id: \.self) { suggestion in
                quickPromptRow(title: suggestion)
            }
            if viewModel.isLoadingSuggestions {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("Refreshing suggestions with on-device AI…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: 460, alignment: .center)
    }

    private func quickPromptRow(title: String) -> some View {
        Button {
            viewModel.inputText = title
            viewModel.sendMessage(calendarViewModel: calendarViewModel)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassTile()
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .focusable(false)
        #endif
    }

    private var messageList: some View {
        VStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            messageBubble(for: message)
                                .id(message.id)
                        }
                    }
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastID = viewModel.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            if viewModel.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Thinking…")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .transition(.opacity)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.secondary)
            TextField("Ask anything…", text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit { viewModel.sendMessage(calendarViewModel: calendarViewModel) }
            Button(action: { viewModel.sendMessage(calendarViewModel: calendarViewModel) }) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .padding(2)
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.1))
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private func messageBubble(for message: Message) -> some View {
        HStack {
            if message.role == .assistant { Spacer(minLength: 0) }
            Text(message.text)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(message.role == .user ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                )
                .foregroundStyle(message.role == .user ? Color.accentColor : Color.primary)
                .frame(maxWidth: 380, alignment: .leading)
            if message.role == .user { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.vertical, 2)
    }

    // MARK: - Side Panel
    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Feed")
                .font(.headline)

            Label("Latest from your inbox", systemImage: "envelope.badge")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            feedEmailCard
            CalendarView(viewModel: calendarViewModel)

            Spacer()
        }
        .padding(18)
    }

    private var feedEmailCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.primary)
                Text("Coffee? · Mail from Marisa Lu")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Image(systemName: "paperplane")
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Marisa Lu")
                        .font(.headline)
                    Text("Coffee?")
                        .font(.title3.weight(.bold))
                }
                Spacer()
                Text("Just now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Hey Jason,")
                    .font(.subheadline.weight(.semibold))
                Text("""
Was wondering if you'd be interested in meeting my team at Philz Coffee at 11 AM today. No pressure if you can't make it, although I think you guys would really get along!

Marisa
""")
                    .font(.subheadline)
            }

            HStack(spacing: 12) {
                actionChip("Reply")
                actionChip("Forward")
                actionChip("Delete")
            }

            HStack {
                Image(systemName: "asterisk.circle")
                    .font(.caption)
                Text("More actions")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassTile()
    }

    private func actionChip(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.1))
            )
    }

}

// MARK: - Fullscreen Background
private struct FullscreenVisualEffect: View {
    var body: some View {
        #if os(macOS)
        BlurContainer(material: .hudWindow, blendingMode: .behindWindow)
        #else
        Rectangle().fill(.ultraThinMaterial)
        #endif
    }
}

// MARK: - Glass Modifiers
struct GlassTile: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
    }
}

extension View {
    func glassTile() -> some View { modifier(GlassTile()) }
}

// MARK: - Blur Container
#if os(macOS)
import AppKit
public struct BlurView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(material: NSVisualEffectView.Material = .sidebar,
                blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
                state: NSVisualEffectView.State = .active) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        view.wantsLayer = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

private struct BlurContainer: View {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    var body: some View {
        BlurView(material: material, blendingMode: blendingMode)
            .background(Color.clear)
    }
}
#else
private struct BlurContainer: View {
    var material: Any? = nil
    var blendingMode: Any? = nil
    var body: some View { Color.clear }
}
#endif

#Preview {
    ChatView()
}
