import Foundation

/// A process listening on a TCP port. IPv4/IPv6 sockets for the same pid+port are merged.
struct ListeningPort: Identifiable, Hashable, Sendable {
    let pid: Int32
    let port: UInt16
    let addresses: [String]
    let command: String
    let user: String
    let details: ProcessDetails

    var id: String { "\(pid):\(port)" }

    /// True when the socket is only reachable from this machine.
    var isLoopbackOnly: Bool {
        !addresses.isEmpty && addresses.allSatisfy { $0 == "127.0.0.1" || $0 == "::1" || $0 == "localhost" }
    }

    /// URL to open in the browser. Wildcard and loopback binds are reachable via localhost.
    var browserURL: URL {
        var host = "localhost"
        if !addresses.contains("*"), !isLoopbackOnly, let address = addresses.first {
            host = address.contains(":") ? "[\(address)]" : address
        }
        return URL(string: "http://\(host):\(port)")!
    }

    var bindingDescription: String {
        if addresses.contains("*") { return "All interfaces" }
        if isLoopbackOnly { return "Localhost only" }
        return addresses.joined(separator: ", ")
    }
}

enum PortScanner {
    enum ScanError: LocalizedError {
        case lsofFailed(String)
        var errorDescription: String? {
            switch self {
            case .lsofFailed(let message): return "lsof failed: \(message)"
            }
        }
    }

    /// Lists all TCP sockets in LISTEN state visible to the current user.
    static func scan() throws -> [ListeningPort] {
        let output = try runLsof()
        return parse(output)
    }

    private static func runLsof() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -n/-P: no DNS or service-name lookups, -F: machine readable fields.
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcLn"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // lsof exits with 1 when nothing matched, which is not an error for us.
        if process.terminationStatus != 0 && data.isEmpty {
            let message = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if message.isEmpty { return "" }
            throw ScanError.lsofFailed(message)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func parse(_ output: String) -> [ListeningPort] {
        struct Key: Hashable { let pid: Int32; let port: UInt16 }
        var addressesByKey: [Key: [String]] = [:]
        var commandByPid: [Int32: String] = [:]
        var userByPid: [Int32: String] = [:]

        var pid: Int32 = 0
        for line in output.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                pid = Int32(value) ?? 0
            case "c":
                commandByPid[pid] = value
            case "L":
                userByPid[pid] = value
            case "n":
                guard let (address, port) = splitEndpoint(value) else { continue }
                let key = Key(pid: pid, port: port)
                if !(addressesByKey[key]?.contains(address) ?? false) {
                    addressesByKey[key, default: []].append(address)
                }
            default:
                break
            }
        }

        var detailsCache: [Int32: ProcessDetails] = [:]
        return addressesByKey.map { key, addresses in
            let command = commandByPid[key.pid] ?? "?"
            let details = detailsCache[key.pid] ?? ProcessDetails.load(pid: key.pid, fallbackName: command)
            detailsCache[key.pid] = details
            return ListeningPort(
                pid: key.pid,
                port: key.port,
                addresses: addresses.sorted(),
                command: command,
                user: userByPid[key.pid] ?? "",
                details: details
            )
        }
        .sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    /// Splits "127.0.0.1:8080", "[::1]:8080" or "*:8080" into address and port.
    private static func splitEndpoint(_ endpoint: String) -> (String, UInt16)? {
        guard let colon = endpoint.lastIndex(of: ":"),
              let port = UInt16(endpoint[endpoint.index(after: colon)...]) else { return nil }
        var address = String(endpoint[..<colon])
        if address.hasPrefix("["), address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        return (address, port)
    }
}
