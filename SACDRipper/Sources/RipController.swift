import Foundation
import AppKit
import Network
import SwiftUI
import Combine

enum RipFormat: String, CaseIterable, Identifiable {
    case dsf = "DSF"
    case dsdiff = "DSDIFF"
    case dsdiffEM = "DSDIFF · Edit Master"
    case iso = "ISO"
    case isoPlusDSF = "ISO + DSF"
    case isoPlusDSDIFF = "ISO + DSDIFF"

    var id: String { rawValue }

    var flags: [String] {
        switch self {
        case .dsf: return ["-s"]
        case .dsdiff: return ["-p"]
        case .dsdiffEM: return ["-e"]
        case .iso: return ["-I"]
        case .isoPlusDSF: return ["-s", "-w"]
        case .isoPlusDSDIFF: return ["-p", "-w"]
        }
    }

    var icon: String {
        switch self {
        case .dsf: return "waveform"
        case .dsdiff: return "waveform.path"
        case .dsdiffEM: return "waveform.path.ecg"
        case .iso: return "opticaldisc"
        case .isoPlusDSF, .isoPlusDSDIFF: return "square.stack.3d.up"
        }
    }
}

enum RipChannels: String, CaseIterable, Identifiable {
    case stereo = "2 ch"
    case multichannel = "Multichannel"
    var id: String { rawValue }
    var flag: String { self == .stereo ? "-2" : "-m" }
    var icon: String { self == .stereo ? "speaker.wave.2" : "hifispeaker.2" }
}

enum InputKind: Equatable {
    case empty
    case file(URL)
    case network(host: String, port: UInt16)
    case invalid
}

struct DiscInfo: Equatable {
    let raw: String

    var headline: String {
        let first = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("Enhanced by") && !$0.hasPrefix("sacd_extract") })
        return first ?? "SACD detected"
    }

    var trackCount: Int? {
        let pattern = try? NSRegularExpression(pattern: #"(?im)^\s*Track\s+\d+"#)
        guard let pattern else { return nil }
        let range = NSRange(raw.startIndex..., in: raw)
        let n = pattern.numberOfMatches(in: raw, range: range)
        return n > 0 ? n : nil
    }

    var preview: String {
        raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(18)
            .joined(separator: "\n")
    }
}

enum SourceStatus: Equatable {
    case idle
    case invalid(String)
    case fileMissing
    case fileReady(URL, DiscInfo?)
    case fileScanning(URL)
    case netProbing(String)
    case netUnreachable(String)
    case netConnected(String)
    case netReady(String, DiscInfo?)

    var headline: String {
        switch self {
        case .idle: return "No source selected"
        case .invalid(let msg): return "Invalid input · \(msg)"
        case .fileMissing: return "File not found"
        case .fileScanning(let url): return "Scanning \(url.lastPathComponent)…"
        case .fileReady(let url, let info):
            if let info { return info.headline }
            return url.lastPathComponent
        case .netProbing(let addr): return "Connecting to \(addr)…"
        case .netUnreachable(let addr): return "Cannot reach \(addr)"
        case .netConnected(let addr): return "Connected to \(addr) · looking for disc…"
        case .netReady(_, let info):
            if let info { return info.headline }
            return "SACD detected"
        }
    }

    var detail: String? {
        switch self {
        case .fileReady(let url, let info):
            if let info, let n = info.trackCount { return "\(url.lastPathComponent) · \(n) tracks · ready to rip" }
            return url.path
        case .netReady(let addr, let info):
            if let info, let n = info.trackCount { return "\(addr) · \(n) tracks · ready to rip" }
            return "\(addr) · ready to rip"
        case .netConnected(let addr): return addr
        case .fileScanning(let url): return url.path
        default: return nil
        }
    }

    var discInfo: DiscInfo? {
        switch self {
        case .fileReady(_, let info): return info
        case .netReady(_, let info): return info
        default: return nil
        }
    }

    var tint: Color {
        switch self {
        case .idle: return .secondary
        case .invalid, .fileMissing, .netUnreachable: return .red
        case .fileScanning, .netProbing, .netConnected: return .yellow
        case .fileReady, .netReady: return .green
        }
    }

    var icon: String {
        switch self {
        case .idle: return "tray"
        case .invalid, .fileMissing: return "exclamationmark.triangle"
        case .netUnreachable: return "wifi.exclamationmark"
        case .fileScanning: return "doc.text.magnifyingglass"
        case .netProbing: return "antenna.radiowaves.left.and.right"
        case .netConnected: return "network"
        case .fileReady: return "opticaldisc"
        case .netReady: return "opticaldisc.fill"
        }
    }

    var isReady: Bool {
        switch self {
        case .fileReady, .netReady: return true
        default: return false
        }
    }
}

