import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var bluetooth = BLEPeripheralController()

    var body: some View {
        ZStack {
            CodexBackground()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    statusCard
                    modeSection
                    modelSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)

            if let color = bluetooth.status.borderColor {
                StatusBorder(color: color)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: bluetooth.status)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 46, height: 46)
                Image(systemName: "terminal.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.black)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("CODEX")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .tracking(1.2)
                Text("REMOTE CONTROL")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ConnectionBadge(isConnected: bluetooth.isConnected)
        }
        .padding(.horizontal, 2)
    }

    private var statusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(bluetooth.status.tint.opacity(0.16))
                    .frame(width: 54, height: 54)
                Image(systemName: bluetooth.status.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(bluetooth.status.tint)
                    .symbolEffect(.pulse, isActive: bluetooth.status == .working)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("CURRENT STATUS")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(bluetooth.status.label)
                    .font(.title3.weight(.bold))
                Text(bluetooth.bluetoothState)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("MODE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(bluetooth.executionMode.label.uppercased())
                    .font(.subheadline.monospaced().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Text("Reasoning: \(bluetooth.reasoning.label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .codexCard()
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Execution mode", subtitle: "Choose speed or deeper reasoning")
            HStack(spacing: 12) {
                ModeButton(
                    title: "FAST",
                    detail: bluetooth.executionMode.isFastEnabled ? "Tap to turn off" : "Priority speed",
                    symbol: "bolt.fill",
                    color: .orange,
                    isSelected: bluetooth.executionMode.isFastEnabled
                ) {
                    bluetooth.toggleFast()
                }
                ModeButton(
                    title: "DEEP",
                    detail: bluetooth.executionMode.isDeepEnabled ? "Tap to turn off" : "High reasoning",
                    symbol: "brain.head.profile.fill",
                    color: .indigo,
                    isSelected: bluetooth.executionMode.isDeepEnabled
                ) {
                    bluetooth.toggleDeep()
                }
            }
            .disabled(!bluetooth.isConnected)
            .opacity(bluetooth.isConnected ? 1 : 0.45)
        }
        .padding(18)
        .codexCard()
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Model", subtitle: "Select the engine for your next turn")
            HStack(spacing: 8) {
                ForEach(CodexModel.selectable) { model in
                    Button { bluetooth.selectModel(model) } label: {
                        VStack(spacing: 7) {
                            Image(systemName: model.symbol)
                                .font(.system(size: 17, weight: .semibold))
                            Text(model.label)
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(ModelButtonStyle(isSelected: bluetooth.model == model))
                    .disabled(!bluetooth.isConnected)
                    .accessibilityLabel("Select \(model.label) model")
                    .accessibilityAddTraits(bluetooth.model == model ? .isSelected : [])
                }
            }
            .opacity(bluetooth.isConnected ? 1 : 0.45)
        }
        .padding(18)
        .codexCard()
    }
}

private struct CodexBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.04, blue: 0.055).ignoresSafeArea()
            RadialGradient(colors: [Color.indigo.opacity(0.24), .clear], center: .topTrailing, startRadius: 10, endRadius: 390).ignoresSafeArea()
            RadialGradient(colors: [Color.blue.opacity(0.12), .clear], center: .bottomLeading, startRadius: 10, endRadius: 340).ignoresSafeArea()
        }
    }
}

private struct ConnectionBadge: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isConnected ? Color.green : Color.white.opacity(0.35))
                .frame(width: 7, height: 7)
                .shadow(color: isConnected ? .green : .clear, radius: 4)
            Text(isConnected ? "CONNECTED" : "OFFLINE")
                .font(.caption2.weight(.bold))
                .tracking(0.6)
        }
        .foregroundStyle(isConnected ? Color.green : Color.secondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1) }
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ModeButton: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .offset(x: 5, y: -5)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.black))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
        }
        .buttonStyle(ModeButtonStyle(color: color, isSelected: isSelected))
        .accessibilityLabel("Select \(title) execution mode")
        .accessibilityHint(detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct StatusBorder: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 42, style: .continuous)
            .strokeBorder(color.opacity(0.8), lineWidth: 5)
            .shadow(color: color.opacity(0.55), radius: 10)
            .padding(3)
    }
}

private extension View {
    func codexCard() -> some View {
        background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1) }
    }
}

private extension CodexStatus {
    var borderColor: Color? {
        switch self {
        case .done: .green
        case .working, .waitingForUser: .blue
        case .awaitingApproval: .yellow
        case .disconnected, .idle, .error: nil
        }
    }

    var tint: Color {
        switch self {
        case .disconnected: .gray
        case .idle: .cyan
        case .working, .waitingForUser: .blue
        case .done: .green
        case .error: .red
        case .awaitingApproval: .yellow
        }
    }

    var symbol: String {
        switch self {
        case .disconnected: "antenna.radiowaves.left.and.right.slash"
        case .idle: "sparkles"
        case .working: "gearshape.2.fill"
        case .waitingForUser: "person.wave.2.fill"
        case .done: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .awaitingApproval: "hand.raised.fill"
        }
    }
}

private extension CodexModel {
    var symbol: String {
        switch self {
        case .unknown: "questionmark"
        case .sol: "sun.max.fill"
        case .terra: "globe.americas.fill"
        case .luna: "moon.stars.fill"
        }
    }
}

private struct ModeButtonStyle: ButtonStyle {
    let color: Color
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                LinearGradient(
                    colors: isSelected
                        ? [color.opacity(0.48), color.opacity(0.22)]
                        : [color.opacity(0.17), color.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(isSelected ? color : color.opacity(0.28), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: isSelected ? color.opacity(0.3) : .clear, radius: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

private struct ModelButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.72))
            .background(isSelected ? Color.white : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.75))
                        .padding(7)
                }
            }
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(isSelected ? 0 : 0.1), lineWidth: 1) }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview { ContentView() }
