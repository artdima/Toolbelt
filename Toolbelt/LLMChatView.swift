//
//  LLMChatView.swift
//  Toolbelt
//

import SwiftUI

// MARK: - Модель сообщения

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String // "user" | "assistant"
    var content: String
}

// MARK: - Окно чата

enum LLMChatWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            DockPresence.activate()
            return
        }

        DockPresence.retain()

        let hosting = NSHostingController(rootView: LLMChatView())
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "LLM Chat"
        newWindow.setContentSize(NSSize(width: 480, height: 620))
        newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        window = newWindow

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { _ in
            window = nil
            DockPresence.release()
        }

        newWindow.makeKeyAndOrderFront(nil)
        DockPresence.activate()
    }
}

// MARK: - Вью чата

struct LLMChatView: View {
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isLoading = false
    @State private var modelName: String?
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    private let baseURL = "http://localhost:1234/v1"

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        print("[LLM \(formatter.string(from: Date()))] \(message)")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Заголовок
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text(modelName ?? "Подключение…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    messages.removeAll()
                    errorMessage = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Очистить историю")
                .disabled(messages.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Сообщения
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty {
                            Text("Задайте вопрос — ответ придёт с вашего LLM-сервера")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 40)
                        }
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if isLoading, messages.last?.role != "assistant" {
                            HStack {
                                ProgressView().controlSize(.small)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: messages) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if let errorMessage {
                Text("⚠ \(errorMessage)")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            Divider()

            // Поле ввода
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Сообщение…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .font(.system(size: 13))
                    .focused($inputFocused)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(12)
        }
        .frame(minWidth: 380, minHeight: 420)
        .task {
            inputFocused = true
            await loadModel()
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    // MARK: - Логика

    private func loadModel() async {
        guard let url = URL(string: "\(baseURL)/models") else { return }
        log("→ GET \(url)")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse {
                log("← HTTP \(http.statusCode) \(url)")
            }
            log("← body: \(String(data: data, encoding: .utf8) ?? "<не utf8>")")
            struct ModelList: Decodable {
                struct Model: Decodable { let id: String }
                let data: [Model]
            }
            let list = try JSONDecoder().decode(ModelList.self, from: data)
            modelName = list.data.first(where: { !$0.id.contains("embed") })?.id
                ?? list.data.first?.id
                ?? "local-model"
            log("Выбрана модель: \(modelName ?? "?")")
        } catch {
            modelName = "local-model"
            errorMessage = "Сервер недоступен: \(error.localizedDescription)"
            log("✗ Ошибка запроса моделей: \(error)")
        }
    }

    private func send() {
        guard canSend else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        errorMessage = nil
        messages.append(ChatMessage(role: "user", content: text))
        isLoading = true

        Task {
            await streamCompletion()
            isLoading = false
        }
    }

    private func streamCompletion() async {
        guard let url = URL(string: "\(baseURL)/chat/completions") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let body: [String: Any] = [
            "model": modelName ?? "local-model",
            "stream": true,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            log("→ POST \(url)")
            if let bodyData = request.httpBody {
                log("→ body: \(String(data: bodyData, encoding: .utf8) ?? "<не utf8>")")
            }

            let start = Date()
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            if let http = response as? HTTPURLResponse {
                log("← HTTP \(http.statusCode) за \(String(format: "%.2f", Date().timeIntervalSince(start))) c")
                if http.statusCode != 200 {
                    errorMessage = "Ошибка сервера: HTTP \(http.statusCode)"
                    return
                }
            }

            struct StreamChunk: Decodable {
                struct Choice: Decodable {
                    struct Delta: Decodable { let content: String? }
                    let delta: Delta?
                }
                let choices: [Choice]
            }

            messages.append(ChatMessage(role: "assistant", content: ""))
            let assistantIndex = messages.count - 1

            var chunkCount = 0
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else {
                    if !line.isEmpty { log("← (не SSE): \(line)") }
                    continue
                }
                let payload = line.dropFirst(6)
                if payload == "[DONE]" {
                    log("← [DONE], чанков: \(chunkCount), символов: \(messages[assistantIndex].content.count)")
                    break
                }
                guard let data = payload.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                      let delta = chunk.choices.first?.delta?.content
                else {
                    log("← чанк без delta.content: \(payload)")
                    continue
                }
                chunkCount += 1
                messages[assistantIndex].content += delta
            }

            if messages[assistantIndex].content.isEmpty {
                messages[assistantIndex].content = "(пустой ответ)"
            }
        } catch {
            errorMessage = "Не удалось получить ответ: \(error.localizedDescription)"
            log("✗ Ошибка стриминга: \(error)")
        }
    }
}

// MARK: - Пузырь сообщения

private struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            Text(attributed)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    isUser
                        ? AnyShapeStyle(Color.accentColor.opacity(0.85))
                        : AnyShapeStyle(Color.primary.opacity(0.08))
                )
                .foregroundStyle(isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: message.content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.content)
    }
}

#Preview {
    LLMChatView()
}
