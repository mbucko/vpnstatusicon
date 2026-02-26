import Foundation
import Combine
import Darwin

enum VPNState: String {
    case connected = "Connected"
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case disconnecting = "Disconnecting"
    case unknown = "Unknown"
}

@MainActor
final class VPNStatusMonitor: ObservableObject {
    @Published var state: VPNState = .unknown
    @Published var ipAddress: String?
    @Published var connectedSince: Date?
    @Published var localIP: String?
    @Published var publicIP: String?

    private var timer: Timer?
    private let serviceName = "ExpressVPN Lightway"

    private static let normalInterval: TimeInterval = 3.0
    private static let publicIPTTL: TimeInterval = 30.0

    private var lastPublicIPFetch: Date = .distantPast
    private var publicIPFetchInFlight = false

    func startMonitoring() {
        checkStatus()
        startNormalTimer()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func checkStatus() {
        let output = runProcess("/usr/sbin/scutil", arguments: ["--nc", "status", serviceName])
        parseStatus(output)
        refreshLocalIP()
        refreshPublicIP()
    }

    // MARK: - Timers

    private func startNormalTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.normalInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkStatus()
            }
        }
    }

    private func scheduleCheck(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor [weak self] in
                self?.checkStatus()
            }
        }
    }

    // MARK: - Process

    @discardableResult
    private func runProcess(_ path: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - IP Fetching

    private func refreshLocalIP() {
        localIP = getLocalIPAddress()
    }

    private func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let addr = ptr.pointee
            guard addr.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: addr.ifa_name)
            guard name == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr.ifa_addr, socklen_t(addr.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: hostname)
            }
        }
        return nil
    }

    private func refreshPublicIP() {
        guard !publicIPFetchInFlight,
              Date().timeIntervalSince(lastPublicIPFetch) >= Self.publicIPTTL else { return }

        publicIPFetchInFlight = true
        Task {
            defer { self.publicIPFetchInFlight = false }
            guard let url = URL(string: "https://api.ipify.org") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.publicIP = ip
                self.lastPublicIPFetch = Date()
            } catch {
                // Keep previous value on failure
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

        // Parse IP: look for "0 : <ip>" line right after "Addresses : <array> {"
        var inAddresses = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("Addresses : <array>") {
                inAddresses = true
                continue
            }
            if inAddresses {
                if trimmed.hasPrefix("0 : ") {
                    ipAddress = String(trimmed.dropFirst(4))
                }
                inAddresses = false
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
