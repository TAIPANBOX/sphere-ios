import SwiftUI
import SphereCore

/// The open/close ritual flow. Morning: set an intention and commit to a few
/// focus items. Evening: see what you actually did today and jot a reflection,
/// then "close the day".
public struct RitualSheet: View {
    private let phase: RitualPhase
    private let focusItems: [FocusItem]
    private let highlights: [String]
    private let onMorning: (String, [String]) -> Void
    private let onEvening: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var intention: String
    @State private var reflection: String
    @State private var selected: Set<String>

    public init(
        phase: RitualPhase,
        focusItems: [FocusItem] = [],
        highlights: [String] = [],
        initialIntention: String = "",
        initialReflection: String = "",
        initialFocusIds: [String] = [],
        onMorning: @escaping (String, [String]) -> Void = { _, _ in },
        onEvening: @escaping (String) -> Void = { _ in }
    ) {
        self.phase = phase
        self.focusItems = focusItems
        self.highlights = highlights
        self.onMorning = onMorning
        self.onEvening = onEvening
        _intention = State(initialValue: initialIntention)
        _reflection = State(initialValue: initialReflection)
        _selected = State(initialValue: Set(initialFocusIds))
    }

    public var body: some View {
        NavigationStack {
            Form {
                if phase == .evening { eveningContent } else { morningContent }
            }
            .navigationTitle(phase == .evening ? "Close your day" : "Plan your day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(phase == .evening ? "Close the day" : "Start my day", action: finish)
                }
            }
        }
    }

    @ViewBuilder private var morningContent: some View {
        Section {
            TextField("What matters most today?", text: $intention, axis: .vertical)
                .lineLimit(2...4)
        } header: {
            Text("Today's intention")
        }
        if !focusItems.isEmpty {
            Section("Commit to today") {
                ForEach(focusItems) { item in
                    Button {
                        if selected.contains(item.id) { selected.remove(item.id) }
                        else { selected.insert(item.id) }
                    } label: {
                        HStack(spacing: 10) {
                            Text(item.emoji)
                            Text(item.title).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selected.contains(item.id)
                                ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(item.id) ? .green : .secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var eveningContent: some View {
        Section("Today you…") {
            if highlights.isEmpty {
                Text("A quiet day — that's fine too.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(highlights.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
        }
        Section {
            TextField("How did today feel? One line is enough.",
                      text: $reflection, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("Reflection")
        }
    }

    private func finish() {
        if phase == .evening {
            onEvening(reflection)
        } else {
            onMorning(intention, Array(selected))
        }
        dismiss()
    }
}
