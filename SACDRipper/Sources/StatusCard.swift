import SwiftUI

struct StatusCard: View {
    let status: SourceStatus
    @State private var pulse: Bool = false
    @State private var expanded: Bool = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(status.tint.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: status.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(status.tint)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(status.tint)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                            .scaleEffect(pulse && isActive ? 1.35 : 1.0)
                            .opacity(pulse && isActive ? 0.4 : 1.0)
                            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                            .offset(x: 2, y: -2)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.headline)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                        if let detail = status.detail {
                            Text(detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)

                    if status.isReady {
                        Label("Ready", systemImage: "checkmark.seal.fill")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                if let info = status.discInfo {
                    DisclosureGroup(isExpanded: $expanded) {
                        Text(info.preview)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            .textSelection(.enabled)
                            .padding(.top, 6)
                    } label: {
                        Text("Disc details")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: status)
        .onAppear { pulse = true }
    }

    private var isActive: Bool {
        switch status {
        case .fileScanning, .netProbing, .netConnected: return true
        default: return false
        }
    }
}
