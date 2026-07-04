import SwiftUI
import SphereCore

/// Settings "Models" page: browse the curated on-device models, see size and
/// RAM-fit badges, download / cancel / delete, and pick the active one.
public struct ModelsScreen: View {
    private let manager: ModelManager

    public init(manager: ModelManager) { self.manager = manager }

    public var body: some View {
        List {
            Section {
                ForEach(manager.catalog) { model in
                    row(model)
                }
            } footer: {
                Text("Models run entirely on your device — private and free. They download over Wi-Fi and live in on-device storage.")
            }
        }
        .navigationTitle("Models")
    }

    @ViewBuilder
    private func row(_ model: ModelInfo) -> some View {
        let state = manager.state(for: model)
        let fit = manager.ramFit(for: model)
        let isActive = manager.activeModelID == model.id

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.body.weight(.medium))
                    Text("\(ModelFit.sizeLabel(model)) · \(model.quant) · \(fit.label)")
                        .font(.caption)
                        .foregroundStyle(fit == .insufficient ? .orange : .secondary)
                }
                Spacer()
                control(model, state: state, fit: fit)
            }

            if case .downloading(let progress) = state {
                ProgressView(value: progress)
            }

            if state == .installed {
                Button {
                    manager.setActive(isActive ? nil : model.id)
                } label: {
                    Label(isActive ? "Active" : "Use this model",
                          systemImage: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? SphereTheme.accent(for: .mindfulness) : .secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func control(_ model: ModelInfo, state: ModelDownloadState, fit: RAMFit) -> some View {
        switch state {
        case .notInstalled, .failed:
            Button("Get") { manager.startDownload(model) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(fit == .insufficient || !manager.fitsOnDisk(model))
        case .downloading:
            Button("Cancel") { manager.cancelDownload(model) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .installed:
            Button("Delete", role: .destructive) { manager.remove(model) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