enum RipPhase: Equatable {
    case idle
    case starting
    case ripping
    case done(elapsed: String?)
    case failed(message: String, exitCode: Int32)
    case cancelled

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .starting: return "Starting…"
        case .ripping: return "Ripping"
        case .done: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var tint: Color {
        switch self {
        case .idle: return .secondary
        case .starting, .ripping: return .accentColor
        case .done: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    var icon: String {
        switch self {
        case .idle: return "pause.circle"
        case .starting: return "hourglass"
        case .ripping: return "waveform"
        case .done: return "checkmark.seal.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    var isActive: Bool {
        switch self {
        case .starting, .ripping: return true
        default: return false
        }
    }
}

// MARK: - Thread-safe continuation helpers

private final class TCPProbeState: @unchecked Sendable {
    let connection: NWConnection
    private let continuation: CheckedContinuation<Bool, Never>
    private let lock = NSLock()
    private var done = false

    init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        connection.cancel()
        continuation.resume(returning: value)
    }
}

private final class ProbeDiscState: @unchecked Sendable {
    private let continuation: CheckedContinuation<DiscInfo?, Never>
    private let lock = NSLock()
    private var done = false

    init(_ continuation: CheckedContinuation<DiscInfo?, Never>) {
        self.continuation = continuation
    }

    func finish(_ v: DiscInfo?) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(returning: v)
    }
}

@MainActor
final class RipController: ObservableObject {
    // MARK: User inputs
    @Published var inputPath: String = "" {
        didSet { if inputPath != oldValue && !isRunning { scheduleProbe() } }
    }
    @Published var outputDir: String = (NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first ?? NSHomeDirectory())
    @Published var format: RipFormat = .dsf
    @Published var channels: RipChannels = .stereo
    @Published var convertDSTtoDSD: Bool = true
    @Published var exportCUE: Bool = false
    @Published var includePauses: Bool = false
    @Published var dsfNoPad: Bool = false
    @Published var artistInFolder: Bool = false
    @Published var performerInFile: Bool = false
    @Published var printOnly: Bool = false
    @Published var concatenate: Bool = false
    @Published var trackSelection: String = ""

    // MARK: Derived state
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var sourceStatus: SourceStatus = .idle

    @Published private(set) var phase: RipPhase = .idle
    @Published private(set) var filePercent: Int = 0
    @Published private(set) var totalPercent: Int? = nil
    @Published private(set) var currentTrack: Int? = nil
    @Published private(set) var totalTracks: Int? = nil
    @Published private(set) var currentFile: String? = nil
    @Published private(set) var startDate: Date? = nil
    @Published private(set) var tail: [String] = []

    // MARK: Network scan
    @Published private(set) var scanning: Bool = false
    @Published private(set) var scanProgress: (done: Int, total: Int) = (0, 0)
    @Published var scanResults: [ScanHit] = []
    @Published private(set) var lastScanFinished: Bool = false
    private var scanTask: Task<Void, Never>?

    var displayProgress: Double {
        if let total = totalPercent { return Double(total) / 100.0 }
        if let cur = currentTrack, let total = totalTracks, total > 0 {
            return min(1.0, (Double(cur - 1) + Double(filePercent) / 100.0) / Double(total))
        }
        return Double(filePercent) / 100.0
    }

    // MARK: Internals
    private var process: Process?
    private var probeTask: Task<Void, Never>?
    private weak var activeProbeProcess: Process?
    private var readBuffer: String = ""

    private static let reCompleted = try! NSRegularExpression(pattern: #"Completed:\s*(\d+)%"#)
    private static let reTotal = try! NSRegularExpression(pattern: #"Total:\s*(\d+)%"#)
    private static let reProcessing = try! NSRegularExpression(pattern: #"Processing\s+\[([^\]]+)\]\s+\((\d+)/(\d+)\)"#)
    private static let reElapsed = try! NSRegularExpression(pattern: #"\[elapsed:\s*([^\]]+)\]"#)

    var binaryPath: String? {
        Bundle.main.path(forResource: "sacd_extract", ofType: nil)
    }

    // MARK: - Browsing

    func pickInputISO() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select an SACD ISO image"
        if panel.runModal() == .OK, let url = panel.url {
            inputPath = url.path
        }
    }

    func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Select output directory"
        if panel.runModal() == .OK, let url = panel.url {
            outputDir = url.path
        }
    }

    func rescan() {
        guard !isRunning else { return }
        scheduleProbe(delayMs: 0)
    }

    // MARK: - Network discovery

    func startNetworkScan() {
        guard !scanning, !isRunning else { return }
        let subnets = NetworkScanner.localIPv4Subnets()
        guard !subnets.isEmpty else {
            scanResults = []
            lastScanFinished = true
            return
        }
        scanning = true
        lastScanFinished = false
        scanResults = []
        scanProgress = (0, subnets.count * 254)

        let progressHandler: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            Task { @MainActor in
                self?.scanProgress = (done, total)
            }
        }
        scanTask = Task { [weak self] in
            let hits = await NetworkScanner.scan(subnets: subnets, progress: progressHandler)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scanning = false
                self.lastScanFinished = true
                self.scanResults = hits
                // Auto-populate when there's exactly one candidate; the
                // existing probe pipeline will then validate it's a real
                // sacd-ripper server by running `sacd_extract -P`.
                if hits.count == 1 {
                    self.applyScanHit(hits[0])
                }
            }
        }
    }

