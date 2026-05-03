//
//  InputDevicePriorityListView.swift
//  fluid
//
//  Microphone priority list UI — lets users rank input devices so FluidVoice
//  always uses the highest-ranked device that is currently connected.
//

import CoreAudio
import SwiftUI

/// A view that shows the user-defined microphone priority list.
/// Devices can be reordered by dragging; the app will always use the
/// first *available* (connected) device in the list when STT starts.
struct InputDevicePriorityListView: View {
    /// All input devices currently visible to CoreAudio (refreshed from parent).
    @Binding var inputDevices: [AudioDevice.Device]

    @ObservedObject private var settings = SettingsStore.shared

    /// Drag-and-drop state
    @State private var draggingUID: String?

    // MARK: - Helpers

    /// Builds the display list: priority-list items first (in order),
    /// then any connected device not yet in the list at the end.
    private var displayItems: [PriorityItem] {
        var items: [PriorityItem] = []
        let priorityList = settings.inputDevicePriorityList
        let connectedUIDs = Set(inputDevices.map { $0.uid })

        // 1. Devices that are in the priority list (in order)
        for uid in priorityList {
            let name = inputDevices.first(where: { $0.uid == uid })?.name
                ?? cachedName(for: uid)
                ?? uid
            let isConnected = connectedUIDs.contains(uid)
            items.append(PriorityItem(uid: uid, name: name, isConnected: isConnected))
        }

        // 2. Connected devices not yet in the list (tail — unlisted)
        for device in inputDevices where !priorityList.contains(device.uid) {
            items.append(PriorityItem(uid: device.uid, name: device.name, isConnected: true))
        }

        return items
    }

    /// Persist a human-readable name for devices that may go offline.
    @State private var nameCache: [String: String] = [:]

    private func cachedName(for uid: String) -> String? {
        nameCache[uid]
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Microphone Priority")
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                if settings.inputDevicePriorityList.isEmpty {
                    Button("Initialize from current devices") {
                        self.initializeList()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Reset") {
                        settings.inputDevicePriorityList = []
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.red)
                }
            }

            if displayItems.isEmpty {
                Text("No input devices detected. Click Refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayItems.enumerated()), id: \.element.uid) { index, item in
                        PriorityRowView(
                            item: item,
                            rank: index + 1,
                            isTopRanked: index == 0,
                            onMoveUp: index > 0 ? { self.move(uid: item.uid, direction: .up) } : nil,
                            onMoveDown: index < displayItems.count - 1 ? { self.move(uid: item.uid, direction: .down) } : nil
                        )
                        .background(
                            item.isConnected && index == 0
                                ? Color.accentColor.opacity(0.08)
                                : Color.clear
                        )

                        if index < displayItems.count - 1 {
                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

                Text("⬆ Drag or use arrows to reorder. The first ✅ device is used when you record.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .onAppear {
            self.updateNameCache()
            // Auto-initialize from connected devices if list is empty and devices are available
            if settings.inputDevicePriorityList.isEmpty && !inputDevices.isEmpty {
                self.initializeList()
            }
        }
        .onChange(of: inputDevices) { _, _ in
            self.updateNameCache()
        }
    }

    // MARK: - Actions

    private func initializeList() {
        // Start with whatever devices are connected right now
        settings.inputDevicePriorityList = inputDevices.map { $0.uid }
        updateNameCache()
    }

    private enum MoveDirection { case up, down }

    private func move(uid: String, direction: MoveDirection) {
        var list = settings.inputDevicePriorityList

        // Ensure all displayed items are in the list first
        for item in displayItems where !list.contains(item.uid) {
            list.append(item.uid)
        }

        guard let idx = list.firstIndex(of: uid) else { return }
        switch direction {
        case .up where idx > 0:
            list.swapAt(idx, idx - 1)
        case .down where idx < list.count - 1:
            list.swapAt(idx, idx + 1)
        default:
            return
        }
        settings.inputDevicePriorityList = list
    }

    private func updateNameCache() {
        for device in inputDevices {
            nameCache[device.uid] = device.name
        }
    }
}

// MARK: - Priority Item Model

private struct PriorityItem: Identifiable {
    let uid: String
    let name: String
    let isConnected: Bool

    var id: String { uid }
}

// MARK: - Row View

private struct PriorityRowView: View {
    let item: PriorityItem
    let rank: Int
    let isTopRanked: Bool
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            // Rank badge
            Text("\(rank)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            // Availability indicator
            Circle()
                .fill(item.isConnected ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)

            // Device name
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                if !item.isConnected {
                    Text("Not connected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if isTopRanked && item.isConnected {
                    Text("Active — used for recording")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()

            // Reorder arrows
            HStack(spacing: 2) {
                Button {
                    onMoveUp?()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(onMoveUp == nil)
                .opacity(onMoveUp == nil ? 0.3 : 1)

                Button {
                    onMoveDown?()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(onMoveDown == nil)
                .opacity(onMoveDown == nil ? 0.3 : 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}
