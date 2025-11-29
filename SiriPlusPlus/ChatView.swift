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
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                messages.append(Message(role: .assistant, text: response.content))
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

    public init() {}

    public var body: some View {
        ZStack {
            FullscreenVisualEffect()
                .ignoresSafeArea()

            #if os(macOS)
            macOSLayout
                .frame(minWidth: 420, idealWidth: 480, maxWidth: 540)
                .padding(20)
            #else
            iOSLayout
                .padding(.horizontal)
                .padding(.top, 12)
            #endif
        }
    }

    @ViewBuilder
    private var macOSLayout: some View {
        HStack(spacing: 0) {
            ZStack {
                BlurContainer(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08))
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 10)
                chatStack
                    .padding(18)
            }
            .frame(maxWidth: 520)

            Divider()

            ZStack {
                BlurContainer(material: .sidebar, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text("Context Panel")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.clear)
    }

    @ViewBuilder
    private var iOSLayout: some View {
        VStack(spacing: 12) {
            chatStack
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.1))
                )
                .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
        }
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
                TextField("Message", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .onSubmit { viewModel.sendMessage() }

                Button(action: viewModel.sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
}

// MARK: - Fullscreen Background
private struct FullscreenVisualEffect: View {
    var body: some View {
        #if os(macOS)
        ZStack {
            BlurContainer(material: .hudWindow, blendingMode: .behindWindow)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.accentColor.opacity(0.1),
                    Color.black.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
        }
        #else
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.accentColor.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 24)
        }
        #endif
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
