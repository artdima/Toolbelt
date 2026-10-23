//
//  MCPHub.swift
//  Toolbelt
//
//  The MCP server inside Toolbelt: the socket, the connected clients, the tools and the call log.
//

import Foundation
import MCP
import Observation
import OSLog

@Observable
@MainActor
final class MCPHub {
    static let shared = MCPHub()

    enum ServerState: Equatable {
        case off
        case running
        case failed(String)
    }

    struct ConnectedClient: Identifiable, Equatable {
        let id: UUID
        let connectedAt: Date
        var name: String?
        var version: String?

        var title: String {
            guard let name else { return "Connecting…" }
            return [name, version].compactMap { $0 }.joined(separator: " ")
        }
    }

    static let logLimit = 200
    static let pingToolName = "toolbelt_ping"

    private static let enabledKey = "mcp.isEnabled"
    private static let callsDayKey = "mcp.callsToday.day"
    private static let callsCountKey = "mcp.callsToday.count"

    private(set) var state = ServerState.off
    private(set) var clients: [ConnectedClient] = []
    private(set) var log: [MCPCallLogEntry] = []
    private(set) var isEnabled: Bool
    private var callsDay: String
    private var callsCount: Int

    @ObservationIgnored let socketPath: String
    @ObservationIgnored private let store: MCPResourceStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var listener: MCPSocketListener?
    @ObservationIgnored private var sessions: [UUID: MCPSession] = [:]
    @ObservationIgnored private var publishedTools: [Tool] = []

    convenience init() {
        self.init(store: .shared, defaults: .standard, socketPath: MCPSocket.defaultURL.path(percentEncoded: false))
    }

    init(store: MCPResourceStore, defaults: UserDefaults, socketPath: String) {
        self.store = store
        self.defaults = defaults
        self.socketPath = socketPath
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        callsDay = defaults.string(forKey: Self.callsDayKey) ?? ""
        callsCount = defaults.integer(forKey: Self.callsCountKey)
        store.onChange = { [weak self] in
            self?.toolsMayHaveChanged()
        }
    }

    var callsToday: Int {
        callsDay == Self.dayStamp(Date()) ? callsCount : 0
    }

    var isRunning: Bool { state == .running }

    var statusTitle: String {
        switch state {
        case .off:
            return "MCP is off"
        case .failed:
            return "MCP could not start"
        case .running where clients.isEmpty:
            return "Not connected to Claude"
        case .running:
            return "Running · \(Plural.counted(clients.count, "client", "clients"))"
        }
    }

    // MARK: Lifecycle

    func startIfEnabled() {
        guard isEnabled else { return }
        start()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard listener == nil else { return }
        // SO_NOSIGPIPE covers the sockets; this covers anything else a vanished client leaves behind.
        signal(SIGPIPE, SIG_IGN)

        let listener = MCPSocketListener(path: socketPath) { [weak self] fd in
            Task { @MainActor [weak self] in
                guard let self else {
                    close(fd)
                    return
                }
                self.accept(fd)
            }
        }
        do {
            try listener.start()
            self.listener = listener
            publishedTools = tools()
            state = .running
            Log.mcp.info("MCP socket is listening")
        } catch {
            state = .failed(error.localizedDescription)
            Log.mcp.error("MCP socket failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        listener?.stop()
        listener = nil
        for session in sessions.values {
            Task { await session.close() }
        }
        sessions.removeAll()
        clients.removeAll()
        state = .off
    }

    private func accept(_ fd: Int32) {
        guard listener != nil else {
            close(fd)
            return
        }
        let session = MCPSession(fileDescriptor: fd, hub: self, version: Self.appVersion)
        sessions[session.id] = session
        clients.append(ConnectedClient(id: session.id, connectedAt: Date()))
        Task { await session.run() }
    }

    func session(_ id: UUID, didInitializeAs name: String, version: String) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[index].name = name
        clients[index].version = version
        Log.mcp.info("MCP client connected: \(name, privacy: .public) \(version, privacy: .public)")
    }

    func sessionDidEnd(_ id: UUID) {
        sessions.removeValue(forKey: id)
        clients.removeAll { $0.id == id }
    }

    // MARK: Tools

    func tools() -> [Tool] {
        var tools = [Self.pingTool]
        for provider in MCPProviders.all {
            let enabled = store.resources.filter { $0.kind == provider.kind && $0.isEnabled }
            if !enabled.isEmpty {
                tools += provider.tools(for: enabled)
            }
        }
        return tools
    }

    func call(_ params: CallTool.Parameters, session id: UUID) async -> CallTool.Result {
        let started = Date()
        let arguments = params.arguments ?? [:]

        var secrets: [String] = []
        let output: MCPToolOutput
        if params.name == Self.pingToolName {
            output = .success(pingText())
        } else if let provider = MCPProviders.all.first(where: { $0.owns(toolName: params.name) }) {
            let credentials = credentials(for: provider)
            secrets = credentials.flatMap(\.secrets)
            if credentials.allSatisfy({ $0.token == nil }) {
                output = .failure("No \(provider.kind.title) resource is turned on in Toolbelt, so \(params.name) is unavailable.")
            } else {
                let name = params.name
                output = await Task.detached(priority: .userInitiated) {
                    await provider.call(name, arguments: arguments, credentials: credentials)
                }.value
            }
        } else {
            output = .failure("Toolbelt has no tool named \(params.name).")
        }

        let text = MCPText.redacting(secrets, in: output.text)
        record(
            tool: params.name,
            arguments: MCPText.redacting(secrets, in: ToolArguments.compactJSON(arguments)),
            session: id,
            isError: output.isError,
            started: started,
            responseSize: text.count
        )
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: output.isError)
    }

