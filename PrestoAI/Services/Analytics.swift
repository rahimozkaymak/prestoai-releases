import Foundation
import AppKit

final class Analytics: @unchecked Sendable {
    static let shared = Analytics()

    private var buffer: [[String: Any]] = []
    private let lock = NSLock()
    private var flushTimer: Timer?
    private let flushInterval: TimeInterval = 30

    private init() {
        setupFlushTimer()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification, object: nil
        )
    }

    func track(_ event: String, params: [String: String] = [:]) {
        let entry: [String: Any] = [
            "name": event,
            "params": params,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        lock.lock()
        buffer.append(entry)
        lock.unlock()
    }

    private func setupFlushTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushTimer = Timer.scheduledTimer(withTimeInterval: self.flushInterval, repeats: true) { [weak self] _ in
                self?.flush()
            }
        }
    }

    @objc private func appWillTerminate() {
        flush()
    }

    func flush() {
        lock.lock()
        guard !buffer.isEmpty else { lock.unlock(); return }
        let events = buffer
        buffer = []
        lock.unlock()

        let deviceID = AppStateManager.shared.deviceID
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let body: [String: Any] = [
            "device_id": deviceID,
            "app_version": appVersion,
            "os_version": osVersion,
            "events": events
        ]

        guard let url = URL(string: "\(APIService.shared.baseURL)/api/v1/events"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            // Put events back on failure
            lock.lock()
            buffer = events + buffer
            lock.unlock()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                // Put events back for retry
                self?.lock.lock()
                self?.buffer = events + (self?.buffer ?? [])
                self?.lock.unlock()
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 202 {
                self?.lock.lock()
                self?.buffer = events + (self?.buffer ?? [])
                self?.lock.unlock()
            }
        }.resume()
    }
}
