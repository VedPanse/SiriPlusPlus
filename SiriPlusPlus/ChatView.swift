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
    @State private var enableGPT4 = true
    @State private var enableBERT = false
    @State private var enableLlama = false

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
        HStack(alignment: .top, spacing: 16) {
            mainGlassCard
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            sidePanel
                .frame(width: 320, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.trailing, 12)
        .background(Color.clear)
    }

    @ViewBuilder
    private var iOSLayout: some View {
        VStack(spacing: 12) {
            mainGlassCard
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Main Glass Card
    private var mainGlassCard: some View {
        VStack(spacing: 18) {
            headerHero
            quickPrompts
            chatStack
        }
        .padding(22)
        .glassCard()
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
            quickPromptRow(title: "Help me write a product update")
            quickPromptRow(title: "How does this API work?")
            quickPromptRow(title: "Summarize the meeting notes")
        }
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
    }

    private var chatStack: some View {
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

            HStack(alignment: .bottom, spacing: 8) {
                HStack(spacing: 10) {
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
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glassTile()
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal Cognition")
                        .font(.headline)
                    Label("2 sources connected", systemImage: "bolt.horizontal.fill")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Spacer()
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            GlassButton(label: "Preferences", systemImage: "gearshape.fill") {}

            VStack(alignment: .leading, spacing: 12) {
                Text("General Knowledge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                toggleRow(title: "GPT-4", isOn: $enableGPT4)
                toggleRow(title: "BERT", isOn: $enableBERT)
                toggleRow(title: "Llama", isOn: $enableLlama)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Integrations")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                integrationRow(title: "Notion", status: "Manage")
                integrationRow(title: "Google Drive", status: "Connect")
                integrationRow(title: "Asana", status: "Connect")
                integrationRow(title: "Jira", status: "Connect")
            }

            Spacer()
        }
        .padding(18)
        .glassCard()
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: "bolt.fill")
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassTile()
    }

    private func integrationRow(title: String, status: String) -> some View {
        HStack {
            Label(title, systemImage: "link")
            Spacer()
            Text(status)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassTile()
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
private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.12))
            )
            .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 10)
    }
}

private struct GlassTile: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
    }
}

private extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
    func glassTile() -> some View { modifier(GlassTile()) }
}

// MARK: - Glass Button
private struct GlassButton: View {
    var label: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: systemImage)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassTile()
        }
        .buttonStyle(.plain)
    }
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
