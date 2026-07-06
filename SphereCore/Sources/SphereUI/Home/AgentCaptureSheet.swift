import SwiftUI
import PhotosUI
import SphereCore

/// The bottom "talk to your agent" surface: type or dictate, attach a photo or
/// snap one (e.g. a receipt), and the agent routes everything to the right
/// spheres on its own. Text-only input also works with the free rule-based
/// capture; images need a vision-capable backend.
public struct AgentCaptureSheet: View {
    /// Runs the capture. `(text, images)` in, logged results out.
    private let onCapture: (String, [Data]) async -> [CaptureResult]
    private let onConfigureProvider: (() -> Void)?
    private let agentAvailable: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var images: [Data] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var results: [CaptureResult] = []
    @State private var working = false
    @State private var missed = false
    @State private var showingCamera = false
    #if os(iOS)
    @State private var dictation = SpeechDictation()
    #endif

    public init(
        agentAvailable: Bool = false,
        onConfigureProvider: (() -> Void)? = nil,
        onCapture: @escaping (String, [Data]) async -> [CaptureResult]
    ) {
        self.agentAvailable = agentAvailable
        self.onConfigureProvider = onConfigureProvider
        self.onCapture = onCapture
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    prompt
                    if !images.isEmpty { attachments }
                    if working { thinking }
                    if !results.isEmpty { resultsList }
                    if missed { missHint }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("Your agent")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingCamera) {
                CameraPicker { data in if let data { images.append(data) } }
                    .ignoresSafeArea()
            }
            #endif
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPicked(items) }
            }
        }
    }

    // MARK: - Pieces

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Tell me anything", systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SphereTheme.accent(for: .mindfulness))
            Text("Type or dictate a thought, or snap a receipt — I'll sort it into the right spheres.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var attachments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                    ZStack(alignment: .topTrailing) {
                        (PlatformImage.make(from: data) ?? Image(systemName: "photo"))
                            .resizable().scaledToFill()
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button {
                            images.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(4)
                    }
                }
            }
        }
    }

    private var thinking: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Sorting it into your spheres…").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logged").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                Label(result.summary, systemImage: result.isError
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(result.isError ? .orange : .green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
    }

    private var missHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("I couldn't sort that automatically.")
                .font(.subheadline).foregroundStyle(.secondary)
            if !agentAvailable, let onConfigureProvider {
                Button("Turn on the assistant") { dismiss(); onConfigureProvider() }
                    .font(.subheadline)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 3, matching: .images) {
                Image(systemName: "photo").font(.title3)
            }
            #if os(iOS)
            Button { showingCamera = true } label: {
                Image(systemName: "camera").font(.title3)
            }
            if dictation.isAvailable {
                Button { dictation.toggle { text = $0 } } label: {
                    Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(dictation.isRecording ? .red : .accentColor)
                }
            }
            #endif
            TextField("Message your agent", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(working || (text.trimmingCharacters(in: .whitespaces).isEmpty && images.isEmpty))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Actions

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
        }
        pickerItems = []
    }

    private func send() async {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working, !(input.isEmpty && images.isEmpty) else { return }
        working = true
        missed = false
        #if os(iOS)
        dictation.stop()
        #endif
        let output = await onCapture(input, images)
        results = output
        missed = output.isEmpty
        if !output.isEmpty { text = ""; images = [] }
        working = false
    }
}

private extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

#if os(iOS)
import UIKit

/// Minimal camera capture (SwiftUI has no native camera view).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data?) -> Void
        init(onImage: @escaping (Data?) -> Void) { self.onImage = onImage }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onImage(image?.jpegData(compressionQuality: 0.7))
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
            picker.dismiss(animated: true)
        }
    }
}
#endif
