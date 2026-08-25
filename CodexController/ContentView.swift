import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var bluetooth = BLEPeripheralController()

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("CODEX")
                    .font(.largeTitle.bold())

                VStack(spacing: 6) {
                    Text("Status: \(bluetooth.status.label)")
                        .font(.headline)
                    Text(bluetooth.bluetoothState)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("⚡  FAST") { bluetooth.send(.fast) }
                    .buttonStyle(CodexButtonStyle(color: .orange))
                    .disabled(!bluetooth.isConnected)

                Button("🧠  DEEP") { bluetooth.send(.deep) }
                    .buttonStyle(CodexButtonStyle(color: .indigo))
                    .disabled(!bluetooth.isConnected)

                Text("Reasoning: \(bluetooth.reasoning.label)")
                    .font(.subheadline.monospaced())

                VStack(spacing: 10) {
                    Text("Model: \(bluetooth.model.label)")
                        .font(.subheadline.monospaced())

                    HStack(spacing: 8) {
                        ForEach(CodexModel.selectable) { model in
                            Button(model.label) { bluetooth.selectModel(model) }
                                .buttonStyle(ModelButtonStyle(isSelected: bluetooth.model == model))
                                .disabled(!bluetooth.isConnected)
                        }
                    }
                }
            }
            .padding(28)

            if let color = bluetooth.status.borderColor {
                StatusBorder(color: color)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: bluetooth.status)
    }
}

private struct StatusBorder: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 42, style: .continuous)
            .strokeBorder(color, lineWidth: 10)
            .shadow(color: color.opacity(0.8), radius: 8)
            .padding(3)
    }
}

private extension CodexStatus {
    var borderColor: Color? {
        switch self {
        case .done:
            .green
        case .working, .waitingForUser:
            .blue
        case .awaitingApproval:
            .yellow
        case .disconnected, .idle, .error:
            nil
        }
    }
}

private struct CodexButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.bold())
            .frame(maxWidth: .infinity, minHeight: 62)
            .foregroundStyle(.white)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct ModelButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                isSelected ? Color.blue : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(isSelected ? 0 : 0.45), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview { ContentView() }
