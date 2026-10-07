import Foundation

enum QuickNote {
    /// `- [YYYY-MM-DD HH:mm] text`, one line per note; nil for blank input.
    static func line(for text: String, at date: Date, timeZone: TimeZone = .current) -> String? {
        let flattened = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !flattened.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "- [\(formatter.string(from: date))] \(flattened)"
    }

    /// Appends one note, creating the folder and file on first use. Returns
    /// false for blank input.
    @discardableResult
    static func append(_ text: String, at date: Date, to url: URL, timeZone: TimeZone = .current) throws -> Bool {
        guard let line = line(for: text, at: date, timeZone: timeZone) else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? Data(contentsOf: url)) ?? Data()
        var addition = Data()
        if let last = existing.last, last != UInt8(ascii: "\n") { addition.append(UInt8(ascii: "\n")) }
        addition.append(Data((line + "\n").utf8))
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: addition)
        } else {
            try addition.write(to: url, options: .atomic)
        }
        return true
    }
}
