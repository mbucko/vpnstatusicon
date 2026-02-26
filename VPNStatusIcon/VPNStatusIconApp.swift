import SwiftUI
import ServiceManagement

@main
struct VPNStatusIconApp: App {
    private var monitor = VPNStatusMonitor()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("showLocalIP") private var showLocalIP = false
    @AppStorage("showPublicIP") private var showPublicIP = false
    @AppStorage("vpnServiceName") private var vpnServiceName = "ExpressVPN Lightway"
    
    @State private var availableServices: [String] = []

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            menuBarLabelContent
        }
    }

    @ViewBuilder
    private var menuBarLabelContent: some View {
        HStack(spacing: 4) {
            if let label = menuBarLabelText {
                Text(label)
            }
            Image(nsImage: menuBarNSImage)
        }
        .onAppear {
            monitor.startMonitoring()
            updateAvailableServices()
        }
    }

    private var menuBarLabelText: String? {
        var parts: [String] = []
        if showLocalIP, let ip = monitor.localIP {
            parts.append(ip)
        }
        if showPublicIP, let ip = monitor.publicIP {
            parts.append(ip)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
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
            color = .secondaryLabelColor // Adaptive color for disconnected
        case .connecting, .disconnecting:
            symbolName = "shield.lefthalf.filled"
            color = .systemYellow
        case .unknown:
            symbolName = "shield.slash"
            color = .tertiaryLabelColor
        }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VPN Status")?
            .withSymbolConfiguration(config) ?? NSImage()
        
        return image.tinted(with: color)
    }

    @ViewBuilder
    private var menuContent: some View {
        statusSection
        Divider()
        vpnServiceSelectionSection
        Divider()
        utilitySection
    }

    @ViewBuilder
    private var statusSection: some View {
        let stateEmoji = monitor.state == .connected ? "🟢" : "🔴"
        Text("\(stateEmoji) \(monitor.state.rawValue)")
            .font(.headline)

        if let ip = monitor.ipAddress {
            Button("VPN IP: \(ip)") {
                copyToClipboard(ip)
            }
        }

        if let since = monitor.connectedSince, monitor.state == .connected {
            Text("Connected for: \(formattedDuration(since: since))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var vpnServiceSelectionSection: some View {
        Menu("VPN Service: \(vpnServiceName)") {
            if availableServices.isEmpty {
                Button("Discovering...") {}
                    .disabled(true)
            } else {
                ForEach(availableServices, id: \.self) { service in
                    Button(service) {
                        vpnServiceName = service
                        monitor.serviceName = service
                    }
                    .symbolVariant(service == vpnServiceName ? .fill : .none)
                }
            }
            Divider()
            Button("Refresh Services") {
                updateAvailableServices()
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

    private func updateAvailableServices() {
        Task {
            availableServices = await monitor.getAvailableServices()
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
