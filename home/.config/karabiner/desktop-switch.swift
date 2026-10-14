// Karabiner helper: ask Dock to perform a native desktop swipe, without Ctrl shortcuts.
// The pinned InstantSpaceSwitcher core is linked by install_desktop_switch.sh.
import AppKit

@_silgen_name("CGSMainConnectionID") func connectionID() -> UInt32
@_silgen_name("CGSCopyManagedDisplaySpaces") func managedSpaces(_ connection: UInt32) -> Unmanaged<CFArray>?
@_silgen_name("iss_switch_to_index") func switchToIndex(_ index: UInt32) -> Bool

struct SwitchError: Error, CustomStringConvertible {
    let description: String
}

func activeDisplay() throws -> [String: Any] {
    guard let all = managedSpaces(connectionID())?.takeRetainedValue() as? [[String: Any]] else {
        throw SwitchError(description: "Cannot read desktop information")
    }
    let active = all.filter { $0["Current Space"] != nil }
    guard active.count == 1 else {
        throw SwitchError(description: "Desktop switching requires one active display")
    }
    return active[0]
}

func currentSpace(_ display: [String: Any]) -> UInt64? {
    ((display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value
}

do {
    let state = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
    try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
    let descriptor = open(state.appendingPathComponent("desktop-switch.lock").path, O_CREAT | O_RDWR, 0o600)
    guard descriptor >= 0, flock(descriptor, LOCK_EX) == 0 else { throw SwitchError(description: "Cannot serialize desktop switches") }
    defer { flock(descriptor, LOCK_UN); close(descriptor) }
    let display = try activeDisplay()
    if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--current" {
        guard let id = currentSpace(display) else { throw SwitchError(description: "Cannot read the current desktop") }
        print(id)
        exit(0)
    }
    guard CommandLine.arguments.count == 2, let number = Int(CommandLine.arguments[1]), number > 0 else {
        throw SwitchError(description: "Usage: desktop-switch DESKTOP_NUMBER")
    }
    let allSpaces = display["Spaces"] as? [[String: Any]] ?? []
    let desktops = allSpaces.filter { ($0["type"] as? Int) == 0 }
    guard number <= desktops.count,
          let target = (desktops[number - 1]["ManagedSpaceID"] as? NSNumber)?.uint64Value,
          let targetIndex = allSpaces.firstIndex(where: { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value == target }) else {
        throw SwitchError(description: "Desktop \(number) is unavailable; no change made")
    }
    if currentSpace(display) == target { exit(0) }
    guard CGPreflightPostEventAccess() else {
        _ = CGRequestPostEventAccess()
        throw SwitchError(description: "Accessibility event-posting permission is required for the Karabiner launching process; enable it in System Settings > Privacy & Security > Accessibility")
    }
    guard switchToIndex(UInt32(targetIndex)) else { throw SwitchError(description: "Dock rejected the desktop swipe") }
    for _ in 0..<50 {
        if currentSpace(try activeDisplay()) == target { exit(0) }
        usleep(50000)
    }
    throw SwitchError(description: "Dock did not switch to desktop \(number)")
} catch {
    FileHandle.standardError.write(Data("desktop-switch: \(error)\n".utf8))
    exit(1)
}
