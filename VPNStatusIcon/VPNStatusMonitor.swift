import Foundation
import Combine

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
    @Published var userWantsDisconnected = false

    private var timer: Timer?
    private var disconnectEnforcerTimer: Timer?
    private let serviceName = "ExpressVPN Lightway"

    private static let normalInterval: TimeInterval = 3.0
    private static let enforcerInterval: TimeInterval = 0.5

    func startMonitoring() {
        checkStatus()
        startNormalTimer()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        disconnectEnforcerTimer?.invalidate()
        disconnectEnforcerTimer = nil
    }

    func connect() {
        userWantsDisconnected = false
        stopEnforcer()
        runProcess("/usr/sbin/scutil", arguments: ["--nc", "start", serviceName])
        scheduleCheck(after: 0.5)
    }

    func disconnect() {
        userWantsDisconnected = true
        runProcess("/usr/sbin/scutil", arguments: ["--nc", "stop", serviceName])
        startEnforcer()
        scheduleCheck(after: 0.5)
    }

    func checkStatus() {
        let output = runProcess("/usr/sbin/scutil", arguments: ["--nc", "status", serviceName])
        parseStatus(output)
    }

    // MARK: - Disconnect enforcer

    /// Rapid timer that keeps killing the VPN when on-demand reconnects
    private func startEnforcer() {
        disconnectEnforcerTimer?.invalidate()
        disconnectEnforcerTimer = Timer.scheduledTimer(withTimeInterval: Self.enforcerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.enforceDisconnect()
            }
        }
    }

    private func stopEnforcer() {
        disconnectEnforcerTimer?.invalidate()
        disconnectEnforcerTimer = nil
    }

    private func enforceDisconnect() {
        let output = runProcess("/usr/sbin/scutil", arguments: ["--nc", "status", serviceName])
        let firstLine = output.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""

        if firstLine == "Connected" || firstLine == "Connecting" {
            runProcess("/usr/sbin/scutil", arguments: ["--nc", "stop", serviceName])
        }

        parseStatus(output)
    }

    // MARK: - Timers

    private func startNormalTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.normalInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.checkStatus()
                // Catch late on-demand reconnects even after enforcer stops
                if self.userWantsDisconnected && (self.state == .connected || self.state == .connecting) {
                    self.runProcess("/usr/sbin/scutil", arguments: ["--nc", "stop", self.serviceName])
                }
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
