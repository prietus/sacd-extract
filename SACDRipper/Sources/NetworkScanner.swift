import Foundation
import Network
import Darwin

struct ScanHit: Identifiable, Hashable {
    let host: String
    let port: UInt16
    var id: String { "\(host):\(port)" }
}

enum NetworkScanner {
    static let defaultPort: UInt16 = 2002

    // Unique /24 prefixes ("192.168.1") for every up, non-loopback IPv4
    // interface whose address falls in a private range. Mac laptops
    // normally return one — the active Wi-Fi or Ethernet — but a VPN or
    // second NIC can add another, and we want to scan all of them.
    static func localIPv4Subnets() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for addr in localIPv4Addresses() {
            let parts = addr.split(separator: ".")
            guard parts.count == 4, let second = Int(parts[1]) else { continue }
            let isPrivate = addr.hasPrefix("192.168.")
                || addr.hasPrefix("10.")
                || (addr.hasPrefix("172.") && (16...31).contains(second))
            guard isPrivate else { continue }
            let base = parts.dropLast().joined(separator: ".")
            if seen.insert(base).inserted { result.append(base) }
        }
        return result
    }

    static func scan(
        subnets: [String],
        port: UInt16 = defaultPort,
        timeout: TimeInterval = 0.6,
        progress: @Sendable @escaping (Int, Int) -> Void = { _, _ in }
    ) async -> [ScanHit] {
        let hosts = subnets.flatMap { base in (1...254).map { "\(base).\($0)" } }
        let total = hosts.count
        guard total > 0 else { return [] }
        let counter = ScanCounter()

        return await withTaskGroup(of: ScanHit?.self) { group in
            for host in hosts {
                group.addTask {
                    let ok = await probeTCP(host: host, port: port, timeout: timeout)
                    let done = await counter.increment()
                    progress(done, total)
                    return ok ? ScanHit(host: host, port: port) : nil
                }
            }
            var hits: [ScanHit] = []
            for await hit in group {
                if let hit { hits.append(hit) }
            }
            hits.sort { compareIPv4($0.host, $1.host) }
            return hits
        }
    }

    private static func probeTCP(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                cont.resume(returning: false); return
            }
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let state = ScanProbeState(connection: conn, continuation: cont)
            conn.stateUpdateHandler = { nwState in
                switch nwState {
                case .ready: state.finish(true)
                case .failed, .cancelled: state.finish(false)
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                state.finish(false)
            }
        }
    }

    private static func compareIPv4(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for (x, y) in zip(pa, pb) where x != y { return x < y }
        return pa.count < pb.count
    }

    private static func localIPv4Addresses() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            if flags & IFF_UP == 0 { continue }
            if flags & IFF_LOOPBACK != 0 { continue }
            guard let sa = p.pointee.ifa_addr else { continue }
            if sa.pointee.sa_family != UInt8(AF_INET) { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                           &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        return result
    }
}

private actor ScanCounter {
    var n = 0
    func increment() -> Int { n += 1; return n }
}

private final class ScanProbeState: @unchecked Sendable {
    let connection: NWConnection
    private let cont: CheckedContinuation<Bool, Never>
    private let lock = NSLock()
    private var done = false

    init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
        self.connection = connection
        self.cont = continuation
    }

    func finish(_ v: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        connection.cancel()
        cont.resume(returning: v)
    }
}
