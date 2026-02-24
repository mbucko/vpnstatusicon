import SwiftUI
import ServiceManagement

@main
struct VPNStatusIconApp: App {
    @StateObject private var monitor = VPNStatusMonitor()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            menuBarIcon
        }
    }

    private var menuBarIcon: some View {
        Image(nsImage: menuBarNSImage)
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
            color = .systemRed
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
        controlSection
        Divider()
        utilitySection
    }

    @ViewBuilder
    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(monitor.state.rawValue)
        }

        if let ip = monitor.ipAddress {
            Text("IP: \(ip)")
                .font(.system(.body, design: .monospaced))
        }

        if let since = monitor.connectedSince, monitor.state == .connected {
            Text("Connected: \(formattedDuration(since: since))")
        }
    }

    @ViewBuilder
    private var controlSection: some View {
        switch monitor.state {
        case .connected:
            Button("Disconnect") {
                monitor.disconnect()
            }
        case .disconnected:
            Button("Connect") {
                monitor.connect()
            }
        case .connecting:
            Button("Connecting...") {}
                .disabled(true)
        case .disconnecting:
            Button("Disconnecting...") {}
                .disabled(true)
        case .unknown:
            Button("Connect") {
                monitor.connect()
            }
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
