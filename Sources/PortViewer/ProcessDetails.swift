import Darwin
import Foundation

/// Extra information about a process that lsof doesn't give us (lsof truncates names).
struct ProcessDetails: Hashable, Sendable {
    /// Human friendly name, e.g. "Visual Studio Code" or "node".
    let displayName: String
    /// Full path of the executable, if readable.
    let executablePath: String?
    /// Outermost .app bundle containing the executable, if any.
    let appBundlePath: String?
    /// Short command line summary, e.g. "node server.js --port 3000".
    let commandLine: String?
    /// Recognized dev server, e.g. "Vite" or "Next.js".
    let framework: String?

    static func load(pid: Int32, fallbackName: String) -> ProcessDetails {
        let path = executablePath(pid: pid)
        let bundlePath = path.flatMap(outermostAppBundle(of:))
        let args = arguments(pid: pid)

        let name: String
        if let bundlePath {
            name = appName(bundlePath: bundlePath)
        } else if let path {
            name = (path as NSString).lastPathComponent
        } else {
            name = fallbackName
        }

        return ProcessDetails(
            displayName: name,
            executablePath: path,
            appBundlePath: bundlePath,
            commandLine: args.map(summarize),
            framework: args.flatMap(DevServerDetector.framework(for:))
        )
    }

    private static func executablePath(pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer[..<Int(length)], as: UTF8.self)
    }

    private static func outermostAppBundle(of path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private static func appName(bundlePath: String) -> String {
        let info = Bundle(path: bundlePath)?.infoDictionary
        if let name = info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String, !name.isEmpty {
            return name
        }
        return ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Reads argv via sysctl(KERN_PROCARGS2). Only works for processes we own.
    private static func arguments(pid: Int32) -> [String]? {
        var argMax: Int32 = 0
        var argMaxSize = MemoryLayout<Int32>.size
        var argMaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argMaxMib, 2, &argMax, &argMaxSize, nil, 0) == 0, argMax > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: Int(argMax))
        var size = buffer.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        // Layout: argc (Int32), exec path, NUL padding, argv[0..argc), env...
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size && buffer[index] != 0 { index += 1 }
        while index < size && buffer[index] == 0 { index += 1 }

        var args: [String] = []
        while args.count < argc && index < size {
            let start = index
            while index < size && buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args.isEmpty ? nil : args
    }

    /// Shortens paths to their last component so the line fits in the popover,
    /// e.g. "node node_modules/.bin/../vite/bin/vite.js" becomes "node vite.js".
    private static func summarize(_ args: [String]) -> String {
        args.map { arg in
            arg.contains("/") && !arg.hasPrefix("-") && !arg.contains("://")
                ? (arg as NSString).lastPathComponent
                : arg
        }
        .joined(separator: " ")
    }
}
