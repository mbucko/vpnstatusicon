import Foundation
import Combine
import Darwin
import Network
import Observation

enum VPNState: String {
    case connected = "Connected"
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case disconnecting = "Disconnecting"
    case unknown = "Unknown"
}

@MainActor
@Observable
final class VPNStatusMonitor {
    var state: VPNState = .unknown
    var ipAddress: String?
    var connectedSince: Date?
    var localIP: String?
    var publicIP: String?
    
    // Configurable VPN service name (from UserDefaults)
    var serviceName: String {
        get { UserDefaults.standard.string(forKey: "vpnServiceName") ?? "ExpressVPN Lightway" }
        set { 
            UserDefaults.standard.set(newValue, forKey: "vpnServiceName")
            checkStatus()
        }
    }

    private var timer: Timer?
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "VPNStatusMonitorPathMonitor")
    
    private static let fallbackInterval: TimeInterval = 60.0
    private static let publicIPTTL: TimeInterval = 60.0

    private var lastPublicIPFetch: Date = .distantPast
    private var isChecking = false

    func startMonitoring() {
        checkStatus()
        
        // Setup NWPathMonitor for efficient triggers
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkStatus()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
        
        // Fallback timer (much longer)
        startFallbackTimer()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        pathMonitor.cancel()
    }

    func checkStatus() {
        guard !isChecking else { return }
        isChecking = true
        
        Task {
            defer { isChecking = false }
            
            // Run scutil in a background thread to avoid blocking UI
            let output = await runProcessAsync("/usr/sbin/scutil", arguments: ["--nc", "status", serviceName])
            
            // Update properties (runs on MainActor because the class is @MainActor)
            parseStatus(output)
            refreshLocalIP()
            refreshPublicIP()
        }
    }

    // MARK: - Discovery

    func getAvailableServices() async -> [String] {
        let output = await runProcessAsync("/usr/sbin/scutil", arguments: ["--nc", "list"])
        let lines = output.components(separatedBy: "\n")
        var services: [String] = []
        
        // Line format: * (Disconnected) <UUID> VPN (com.xxx) "Name" [VPN:com.xxx]
        for line in lines {
            let parts = line.components(separatedBy: "\"")
            if parts.count >= 3 {
                let name = parts[1]
                if !name.isEmpty {
                    services.append(name)
                }
            }
        }
        return services.sorted()
    }

    // MARK: - Timers

    private func startFallbackTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.fallbackInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkStatus()
            }
        }
    }

    // MARK: - Process

    private func runProcessAsync(_ path: String, arguments: [String]) async -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        return await withCheckedContinuation { continuation in
            do {
                process.terminationHandler = { _ in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                }
                try process.run()
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - IP Fetching

    private func refreshLocalIP() {
        localIP = getPrimaryLocalIPAddress()
    }

    private func getPrimaryLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let addr = ptr.pointee
            let flags = Int32(addr.ifa_flags)
            let family = addr.ifa_addr.pointee.sa_family

            // Filter for IPv4, Up, and not Loopback
            if family == UInt8(AF_INET) && (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0 {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr.ifa_addr, socklen_t(addr.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: hostname)
                }
            }
        }
        return nil
    }

    private func refreshPublicIP() {
        guard Date().timeIntervalSince(lastPublicIPFetch) >= Self.publicIPTTL else { return }

        Task {
            guard let url = URL(string: "https://api.ipify.org") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    self.publicIP = ip
                    self.lastPublicIPFetch = Date()
                }
            } catch {
                // Silently fail, keep old value
            }
        }
    }

    // MARK: - Parsing

    private func parseStatus(_ output: String) {
        let lines = output.components(separatedBy: "\n")
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespaces) else {
            state = .unknown
            ipAddress = nil
            connectedSince = nil
            return
        }

        switch firstLine {
        case "Connected":
            state = .connected
        case "Disconnected":
            state = .disconnected
            ipAddress = nil
            connectedSince = nil
            return
        case "Connecting":
            state = .connecting
        case "Disconnecting":
            state = .disconnecting
        default:
            state = .unknown
            ipAddress = nil
            connectedSince = nil
            return
        }

        // Improved IP parsing: find first IPv4 after "Addresses : <array>"
        var inAddresses = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("Addresses : <array>") {
                inAddresses = true
                continue
            }
            if inAddresses {
                if trimmed.contains(":") && trimmed.components(separatedBy: ".").count >= 3 {
                    if let value = trimmed.components(separatedBy: " : ").last {
                        ipAddress = value
                        inAddresses = false
                    }
                } else if trimmed == "}" {
                    inAddresses = false
                }
            }

            if trimmed.hasPrefix("LastStatusChangeTime") {
                if let value = trimmed.components(separatedBy: " : ").last?.trimmingCharacters(in: .whitespaces) {
                    connectedSince = parseDate(value)
                }
            }
        }
    }

    private func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: string) {
            return date
        }
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        iso.locale = Locale(identifier: "en_US_POSIX")
        return iso.date(from: string)
    }
}
