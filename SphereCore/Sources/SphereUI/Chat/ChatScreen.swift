import SwiftUI
import PhotosUI
import SphereCore

public struct ChatScreen: View {
    private let session: ChatSession
    private let accent: Color

    @State private var draft = ""
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var pendingImages: [LLMImage] = []
    #if os(iOS)
    @State private var dictation = SpeechDictation()
    #endif

    public init(session: ChatSession) {
        self.session = session
        self.accent = SphereTheme.accent(for: session.sphereType ?? .goals)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(session.messages) { message in
                            MessageBubble(message: message, accent: accent)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: session.messages.last?.content) {
                    if let lastId = session.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }
            inputBar
        }
        .navigationTitle(session.sphereName)
        .onChange(of: pickedItems) {
            Task { await loadPickedImages() }
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 6) {
            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { index, image in
                            AttachmentThumbnail(image: image) {
                                pendingImages.remove(at: index)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $pickedItems, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                #if os(iOS)
                Button {
                    dictation.toggle { draft = $0 }
                } label: {
                    Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                        .foregroundStyle(dictation.isRecording ? .red : .secondary)
                        .symbolEffect(.pulse, isActive: dictation.isRecording)
                }
                .buttonStyle(.plain)
                #endif
                TextField("Message your \(session.sphereName) agent…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit(sendDraft)
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? accent : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private var canSend: Bool {
        !session.isBusy
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
    }

    private func sendDraft() {
        guard canSend else { return }
        #if os(iOS)
        dictation.stop()
        #endif
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        draft = ""
        pendingImages = []
        pickedItems = []
        Task { await session.send(text, images: images) }
    }

    private func loadPickedImages() async {
        var images: [LLMImage] = []
        for item in pickedItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                images.append(LLMImage(mimeType: "image/jpeg", base64Data: data.base64EncodedString()))
            }
        }
        pendingImages = images
    }
}

// MARK: - Bubbles

struct MessageBubble: View {
    let message: SphereCore.ChatMessage
    let accent: Color

    var body: some View {
        if message.isToolConfirmation {
            toolChip
        } else {
            HStack {
                if message.isUser { Spacer(minLength: 40) }
                bubble
                if !message.isUser { Spacer(minLength: 40) }
            }
        }
    }

    private var toolChip: some View {
        Label(
            message.content,
            systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (message.isError ? Color.red : Color.green).opacity(0.12),
            in: Capsule()
        )
        .foregroundStyle(message.isError ? .red : .green)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(message.images.enumerated()), id: \.offset) { _, image in
                AttachmentImage(image: image)
            }
            if message.isTyping {
                ProgressView().controlSize(.small)
            } else if !message.content.isEmpty {
                Text(markdown(message.content))
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            message.isUser ? AnyShapeStyle(accent.opacity(0.9)) : AnyShapeStyle(.background.secondary),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .foregroundStyle(message.isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .overlay(alignment: .bottomTrailing) {
            if message.isStreaming {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .padding(6)
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(text)
    }
}

// MARK: - Attachments

struct AttachmentImage: View {
    let image: LLMImage

    var body: some View {
        if let data = Data(base64Encoded: image.base64Data),
           let platformImage = PlatformImage.make(from: data) {
            platformImage
                .resizable()
                .scaledToFill()
                .frame(maxWidth: 220, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct AttachmentThumbnail: View {
    let image: LLMImage
    let onRemove: () -> Void

    var body: some View {
        if let data = Data(base64Encoded: image.base64Data),
           let platformImage = PlatformImage.make(from: data) {
            platformImage
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(2)
                }
        }
    }
}

enum PlatformImage {
    static func make(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}