    func cancelNetworkScan() {
        scanTask?.cancel()
        scanTask = nil
        scanning = false
    }

    func applyScanHit(_ hit: ScanHit) {
        inputPath = "\(hit.host):\(hit.port)"
        scanResults = []
    }

    func dismissScanResults() {
        scanResults = []
        lastScanFinished = false
    }

    private func cancelActiveProbe() {
        probeTask?.cancel()
        probeTask = nil
        if let p = activeProbeProcess, p.isRunning {
            p.terminate()
        }
        activeProbeProcess = nil
    }

    // MARK: - Input classification

    private func classify(_ raw: String) -> InputKind {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return .empty }
        if s.hasPrefix("/") || s.hasPrefix("~") {
            let expanded = (s as NSString).expandingTildeInPath
            return .file(URL(fileURLWithPath: expanded))
        }
        if let colon = s.lastIndex(of: ":"),
           let port = UInt16(s[s.index(after: colon)...]) {
            let host = String(s[..<colon])
            if !host.isEmpty { return .network(host: host, port: port) }
        }
        if FileManager.default.fileExists(atPath: s) { return .file(URL(fileURLWithPath: s)) }
        return .invalid
    }

    // MARK: - Probing

    private func scheduleProbe(delayMs: UInt64 = 400) {
        probeTask?.cancel()
        let snapshot = inputPath
        probeTask = Task { [weak self] in
            if delayMs > 0 { try? await Task.sleep(nanoseconds: delayMs * 1_000_000) }
            guard !Task.isCancelled else { return }
            await self?.runProbe(for: snapshot)
        }
    }

    private func runProbe(for raw: String) async {
        let kind = classify(raw)
        switch kind {
        case .empty:
            sourceStatus = .idle
        case .invalid:
            sourceStatus = .invalid("use /path/to.iso or host:port")
        case .file(let url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                sourceStatus = .fileMissing
                return
            }
            sourceStatus = .fileScanning(url)
            let info = await probeDisc(args: ["-P", "-i", url.path])
            if Task.isCancelled { return }
            sourceStatus = .fileReady(url, info)
        case .network(let host, let port):
            let addr = "\(host):\(port)"
            sourceStatus = .netProbing(addr)
            let reachable = await tcpProbe(host: host, port: port, timeout: 2.5)
            if Task.isCancelled { return }
            if !reachable { sourceStatus = .netUnreachable(addr); return }
            sourceStatus = .netConnected(addr)
            let info = await probeDisc(args: ["-P", "-i", addr], timeoutSec: 12)
            if Task.isCancelled { return }
            sourceStatus = .netReady(addr, info)
        }
    }

