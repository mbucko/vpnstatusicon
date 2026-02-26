import SwiftUI
import ServiceManagement

@main
struct VPNStatusIconApp: App {
    @StateObject private var monitor = VPNStatusMonitor()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("showLocalIP") private var showLocalIP = false
    @AppStorage("showPublicIP") private var showPublicIP = false

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            menuBarIcon
        }
    }

    private var menuBarLabel: String? {
        var parts: [String] = []
        if showLocalIP, let ip = monitor.localIP {
            parts.append(ip)
        }
        if showPublicIP, let ip = monitor.publicIP {
            parts.append(ip)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    private var menuBarIcon: some View {
        HStack(spacing: 4) {
            if let label = menuBarLabel {
                Text(label)
            }
            Image(nsImage: menuBarNSImage)
        }
        .onAppear {
            monitor.startMonitoring()
        }
    }

    private var menuBarNSImage: NSImage {
        let symbolName: String
        let color: NSColor

        switch monitor.state {
        case .connected:
            symbolName = "shield.checkered"
            color = .systemGreen
        case .disconnected:
            symbolName = "shield.slash"
            color = .white
        case .connecting, .disconnecting:
            symbolName = "shield.lefthalf.filled"
            color = .systemYellow
        case .unknown:
            symbolName = "shield.slash"
            color = .secondaryLabelColor
        }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VPN Status")?
            .withSymbolConfiguration(config) ?? NSImage()
        let coloredImage = image.image(with: color)
        coloredImage.isTemplate = false
        return coloredImage
    }

    @ViewBuilder
    private var menuContent: some View {
        statusSection
        Divider()
        utilitySection
    }

    @ViewBuilder
    private var statusSection: some View {
        let stateEmoji = monitor.state == .connected ? "🟢" : "🔴"
        Button("\(stateEmoji) \(monitor.state.rawValue)") {}

        if let ip = monitor.ipAddress {
            Button("IP: \(ip)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ip, forType: .string)
            }
        }

        if let since = monitor.connectedSince, monitor.state == .connected {
            Button("Connected: \(formattedDuration(since: since))") {}
        }
    }

    @ViewBuilder
    private var utilitySection: some View {
        Button("Open ExpressVPN") {
            NSWorkspace.shared.open(URL(string: "expressvpn://")!)
        }

        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Revert on failure
                    launchAtLogin = !newValue
                }
            }

        Menu("Settings") {
            Toggle("Show Local IP in Menu Bar", isOn: $showLocalIP)
            Toggle("Show Public IP in Menu Bar", isOn: $showPublicIP)
        }

        Divider()

        Button("Quit") {
            monitor.stopMonitoring()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusColor: Color {
        switch monitor.state {
        case .connected: return .green
        case .disconnected: return .red
        case .connecting, .disconnecting: return .yellow
        case .unknown: return .gray
        }
    }

    private func formattedDuration(since date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

extension NSImage {
    func image(with tintColor: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        tintColor.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
