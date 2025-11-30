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
    @available(iOS 18.0, macOS 15.0, *)
    private var liveSession: LanguageModelSession?

    public init() {}

    public func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMessage = Message(role: .user, text: trimmed)
        messages.append(userMessage)
        inputText = ""

        Task {
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
                let response = try await liveSession?.respond(to: prompt)
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
            quickPromptRow(title: "Triage my inbox and draft replies for anything urgent")
            quickPromptRow(title: "Plan my day: calendar, reminders, and travel buffers")
            quickPromptRow(title: "Order my usual lunch from DoorDash at noon")
        }
        .frame(maxWidth: 460, alignment: .center)
    }

    private func quickPromptRow(title: String) -> some View {
        Button {
            viewModel.inputText = title
            viewModel.sendMessage()
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
                .onSubmit { viewModel.sendMessage() }
            Button(action: viewModel.sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
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