    private func tcpProbe(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let state = TCPProbeState(connection: conn, continuation: cont)
            conn.stateUpdateHandler = { nwState in
                switch nwState {
                case .ready: state.finish(true)
                case .failed, .cancelled: state.finish(false)
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { state.finish(false) }
        }
    }

    private func probeDisc(args: [String], timeoutSec: TimeInterval = 10) async -> DiscInfo? {
        guard let binary = binaryPath else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary)

        return await withCheckedContinuation { (cont: CheckedContinuation<DiscInfo?, Never>) in
            let state = ProbeDiscState(cont)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: binary)
            proc.arguments = args
            let out = Pipe()
            let err = Pipe()
            proc.standardOutput = out
            proc.standardError = err

            proc.terminationHandler = { _ in
                let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
                let text = String(data: data, encoding: .utf8) ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                state.finish(trimmed.isEmpty ? nil : DiscInfo(raw: trimmed))
            }

            do {
                try proc.run()
            } catch {
                state.finish(nil)
                return
            }
            Task { @MainActor [weak self] in self?.activeProbeProcess = proc }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSec) {
                if proc.isRunning { proc.terminate() }
            }
        }
    }

    // MARK: - Rip execution

    private func buildArgs() -> [String] {
        var args: [String] = []
        args.append(channels.flag)
        args.append(contentsOf: format.flags)
        if convertDSTtoDSD { args.append("-c") }
        if exportCUE { args.append("-C") }
        if includePauses { args.append("-b") }
        if dsfNoPad && (format == .dsf || format == .isoPlusDSF) { args.append("-z") }
        if artistInFolder { args.append("-A") }
        if performerInFile { args.append("-a") }
        if printOnly { args.append("-P") }
        let tracks = trackSelection.trimmingCharacters(in: .whitespaces)
        if !tracks.isEmpty {
            args.append("-t"); args.append(tracks)
            if concatenate { args.append("-k") }
        }
        if !outputDir.isEmpty {
            args.append("-o"); args.append(outputDir)
            args.append("-y"); args.append(outputDir)
        }
        args.append("-i"); args.append(inputPath.trimmingCharacters(in: .whitespaces))
        return args
    }

    func start() {
        guard !isRunning else { return }
        guard let binary = binaryPath else {
            phase = .failed(message: "sacd_extract binary not found in app bundle", exitCode: -1)
            return
        }
        guard !inputPath.trimmingCharacters(in: .whitespaces).isEmpty else {
            phase = .failed(message: "Input not set", exitCode: -1)
            return
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary)
        if !outputDir.isEmpty {
            try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }
        cancelActiveProbe()
        resetRipState()
        phase = .starting
        startDate = Date()

        let args = buildArgs()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let str = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in self?.consume(str) }
            }
        }

        proc.terminationHandler = { [weak self] p in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in self?.finishRun(exitCode: p.terminationStatus) }
        }

        do {
            try proc.run()
            process = proc
            isRunning = true
        } catch {
            phase = .failed(message: error.localizedDescription, exitCode: -1)
        }
    }

    func stop() {
        process?.interrupt()
    }

    func clearTail() { tail = [] }

    private func resetRipState() {
        readBuffer = ""
        filePercent = 0
        totalPercent = nil
        currentTrack = nil
        totalTracks = nil
        currentFile = nil
        startDate = nil
        tail = []
    }

    private func finishRun(exitCode: Int32) {
        isRunning = false
        process = nil

        switch exitCode {
        case 0:
            let elapsed = extractElapsed(from: tail)
            filePercent = 100
            totalPercent = 100
            phase = .done(elapsed: elapsed)
        case 2, 15, -15: // SIGINT / SIGTERM
            phase = .cancelled
        default:
            let recent = tail.suffix(6).joined(separator: "\n")
            let msg = recent.isEmpty ? "sacd_extract exited with code \(exitCode)" : recent
            phase = .failed(message: msg, exitCode: exitCode)
        }
    }

    private func extractElapsed(from lines: [String]) -> String? {
        for line in lines.reversed() {
            let range = NSRange(line.startIndex..., in: line)
            if let m = Self.reElapsed.firstMatch(in: line, range: range),
               let r = Range(m.range(at: 1), in: line) {
                return String(line[r]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // Consume stdout chunks, split on \r or \n, forward to processLine
    private func consume(_ chunk: String) {
        readBuffer.append(chunk)
        while let idx = readBuffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let line = String(readBuffer[readBuffer.startIndex..<idx])
            readBuffer = String(readBuffer[readBuffer.index(after: idx)...])
            if !line.isEmpty { processLine(line) }
        }
        if readBuffer.count > 4096 {
            processLine(readBuffer)
            readBuffer = ""
        }
    }

    private func processLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        let range = NSRange(line.startIndex..., in: line)

        var matchedProgress = false

        if let m = Self.reProcessing.firstMatch(in: line, range: range),
           let r1 = Range(m.range(at: 1), in: line),
           let r2 = Range(m.range(at: 2), in: line),
           let r3 = Range(m.range(at: 3), in: line),
           let cur = Int(line[r2]),
           let total = Int(line[r3]) {
            currentFile = String(line[r1])
            currentTrack = cur
            totalTracks = total
            filePercent = 0
            if phase != .ripping { phase = .ripping }
            matchedProgress = true
        }

        if let m = Self.reCompleted.firstMatch(in: line, range: range),
           let r = Range(m.range(at: 1), in: line),
           let pct = Int(line[r]) {
            filePercent = min(100, max(0, pct))
            if phase != .ripping { phase = .ripping }
            matchedProgress = true
        }

        if let m = Self.reTotal.firstMatch(in: line, range: range),
           let r = Range(m.range(at: 1), in: line),
           let pct = Int(line[r]) {
            totalPercent = min(100, max(0, pct))
            matchedProgress = true
        }

        if !matchedProgress {
            appendTail(line)
        }
    }

    private func appendTail(_ line: String) {
        tail.append(line)
        if tail.count > 80 {
            tail.removeFirst(tail.count - 60)
        }
    }
}
