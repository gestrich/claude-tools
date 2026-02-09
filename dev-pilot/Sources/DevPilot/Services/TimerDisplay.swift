import Foundation
#if canImport(Darwin)
import Darwin
#endif

final class TimerDisplay: @unchecked Sendable {
    private let maxRuntimeSeconds: Int
    private let scriptStartTime: Date
    private var phaseStartTime: Date = Date()
    private var running = false
    private var thread: Thread?

    init(maxRuntimeSeconds: Int, scriptStartTime: Date) {
        self.maxRuntimeSeconds = maxRuntimeSeconds
        self.scriptStartTime = scriptStartTime
    }

    func start() {
        phaseStartTime = Date()
        running = true

        if let termHeight = Self.terminalHeight() {
            // Set scroll region to exclude bottom line
            print("\u{1B}[1;\(termHeight - 1)r", terminator: "")
            print("\u{1B}[\(termHeight - 1);1H", terminator: "")
            fflush(stdout)
        }

        let t = Thread { [weak self] in
            self?.updateLoop()
        }
        t.qualityOfService = .utility
        t.start()
        thread = t
    }

    func stop() {
        running = false
        thread = nil

        // Reset scroll region and clear timer line
        if let termHeight = Self.terminalHeight() {
            print("\u{1B}[r", terminator: "")
            print("\u{1B}[\(termHeight);1H\u{1B}[K", terminator: "")
            print("\u{1B}[\(termHeight - 1);1H")
            fflush(stdout)
        }
    }

    // MARK: - Private

    private func updateLoop() {
        while running {
            let now = Date()
            let phaseElapsed = Int(now.timeIntervalSince(phaseStartTime))
            let totalElapsed = Int(now.timeIntervalSince(scriptStartTime))

            let display = "\u{1B}[0;36m⏱  Phase: \(Self.formatTime(phaseElapsed)) | Total: \(Self.formatTime(totalElapsed)) of \(Self.formatTime(maxRuntimeSeconds))\u{1B}[0m"

            if let termHeight = Self.terminalHeight() {
                print("\u{1B}[\(termHeight);1H\u{1B}[K\(display)", terminator: "")
                fflush(stdout)
            }

            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    static func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private static func terminalHeight() -> Int? {
        var w = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0, w.ws_row > 0 else {
            return nil
        }
        return Int(w.ws_row)
    }
}
