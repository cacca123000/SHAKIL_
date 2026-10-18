import Foundation
import SwiftUI

/// Live event log of everything the camera does (shown in the on-screen console
/// and in Settings → Log). Safe to call from any thread.
final class CameraLog: ObservableObject {
    enum Level: String {
        case info, success, warning, error, capture

        var tag: String {
            switch self {
            case .info: return "INFO"
            case .success: return " OK "
            case .warning: return "WARN"
            case .error: return "ERR!"
            case .capture: return "SHOT"
            }
        }

        var color: Color {
            switch self {
            case .info: return Color.white.opacity(0.75)
            case .success: return Theme.ok
            case .warning: return Theme.accent
            case .error: return Theme.rec
            case .capture: return Theme.cyan
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let level: Level
        let message: String

        var time: String { CameraLog.timeFormatter.string(from: date) }
    }

    static let shared = CameraLog()

    @Published private(set) var entries: [Entry] = []

    private static let maxEntries = 400
    fileprivate static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func log(_ message: String, _ level: Level = .info) {
        let entry = Entry(date: Date(), level: level, message: message)
        #if DEBUG
        print("[\(level.tag)] \(message)")
        #endif
        if Thread.isMainThread {
            append(entry)
        } else {
            DispatchQueue.main.async { self.append(entry) }
        }
    }

    func clear() {
        entries.removeAll()
        log("Log azzerato")
    }

    var exportText: String {
        entries.map { "\($0.time) [\($0.level.tag)] \($0.message)" }.joined(separator: "\n")
    }

    private func append(_ entry: Entry) {
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }
}

/// Shorthand used throughout the camera code.
func camLog(_ message: String, _ level: CameraLog.Level = .info) {
    CameraLog.shared.log(message, level)
}
