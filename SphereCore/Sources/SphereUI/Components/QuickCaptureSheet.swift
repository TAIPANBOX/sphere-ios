import SwiftUI
import SphereCore

/// One text/voice field that logs across spheres: type or dictate "water 2,
/// mood 4, spent 4.50 on coffee" and the rule parser routes each fact to the
/// right sphere tool. Attacks logging fatigue — the #1 tracker-abandonment
/// cause — by making the common logs a single line.
public struct QuickCaptureSheet: View {
    private let run: (String) async -> [CaptureResult]

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var results: [CaptureResult] = []
    @State private var working = false
    @State private var missed = false
    @State private var successTick = 0
    @FocusState private var fieldFocused: Bool
    #if os(iOS)
    @State private var dictation = SpeechDictation()
    #endif

    public init(run: @escaping (String) async -> [CaptureResult]) {
        self.run = run
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    TextField(text: $text, axis: .vertical) {
                        Text(ui: "water 2 · mood 4 · spent 4.50 on coffee")
                    }
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(submit)
                    #if os(iOS)
                    if dictation.isAvailable {
                        Button {
                            dictation.toggle { text = $0 }
                        } label: {
                            Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                                .font(.title3)
                                .foregroundStyle(dictation.isRecording ? .red : .accentColor)
                        }
                    }
                    #endif
                }

                if !results.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                            Label(result.summary,
                                  systemImage: result.isError
                                    ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(result.isError ? .orange : .green)
                        }
                    }
                }

                if missed {
                    Text(ui: "Didn't catch that. Try wording like \"water 2\", \"mood 4\", or \"spent 12 on lunch\" — or open a sphere's chat for anything else.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .sphereHaptic(.success, trigger: successTick)
            .navigationTitle(Text(ui: "Quick capture"))
            .onAppear { fieldFocused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Done") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: submit) { Text(ui: "Log") }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || working)
                }
            }
        }
    }

    private func submit() {
        let input = text.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty, !working else { return }
        working = true
        missed = false
        #if os(iOS)
        dictation.stop()
        #endif
        Task {
            let output = await run(input)
            results = output
            missed = output.isEmpty
            if !output.isEmpty {
                text = ""
                successTick += 1
            }
            working = false
        }
    }
}