    /// Secrets of turned-off resources are not read: such a resource only tells the
    /// provider that it exists.
    private func credentials(for provider: any MCPProvider) -> [MCPCredential] {
        store.resources
            .filter { $0.kind == provider.kind }
            .map { resource -> MCPCredential in
                guard resource.isEnabled else { return MCPCredential(resource: resource, token: nil) }
                return MCPCredential(
                    resource: resource,
                    token: store.token(for: resource.id),
                    clientSecret: provider.asksForClientCredentials ? store.clientSecret(for: resource.id) : nil
                )
            }
    }

    private func toolsMayHaveChanged() {
        guard isRunning else { return }
        let current = tools()
        guard current != publishedTools else { return }
        publishedTools = current
        for session in sessions.values {
            Task { await session.notifyToolsChanged() }
        }
    }

    private func pingText() -> String {
        var lines = ["Toolbelt \(Self.appVersion) is running."]
        let enabled = store.resources.filter(\.isEnabled)
        if enabled.isEmpty {
            lines.append("No resources are turned on. The user adds them in Toolbelt → MCP.")
        } else {
            lines.append("Enabled resources:")
            lines += enabled.map { "\($0.kind.title) · \($0.name) · \($0.host)" }
        }
        return lines.joined(separator: "\n")
    }

    private static let pingTool = Tool(
        name: pingToolName,
        description: "Check that Toolbelt is running and list the resources the user enabled in it.",
        inputSchema: JSONSchema.object([:]),
        annotations: Tool.Annotations(readOnlyHint: true, openWorldHint: false)
    )

    // MARK: Log

    func clearLog() {
        log.removeAll()
    }

    private func record(
        tool: String,
        arguments: String,
        session id: UUID,
        isError: Bool,
        started: Date,
        responseSize: Int
    ) {
        let duration = Date().timeIntervalSince(started)
        let client = clients.first { $0.id == id }?.title ?? "Disconnected client"
        let entry = MCPCallLogEntry(
            date: started,
            client: client,
            tool: tool,
            arguments: MCPText.truncated(arguments, to: 300),
            isError: isError,
            duration: duration,
            responseSize: responseSize
        )
        log.insert(entry, at: 0)
        if log.count > Self.logLimit {
            log.removeLast(log.count - Self.logLimit)
        }

        let today = Self.dayStamp(started)
        if callsDay != today {
            callsDay = today
            callsCount = 0
        }
        callsCount += 1
        defaults.set(callsDay, forKey: Self.callsDayKey)
        defaults.set(callsCount, forKey: Self.callsCountKey)

        Log.mcp.info(
            "\(tool, privacy: .public) → \(isError ? "error" : "ok", privacy: .public) in \(Int(duration * 1000), privacy: .public) ms"
        )
    }

    private static func dayStamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
