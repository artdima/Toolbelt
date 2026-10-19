//
//  MCPPanelSection.swift
//  Toolbelt
//
//  MCP in the menu bar panel: the status, the switch and today's calls.
//

import SwiftUI

struct MCPPanelSection: View {
    private let hub = MCPHub.shared

    var body: some View {
        PanelSection("MCP", id: "mcp") {
            PanelRow(
                title: hub.statusTitle,
                systemImage: "server.rack",
                role: hub.isRunning && !hub.clients.isEmpty ? .prominent : .standard,
                detail: Plural.counted(hub.callsToday, "call today", "calls today")
            ) {
                AppWindows.mcp()
            }
            .help("Resources, Claude connection and the call log")

            PanelToggleRow(
                title: "MCP enabled",
                systemImage: "power",
                isOn: Binding(get: { hub.isEnabled }, set: { hub.setEnabled($0) })
            )
        }
    }
}
