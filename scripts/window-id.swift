// Prints the CGWindowID of the largest on-screen window owned by a process.
// Usage: xcrun swift scripts/window-id.swift <pid>
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: window-id.swift <pid>\n".utf8))
    exit(64)
}

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []

let match = windows
    .filter { info in
        let bounds = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
        // Skip the menu-bar strips the app owns; a content window is taller.
        return (info[kCGWindowOwnerPID as String] as? Int) == pid
            && (info[kCGWindowLayer as String] as? Int) == 0
            && (bounds["Height"] ?? 0) > 100
    }
    .max { lhs, rhs in
        func area(_ info: [String: Any]) -> Double {
            let bounds = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
        }
        return area(lhs) < area(rhs)
    }

guard let windowID = match?[kCGWindowNumber as String] as? Int else { exit(1) }
print(windowID)
