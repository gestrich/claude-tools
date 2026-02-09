import Foundation

final class LogService {
    let logFileURL: URL
    private let fileHandle: FileHandle

    init(label: String) throws {
        let fm = FileManager.default
        let logsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("dev-pilot")
            .appendingPathComponent("logs")

        if !fm.fileExists(atPath: logsDir.path) {
            try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let sanitizedLabel = String(
            label.replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                .prefix(50)
        )

        let filename = "\(timestamp)_\(sanitizedLabel).log"
        self.logFileURL = logsDir.appendingPathComponent(filename)

        fm.createFile(atPath: logFileURL.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: logFileURL)
        fileHandle.seekToEndOfFile()
    }

    deinit {
        try? fileHandle.close()
    }

    func log(_ message: String) {
        print(message)
        let stripped = Self.stripANSI("[\(Self.timestamp())] \(message)") + "\n"
        if let data = stripped.data(using: .utf8) {
            fileHandle.write(data)
        }
    }

    func writeRaw(_ data: Data) {
        FileHandle.standardError.write(data)
        if let str = String(data: data, encoding: .utf8) {
            let stripped = Self.stripANSI(str)
            if let strippedData = stripped.data(using: .utf8) {
                fileHandle.write(strippedData)
            }
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
    }
}
