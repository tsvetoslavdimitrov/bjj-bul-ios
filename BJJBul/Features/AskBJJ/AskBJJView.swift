import SwiftUI

/// "Ask BJJ" AI chat. Requires sign-in; messages go through the ask-bjj Edge Function.
struct AskBJJView: View {
    @Environment(AppServices.self) private var services
    @State private var messages: [AIChatMessage]
    @State private var input = ""
    @State private var conversationId: UUID?
    @State private var isSending = false
    @State private var usage: AIUsage?
    @State private var errorMessage: String?
    @State private var confirmDeleteHistory = false

    private var isBulgarian: Bool {
        Locale.current.language.languageCode?.identifier == "bg"
    }

    private let bottomId = "bottom"

    /// initialMessages: used by DEBUG demo screenshots only.
    init(initialMessages: [AIChatMessage] = []) {
        _messages = State(initialValue: initialMessages)
    }

    var body: some View {
        Group {
            if services.isSignedIn {
                chat
            } else {
                ContentUnavailableView {
                    Label("ai.title", systemImage: "sparkles")
                } description: {
                    Text("ai.signIn")
                }
            }
        }
        .navigationTitle("ai.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if services.isSignedIn && !messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        messages = []
                        conversationId = nil
                        errorMessage = nil
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(Text("ai.newChat"))
                }
            }
        }
        .toolbar {
            if services.isSignedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("ai.deleteHistory", role: .destructive) {
                            confirmDeleteHistory = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("ai.deleteHistory.confirm", isPresented: $confirmDeleteHistory, titleVisibility: .visible) {
            Button("ai.deleteHistory", role: .destructive) {
                Task { await deleteHistory() }
            }
        }
        .task(id: services.isSignedIn) {
            if services.isSignedIn {
                usage = try? await services.ai.usage()
            }
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        disclaimer
                        if messages.isEmpty {
                            starters
                        }
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                        if isSending {
                            TypingIndicator()
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                        }
                        Color.clear.frame(height: 1).id(bottomId)
                    }
                    .padding(.vertical)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(bottomId, anchor: .bottom) }
                }
                .onChange(of: isSending) { _, _ in
                    withAnimation { proxy.scrollTo(bottomId, anchor: .bottom) }
                }
            }
            Divider()
            inputBar
        }
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("ai.disclaimer", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let usage {
                Text("ai.remaining \(usage.remaining) \(usage.limit)")
                    .font(.caption)
                    .foregroundStyle(usage.remaining == 0 ? Color.red : Color.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ai.starters")
                .font(.subheadline)
                .bold()
            ForEach(AIStarterPrompts.prompts(bulgarian: isBulgarian), id: \.self) { prompt in
                Button {
                    Task { await send(prompt) }
                } label: {
                    Text(verbatim: prompt)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor))
                }
                .buttonStyle(.plain)
                .disabled(isSending)
            }
        }
        .padding(.horizontal)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("ai.placeholder", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
            Button {
                let text = input
                Task { await send(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || usage?.remaining == 0)
            .accessibilityLabel(Text("ai.send"))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @MainActor
    private func deleteHistory() async {
        guard let history = services.ai as? AIHistoryService else { return }
        do {
            try await history.deleteAllConversations()
            messages = []
            conversationId = nil
            errorMessage = nil
        } catch {
            errorMessage = AIChatError.failed(error.localizedDescription).errorDescription
        }
    }

    @MainActor
    private func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let limited = String(text.prefix(2000))
        input = ""
        errorMessage = nil
        messages.append(AIChatMessage(id: UUID(), role: .user, text: limited, createdAt: Date()))
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await services.ai.send(message: limited, conversationId: conversationId,
                                                   locale: isBulgarian ? "bg" : "en")
            conversationId = reply.conversationId ?? conversationId
            usage = AIUsage(remaining: reply.remaining, limit: reply.limit)
            messages.append(AIChatMessage(id: UUID(), role: .assistant, text: reply.text, createdAt: Date()))
        } catch let error as AIChatError {
            if case .dailyLimit = error, let current = usage {
                usage = AIUsage(remaining: 0, limit: current.limit)
            }
            errorMessage = error.errorDescription
        } catch {
            errorMessage = AIChatError.failed(error.localizedDescription).errorDescription
        }
    }
}

struct ChatBubble: View {
    let message: AIChatMessage

    private var isUser: Bool { message.role == .user }

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: options)) ?? AttributedString(message.text)
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(rendered)
                .font(.body)
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isUser ? Color.accentColor : Color.secondary.opacity(0.15))
                )
            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }
}

struct TypingIndicator: View {
    var body: some View {
        HStack {
            TimelineView(.periodic(from: Date(), by: 0.35)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 7, height: 7)
                            .opacity(index == step ? 1 : 0.35)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.15)))
            }
            Spacer()
        }
        .padding(.horizontal)
        .accessibilityLabel(Text("ai.typing"))
    }
}
