import AppKit
import Observation

@MainActor
@Observable
final class PortStore {
    private(set) var ports: [ListeningPort] = []
    private(set) var lastUpdated: Date?
    private(set) var isScanning = false
    var errorMessage: String?
    var searchText = ""

    private var timer: Timer?
    /// HTTP probe results per port id, so each listener is only probed once.
    private var probeResults: [String: Bool] = [:]
    private var probing: Set<String> = []

    /// Whether the port looks like a website: a known dev server or a port that answers with HTML.
    func isWebsite(_ port: ListeningPort) -> Bool {
        port.details.framework != nil || probeResults[port.id] == true
    }

    func openInBrowser(_ port: ListeningPort) {
        NSWorkspace.shared.open(port.browserURL)
    }

    var filteredPorts: [ListeningPort] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return ports }
        return ports.filter { port in
            String(port.port).contains(query)
                || String(port.pid) == query
                || port.details.displayName.lowercased().contains(query)
                || port.command.lowercased().contains(query)
                || (port.details.framework?.lowercased().contains(query) ?? false)
                || (port.details.commandLine?.lowercased().contains(query) ?? false)
        }
    }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try PortScanner.scan() }
            }.value
            switch result {
            case .success(let ports):
                if ports != self.ports { self.ports = ports }
                self.probeNewPorts()
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
            self.lastUpdated = Date()
            self.isScanning = false
        }
    }

    private func probeNewPorts() {
        let liveIds = Set(ports.map(\.id))
        probeResults = probeResults.filter { liveIds.contains($0.key) }

        for port in ports where probeResults[port.id] == nil && !probing.contains(port.id) {
            probing.insert(port.id)
            let url = port.browserURL
            Task {
                let isWebsite = await WebProbe.servesHTML(url)
                self.probing.remove(port.id)
                self.probeResults[port.id] = isWebsite
            }
        }
    }

    enum Signal {
        case terminate, forceKill
        var value: Int32 { self == .terminate ? SIGTERM : SIGKILL }
        var flag: String { self == .terminate ? "-TERM" : "-KILL" }
    }

    func kill(_ port: ListeningPort, signal: Signal = .terminate) {
        errorMessage = nil
        if Darwin.kill(port.pid, signal.value) == 0 {
            // Optimistically drop every row owned by that pid, then confirm with a rescan.
            ports.removeAll { $0.pid == port.pid }
            scheduleRescan()
            return
        }

        switch errno {
        case EPERM:
            killWithAdministratorPrivileges(port, signal: signal)
        case ESRCH:
            refresh()
        default:
            errorMessage = "Could not stop \(port.details.displayName): \(String(cString: strerror(errno)))"
        }
    }

    /// Processes owned by root or other users need an authenticated kill.
    private func killWithAdministratorPrivileges(_ port: ListeningPort, signal: Signal) {
        let script = "do shell script \"/bin/kill \(signal.flag) \(port.pid)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) != -128 {
            errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Could not stop \(port.details.displayName)."
        }
        scheduleRescan()
    }

    private func scheduleRescan() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            refresh()
        }
    }
}
