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

    private var timer: Timer?
    private let serviceName = "ExpressVPN Lightway"

    func startMonitoring() {
        checkStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkStatus()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func connect() {
        runProcess("/usr/sbin/scutil", arguments: ["--nc", "start", serviceName])
        // Check immediately after triggering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor [weak self] in
                self?.checkStatus()
            }
        }
    }

    func disconnect() {
        runProcess("/usr/sbin/scutil", arguments: ["--nc", "stop", serviceName])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor [weak self] in
                self?.checkStatus()
            }
        }
    }

    func checkStatus() {
        let output = runProcess("/usr/sbin/scutil", arguments: ["--nc", "status", serviceName])
        parseStatus(output)
    }

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
                // Line like "0 : 100.64.100.2"
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
        // scutil outputs dates like "02/24/2026 17:00:00"
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: string) {
            return date
        }
        // Also try ISO-ish formats
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        iso.locale = Locale(identifier: "en_US_POSIX")
        return iso.date(from: string)
    }
}
