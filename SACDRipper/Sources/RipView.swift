import SwiftUI

struct RipView: View {
    @ObservedObject var controller: RipController
    @State private var optionsExpanded: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StatusCard(status: controller.sourceStatus)

                sourceCard
                outputCard

                HStack(alignment: .top, spacing: 16) {
                    formatCard
                    VStack(spacing: 16) {
                        channelsCard
                        tracksCard
                    }
                }

                optionsCard

                actionRow

                ProgressCard(controller: controller)
            }
            .padding(20)
        }
        .background(backgroundGradient.ignoresSafeArea())
    }

    private var sourceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Source", icon: "tray.and.arrow.down")
                HStack(spacing: 8) {
                    Image(systemName: sourceIcon)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    TextField("/path/to/album.iso  or  192.168.1.100:2002", text: $controller.inputPath)
                        .textFieldStyle(.plain)
                        .font(.body.monospaced())
                    if isProbingSource { ProgressView().controlSize(.small) }
                    Button {
                        controller.rescan()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Re-scan input")
                    Button {
                        controller.scanning
                            ? controller.cancelNetworkScan()
                            : controller.startNetworkScan()
                    } label: {
                        if controller.scanning {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Scanning…")
                            }
                        } else {
                            Label("Scan network", systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(controller.isRunning)
                    Button("Browse ISO…") { controller.pickInputISO() }
                        .buttonStyle(.bordered)
                        .disabled(controller.scanning)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                if controller.scanning {
                    scanProgressRow
                } else if !controller.scanResults.isEmpty {
                    scanResultsList
                } else if controller.lastScanFinished {
                    scanEmptyRow
                }

                Text("Accepts an ISO path or a `host:port` address of a Sony player speaking the sacd-ripper protocol (PS3 or compatible BD player, default port 2002). Scan network checks the local /24 on port 2002 in parallel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scanProgressRow: some View {
        let prog = controller.scanProgress
        let frac = prog.total > 0 ? Double(prog.done) / Double(prog.total) : 0
        return HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Probing port 2002 on the local subnet…")
                    .font(.caption.weight(.medium))
                ProgressView(value: frac)
                    .progressViewStyle(.linear)
            }
            Text("\(prog.done) / \(prog.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var scanResultsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Found \(controller.scanResults.count) device\(controller.scanResults.count == 1 ? "" : "s")",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                Button {
                    controller.dismissScanResults()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            ForEach(controller.scanResults) { hit in
                Button {
                    controller.applyScanHit(hit)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "network")
                            .foregroundStyle(.tint)
                        Text("\(hit.host):\(hit.port)")
                            .font(.body.monospaced())
                        Spacer()
                        Text("Use")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.08))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var scanEmptyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.secondary)
            Text("No device answering on port 2002 was found on the local subnet. Make sure the player is on and the sacd-ripper service is enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                controller.dismissScanResults()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private var isProbingSource: Bool {
        switch controller.sourceStatus {
        case .netProbing, .fileScanning, .netConnected: return true
        default: return false
        }
    }

    private var outputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Output directory", icon: "folder")
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.tint)
                        .frame(width: 18)
                    TextField("", text: $controller.outputDir)
                        .textFieldStyle(.plain)
                        .font(.body.monospaced())
                    Button("Browse…") { controller.pickOutputDirectory() }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var formatCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Format", icon: "square.grid.2x2")
                VStack(spacing: 6) {
                    ForEach(RipFormat.allCases) { f in
                        FormatRow(
                            format: f,
                            selected: controller.format == f
                        ) { controller.format = f }
                    }
                }
            }
        }
        .frame(minWidth: 240)
    }

    private var channelsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Channels", icon: "hifispeaker")
                Picker("", selection: $controller.channels) {
                    ForEach(RipChannels.allCases) { c in
                        Label(c.rawValue, systemImage: c.icon).tag(c)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var tracksCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Tracks", icon: "list.number")
                TextField("1,3,5 (empty = all)", text: $controller.trackSelection)
                    .textFieldStyle(.plain)
                    .font(.body.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var optionsCard: some View {
        Card {
            DisclosureGroup(isExpanded: $optionsExpanded) {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                    GridRow {
                        Toggle("Convert DST → DSD", isOn: $controller.convertDSTtoDSD)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Export CUE sheet", isOn: $controller.exportCUE)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Include pauses", isOn: $controller.includePauses)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow {
                        Toggle("DSF no-pad", isOn: $controller.dsfNoPad)
                            .disabled(controller.format != .dsf && controller.format != .isoPlusDSF)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Artist in folder", isOn: $controller.artistInFolder)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Performer in filename", isOn: $controller.performerInFile)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow {
                        Toggle("Print only (no rip)", isOn: $controller.printOnly)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Concatenate selected", isOn: $controller.concatenate)
                            .disabled(controller.trackSelection.trimmingCharacters(in: .whitespaces).isEmpty)
                            .help("Merge selected tracks (-t) into a single file. Needs Tracks set.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.top, 10)
            } label: {
                HStack(spacing: 8) {
                    SectionHeader(title: "Options", icon: "slider.horizontal.3")
                    if enabledOptionsCount > 0 {
                        Text("\(enabledOptionsCount) active")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                }
            }
            .onChange(of: controller.isRunning) { running in
                if running { optionsExpanded = false }
            }
        }
    }

    private var enabledOptionsCount: Int {
        [controller.convertDSTtoDSD, controller.exportCUE, controller.includePauses,
         controller.dsfNoPad, controller.artistInFolder, controller.performerInFile,
         controller.printOnly, controller.concatenate].filter { $0 }.count
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                controller.isRunning ? controller.stop() : controller.start()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: controller.isRunning ? "stop.fill" : "play.fill")
                        .font(.title3)
                    Text(controller.isRunning ? "Stop" : "Start Rip")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 160)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(controller.isRunning ? .red : .accentColor)
            .keyboardShortcut(.return)
            .disabled(controller.inputPath.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: controller.isRunning)
    }

    private var sourceIcon: String {
        switch controller.sourceStatus {
        case .netReady, .netConnected, .netProbing, .netUnreachable, .netNoDisc: return "network"
        case .fileReady, .fileScanning, .fileMissing, .fileNoDisc: return "doc"
        case .invalid: return "exclamationmark.triangle"
        case .idle: return "arrow.down.doc"
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.06),
                Color.clear,
                Color.accentColor.opacity(0.03)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct FormatRow: View {
    let format: RipFormat
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Image(systemName: format.icon)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 18)
                Text(format.rawValue)
                    .fontWeight(selected ? .semibold : .regular)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
    }
}

struct ProgressCard: View {
    @ObservedObject var controller: RipController
    @State private var showDetails: Bool = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: controller.phase.icon)
                        .font(.title2)
                        .foregroundStyle(controller.phase.tint)
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(controller.phase.label)
                            .font(.headline)
                        if let sub = phaseSubtitle {
                            Text(sub)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    elapsedLabel
                }

                ProgressView(value: clampedProgress)
                    .progressViewStyle(.linear)
                    .tint(progressTint)
                    .animation(.linear(duration: 0.2), value: clampedProgress)

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(Int((clampedProgress * 100).rounded()))%")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(progressTint)

                    if let cur = controller.currentTrack, let total = controller.totalTracks {
                        Divider().frame(height: 18)
                        Label("Track \(cur) / \(total)", systemImage: "number")
                            .labelStyle(.titleAndIcon)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if controller.totalPercent != nil, controller.totalTracks != nil {
                        Divider().frame(height: 18)
                        Label("File \(controller.filePercent)%", systemImage: "waveform")
                            .labelStyle(.titleAndIcon)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                if let file = controller.currentFile {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Text(file)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if case .failed(let msg, let code) = controller.phase {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Exit code \(code)", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.red)
                        Text(msg)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                if !controller.tail.isEmpty {
                    DisclosureGroup(isExpanded: $showDetails) {
                        ScrollView {
                            Text(controller.tail.suffix(40).joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 4)
                    } label: {
                        Label("Raw messages (\(controller.tail.count))", systemImage: "text.alignleft")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: controller.phase)
    }

    private var clampedProgress: Double {
        min(1.0, max(0.0, controller.displayProgress))
    }

    private var progressTint: Color {
        switch controller.phase {
        case .done: return .green
        case .failed: return .red
        case .cancelled: return .orange
        default: return .accentColor
        }
    }

    private var phaseSubtitle: String? {
        switch controller.phase {
        case .done(let elapsed):
            if let elapsed { return "Finished in \(elapsed)" }
            return "Finished"
        case .failed: return "Check details below"
        case .cancelled: return "Stopped by user"
        case .ripping:
            if controller.totalPercent != nil { return "Concurrent ISO + track output" }
            return nil
        case .starting: return "Waking the ripper…"
        case .idle:
            return "Configure source and press Start"
        }
    }

    @ViewBuilder
    private var elapsedLabel: some View {
        if case .done(let e) = controller.phase, let e {
            Label(e, systemImage: "clock.badge.checkmark")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
        } else if controller.phase.isActive, let start = controller.startDate {
            TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                Label(Self.formatElapsed(ctx.date.timeIntervalSince(start)), systemImage: "clock")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func formatElapsed(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        let h = t / 3600, m = (t / 60) % 60, s = t % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
