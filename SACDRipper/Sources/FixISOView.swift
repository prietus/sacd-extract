import SwiftUI

struct FixISOView: View {
    @ObservedObject var controller: FixISOController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "bandage.fill")
                                .font(.title2)
                                .foregroundStyle(.tint)
                                .symbolRenderingMode(.hierarchical)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fix ISO · strip 2064-byte sectors")
                                    .font(.headline)
                                Text("Rebuilds a clean 2048 bytes-per-sector ISO by removing the 12-byte header and 4-byte tail from each sector.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Input ISO", icon: "doc")
                        HStack {
                            Image(systemName: "doc.fill").foregroundStyle(.secondary)
                            TextField("Faulty ISO file", text: $controller.inputPath)
                                .textFieldStyle(.plain)
                                .font(.body.monospaced())
                            Button("Browse…") { controller.pickInput() }
                                .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Output ISO", icon: "square.and.arrow.down")
                        HStack {
                            Image(systemName: "arrow.down.doc.fill").foregroundStyle(.tint)
                            TextField("Fixed ISO file", text: $controller.outputPath)
                                .textFieldStyle(.plain)
                                .font(.body.monospaced())
                            Button("Browse…") { controller.pickOutput() }
                                .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Button {
                                controller.isRunning ? controller.cancel() : controller.start()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: controller.isRunning ? "stop.circle.fill" : "wand.and.stars")
                                        .font(.title3)
                                    Text(controller.isRunning ? "Cancel" : "Fix ISO")
                                        .fontWeight(.semibold)
                                }
                                .frame(minWidth: 140)
                            }
                            .controlSize(.large)
                            .buttonStyle(.borderedProminent)
                            .tint(controller.isRunning ? .red : .accentColor)
                            .keyboardShortcut(.return)

                            if controller.isRunning || controller.progress > 0 {
                                ProgressView(value: controller.progress)
                                    .progressViewStyle(.linear)
                            }
                        }

                        if !controller.status.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: controller.progress >= 1.0 ? "checkmark.circle.fill" : "info.circle")
                                    .foregroundStyle(controller.progress >= 1.0 ? .green : .secondary)
                                Text(controller.status)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .background(backgroundGradient.ignoresSafeArea())
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.06), Color.clear, Color.accentColor.opacity(0.03)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
