//
//  SimulatorsView.swift
//  Toolbelt
//
//  Launching an iOS simulator or an Android emulator without Xcode and Android Studio.
//

import SwiftUI

struct SimulatorsView: View {
    @State private var model = SimulatorsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar

            if let warning = model.warning {
                Text("⚠ \(warning)")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            content

            if let result = model.result, !result.isSuccess {
                failureCard(result)
            }
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 480)
        .task {
            await model.reload()
        }
        .onDisappear {
            model.stopTracking()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField("Search", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            if model.isLoading {
                ProgressView().controlSize(.small)
            }

            RefreshButton(isDisabled: model.isLoading) {
                Task { await model.reload() }
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.devices.isEmpty {
            LoadingState(text: "Looking for simulators…")
        } else if !model.hasVisibleDevices {
            EmptyState(
                systemImage: "iphone.slash",
                text: model.devices.isEmpty
                    ? "No iOS simulators and no Android AVDs were found"
                    : "Nothing matches the search"
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section(MobilePlatform.ios.title, devices: model.iosDevices)
                    section(MobilePlatform.android.title, devices: model.androidDevices)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func section(_ title: String, devices: [SimulatorDevice]) -> some View {
        if !devices.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                VStack(spacing: 2) {
                    ForEach(devices) { device in
                        row(device)
                    }
                }
            }
        }
    }

    private func row(_ device: SimulatorDevice) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(stateColor(device.state))
                .frame(width: 7, height: 7)
                .help(device.state.title)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if !device.detail.isEmpty {
                    Text(device.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if model.isBusy(device) {
                ProgressView().controlSize(.small)
            } else if device.state == .shutdown {
                Button("Launch") {
                    Task { await model.boot(device) }
                }
            } else {
                Button("Stop") {
                    Task { await model.shutdown(device) }
                }
                .disabled(!model.canStop(device))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func failureCard(_ result: SimulatorActionResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.red)
                Text("Could not start")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if !result.command.isEmpty {
                    CopyButton(value: result.command, help: "Copy command")
                }
            }

            if !result.command.isEmpty {
                Text(result.command)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !result.output.isEmpty {
                Text(result.output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func stateColor(_ state: SimulatorState) -> Color {
        switch state {
        case .shutdown: return Color.secondary.opacity(0.4)
        case .booting: return Color.orange
        case .booted: return Color.green
        }
    }
}

#Preview {
    SimulatorsView()
}
