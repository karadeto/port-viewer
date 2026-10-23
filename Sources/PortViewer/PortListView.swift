import ServiceManagement
import SwiftUI

struct PortListView: View {
    @Bindable var store: PortStore

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 380)
        .onAppear { store.refresh() }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Open Ports")
                .font(.system(size: 15, weight: .semibold))
            Text("\(store.ports.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    // Scope the animation to the rotation only, so the icon doesn't slide
                    // into place while the popover lays out on first open.
                    .animation(store.isScanning ? .linear(duration: 0.6) : nil) {
                        $0.rotationEffect(.degrees(store.isScanning ? 360 : 0))
                    }
            }
            .buttonStyle(IconButtonStyle())
            .help("Refresh")
            .keyboardShortcut("r")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter by port, app or PID", text: $store.searchText)
                .textFieldStyle(.plain)
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        let ports = store.filteredPorts
        if let error = store.errorMessage {
            ErrorBanner(message: error) { store.errorMessage = nil }
        }
        // Size from the unfiltered list so the popover keeps its height while filtering.
        let listHeight = min(CGFloat(store.ports.count) * 52 + 12, 420)
        if ports.isEmpty {
            EmptyStateView(isFiltering: !store.searchText.isEmpty)
                .frame(height: max(listHeight, 180))
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(ports) { port in
                        PortRow(
                            port: port,
                            isWebsite: store.isWebsite(port),
                            onOpen: { store.openInBrowser(port) },
                            onKill: { signal in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    store.kill(port, signal: signal)
                                }
                            }
                        )
                    }
                }
                .padding(6)
            }
            .frame(height: listHeight, alignment: .top)
        }
    }

    private var footer: some View {
        HStack {
            if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            SettingsMenu()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Row

private struct PortRow: View {
    let port: ListeningPort
    let isWebsite: Bool
    let onOpen: () -> Void
    let onKill: (PortStore.Signal) -> Void

    @State private var isHovering = false
    @State private var isConfirming = false

    var body: some View {
        HStack(spacing: 10) {
            ProcessIcon(details: port.details)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(port.details.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let framework = port.details.framework {
                        FrameworkTag(name: framework)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .help(port.details.executablePath ?? port.command)

            Spacer(minLength: 6)

            if isWebsite {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(IconButtonStyle(hoverTint: .accentColor))
                .help("Open \(port.browserURL.absoluteString) in browser")
                .transition(.opacity)
            }

            PortBadge(port: port)

            killButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if !hovering { isConfirming = false }
        }
        .contextMenu { contextMenu }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var subtitle: String {
        var parts = ["PID \(port.pid)"]
        if let commandLine = port.details.commandLine, commandLine != port.details.displayName {
            parts.append(commandLine)
        } else if port.command != port.details.displayName {
            parts.append(port.command)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var killButton: some View {
        if isConfirming {
            Button("Kill") {
                onKill(NSEvent.modifierFlags.contains(.option) ? .forceKill : .terminate)
                isConfirming = false
            }
            .buttonStyle(KillConfirmButtonStyle())
            .help("Click to stop the process. Hold ⌥ to force kill.")
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            Button {
                withAnimation(.snappy(duration: 0.18)) { isConfirming = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(IconButtonStyle(hoverTint: .red))
            .opacity(isHovering ? 1 : 0.55)
            .help("Stop \(port.details.displayName)")
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open \(port.browserURL.absoluteString) in Browser", action: onOpen)
        Divider()
        Button("Copy Port") { copy(String(port.port)) }
        Button("Copy PID") { copy(String(port.pid)) }
        if let path = port.details.executablePath {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: port.details.appBundlePath ?? path)])
            }
        }
        Divider()
        Button("Terminate Process") { onKill(.terminate) }
        Button("Force Kill Process") { onKill(.forceKill) }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private struct FrameworkTag: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            .fixedSize()
    }
}

private struct PortBadge: View {
    let port: ListeningPort

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: port.isLoopbackOnly ? "lock.fill" : "globe")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: ":\(port.port)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(.primary)
        .help("\(port.bindingDescription) (\(port.addresses.joined(separator: ", ")))")
    }
}

private struct ProcessIcon: View {
    let details: ProcessDetails

    var body: some View {
        Image(nsImage: IconCache.icon(for: details))
            .resizable()
            .interpolation(.high)
            .frame(width: 26, height: 26)
    }
}

@MainActor
private enum IconCache {
    private static var cache: [String: NSImage] = [:]
    private static let terminalIcon: NSImage = {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .unixExecutable)
    }()

    static func icon(for details: ProcessDetails) -> NSImage {
        guard let bundle = details.appBundlePath else { return terminalIcon }
        if let cached = cache[bundle] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: bundle)
        cache[bundle] = icon
        return icon
    }
}

// MARK: - Supporting views

private struct EmptyStateView: View {
    let isFiltering: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isFiltering ? "magnifyingglass" : "checkmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(isFiltering ? "No matching ports" : "No open ports")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if !isFiltering {
                Text("Nothing is listening on a TCP port right now.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
    }
}

private struct SettingsMenu: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Divider()
            Button("Quit Port Viewer") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Button styles

private struct IconButtonStyle: ButtonStyle {
    var hoverTint: Color = .primary
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovering ? hoverTint : .secondary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? hoverTint.opacity(configuration.isPressed ? 0.2 : 0.1) : .clear)
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }
}

private struct KillConfirmButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Color.red.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}
