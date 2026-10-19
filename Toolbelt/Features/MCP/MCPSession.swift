//
//  MCPSession.swift
//  Toolbelt
//
//  One client connected through toolbelt-mcp, with an MCP server of its own.
//

import Foundation
import MCP
import OSLog

actor MCPSession {
    nonisolated let id = UUID()

    private let server: Server
    private let transport: SocketTransport
    private weak var hub: MCPHub?
    private var isInitialized = false

    static let instructions = """
    Toolbelt is a macOS app of the user that holds tokens for their developer services and \
    calls them on the user's behalf. Every tool is read-only. When the user pastes a GitLab link, \
    call gitlab_resolve_url with it first.
    """

    init(fileDescriptor: Int32, hub: MCPHub, version: String) {
        self.hub = hub
        transport = SocketTransport(fileDescriptor: fileDescriptor)
        server = Server(
            name: "toolbelt",
            version: version,
            instructions: Self.instructions,
            capabilities: .init(tools: .init(listChanged: true))
        )
    }

    func run() async {
        let id = id

        await server.withMethodHandler(ListTools.self) { [weak hub] _ in
            ListTools.Result(tools: await hub?.tools() ?? [])
        }
        await server.withMethodHandler(CallTool.self) { [weak hub] params in
            guard let hub else {
                return CallTool.Result(content: [.text(text: "Toolbelt is shutting down.", annotations: nil, _meta: nil)], isError: true)
            }
            return await hub.call(params, session: id)
        }

        do {
            try await server.start(transport: transport) { [weak self, weak hub] client, _ in
                await self?.markInitialized()
                await hub?.session(id, didInitializeAs: client.name, version: client.version)
            }
            await server.waitUntilCompleted()
        } catch {
            Log.mcp.error("An MCP session could not start: \(error.localizedDescription, privacy: .public)")
        }

        await server.stop()
        await hub?.sessionDidEnd(id)
    }

    func notifyToolsChanged() async {
        guard isInitialized else { return }
        try? await server.notify(ToolListChangedNotification.message())
    }

    func close() async {
        await server.stop()
    }

    private func markInitialized() {
        isInitialized = true
    }
}
