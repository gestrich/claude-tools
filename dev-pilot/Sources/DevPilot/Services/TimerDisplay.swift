import Foundation

final class TimerDisplay: @unchecked Sendable {
    private let maxRuntimeSeconds: Int
    private let scriptStartTime: Date
    private let lock = NSLock()
    private var phaseStartTime: Date = Date()
    private var running = false
    private var statusLine: String = ""

    init(maxRuntimeSeconds: Int, scriptStartTime: Date) {
        self.maxRuntimeSeconds = maxRuntimeSeconds
        self.scriptStartTime = scriptStartTime
    }

    static func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    func setStatusLine(_ text: String) {
        lock.lock()
        statusLine = text
        lock.unlock()
    }

    func start() {
        lock.lock()
        guard !running else {
            lock.unlock()
            return
        }
        phaseStartTime = Date()
        running = true
        lock.unlock()

        let size = terminalSize()
        if size.height > 3 {
            writeToStdout("\u{1B}[1;\(size.height - 2)r")
            writeToStdout("\u{1B}[\(size.height - 2);1H")
        }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.timerLoop()
        }
    }

    func stop() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        running = false
        lock.unlock()

        usleep(100_000)

        let size = terminalSize()
        writeToStdout("\u{1B}[r")
        writeToStdout("\u{1B}[\(size.height);1H\u{1B}[K")
        writeToStdout("\u{1B}[\(size.height - 1);1H\u{1B}[K")
        writeToStdout("\u{1B}[\(size.height - 2);1H\n")
    }

    private func timerLoop() {
        while true {
            lock.lock()
            let isRunning = running
            lock.unlock()
            guard isRunning else { break }

            updateDisplay()
            usleep(500_000)
        }
    }

    private func updateDisplay() {
        lock.lock()
        let phaseStart = phaseStartTime
        let currentStatus = statusLine
        lock.unlock()

        let now = Date()
        let phaseElapsed = Int(now.timeIntervalSince(phaseStart))
        let totalElapsed = Int(now.timeIntervalSince(scriptStartTime))

        let timerText = "\u{1B}[0;36m\u{23F1}  Phase: \(Self.formatTime(phaseElapsed)) | Total: \(Self.formatTime(totalElapsed)) of \(Self.formatTime(maxRuntimeSeconds))\u{1B}[0m"

        let size = terminalSize()
        let truncatedStatus = currentStatus.isEmpty ? "" : "\u{1B}[0;33m\(String(currentStatus.prefix(size.width)))\u{1B}[0m"

        writeToStdout("\u{1B}7\u{1B}[\(size.height - 1);1H\u{1B}[K\(truncatedStatus)\u{1B}[\(size.height);1H\u{1B}[K\(timerText)\u{1B}8")
    }

    private func terminalSize() -> (width: Int, height: Int) {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_row > 0, ws.ws_col > 0 {
            return (Int(ws.ws_col), Int(ws.ws_row))
        }
        return (80, 24)
    }

    private func writeToStdout(_ str: String) {
        fputs(str, stdout)
        fflush(stdout)
    }
}
