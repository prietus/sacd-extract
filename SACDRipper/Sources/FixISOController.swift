import Foundation
import AppKit

@MainActor
final class FixISOController: ObservableObject {
    @Published var inputPath: String = ""
    @Published var outputPath: String = ""
    @Published private(set) var progress: Double = 0
    @Published private(set) var status: String = ""
    @Published private(set) var isRunning: Bool = false

    private var currentTask: Task<Void, Never>?

    func pickInput() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select ISO with 2064-byte sectors"
        if panel.runModal() == .OK, let url = panel.url {
            inputPath = url.path
            if outputPath.isEmpty {
                outputPath = defaultOutput(for: url).path
            }
        }
    }

    func pickOutput() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (outputPath as NSString).lastPathComponent.isEmpty
            ? "fixed.iso"
            : (outputPath as NSString).lastPathComponent
        panel.message = "Choose output ISO file"
        if panel.runModal() == .OK, let url = panel.url {
            outputPath = url.path
        }
    }

    private func defaultOutput(for input: URL) -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(base).fixed.iso")
    }

    func start() {
        guard !isRunning else { return }
        guard !inputPath.isEmpty, !outputPath.isEmpty else {
            status = "Set input and output"
            return
        }
        if inputPath == outputPath {
            status = "Output must differ from input"
            return
        }

        let input = URL(fileURLWithPath: inputPath)
        let output = URL(fileURLWithPath: outputPath)
        isRunning = true
        progress = 0
        status = "Starting…"

        currentTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await Self.fixISO(input: input, output: output) { frac, note in
                    Task { @MainActor [weak self] in
                        self?.progress = frac
                        if let note { self?.status = note }
                    }
                }
                await MainActor.run { [weak self] in
                    self?.status = "Done"
                    self?.progress = 1
                    self?.isRunning = false
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.status = "Cancelled"
                    self?.isRunning = false
                    try? FileManager.default.removeItem(at: output)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.status = "Error: \(error.localizedDescription)"
                    self?.isRunning = false
                }
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
    }

    private static let sectorSize = 2064
    private static let headerSize = 12
    private static let dataSize = 2048
    private static let sectorsPerChunk = 512

    private static func fixISO(
        input: URL,
        output: URL,
        report: @escaping (Double, String?) -> Void
    ) async throws {
        let fm = FileManager.default
        let totalBytes = (try fm.attributesOfItem(atPath: input.path)[.size] as? NSNumber)?.uint64Value ?? 0
        if totalBytes == 0 { throw NSError(domain: "fixiso", code: 1, userInfo: [NSLocalizedDescriptionKey: "Input is empty"]) }
        if totalBytes % UInt64(sectorSize) != 0 {
            report(0, "Warning: size not multiple of \(sectorSize); trailing bytes ignored")
        }

        let inHandle = try FileHandle(forReadingFrom: input)
        defer { try? inHandle.close() }

        if fm.fileExists(atPath: output.path) {
            try fm.removeItem(at: output)
        }
        fm.createFile(atPath: output.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: output)
        defer { try? outHandle.close() }

        let chunkBytes = sectorSize * sectorsPerChunk
        var processed: UInt64 = 0

        while true {
            try Task.checkCancellation()
            let chunk = try inHandle.read(upToCount: chunkBytes) ?? Data()
            if chunk.isEmpty { break }
            let fullSectors = chunk.count / sectorSize
            if fullSectors == 0 { break }

            var outBuffer = Data(count: fullSectors * dataSize)
            chunk.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
                outBuffer.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
                    for i in 0..<fullSectors {
                        let srcOffset = i * sectorSize + headerSize
                        let dstOffset = i * dataSize
                        memcpy(dst.baseAddress!.advanced(by: dstOffset),
                               src.baseAddress!.advanced(by: srcOffset),
                               dataSize)
                    }
                }
            }
            try outHandle.write(contentsOf: outBuffer)
            processed += UInt64(fullSectors * sectorSize)

            let frac = Double(processed) / Double(totalBytes)
            let mbIn = Double(processed) / 1_048_576.0
            let mbTotal = Double(totalBytes) / 1_048_576.0
            report(frac, String(format: "%.1f / %.1f MiB", mbIn, mbTotal))

            if chunk.count < chunkBytes { break }
        }

        try outHandle.synchronize()
    }
}
