import Foundation
import AppKit
import Darwin

struct SyncError: Error, CustomStringConvertible {
    let description: String
}

func resolve(_ config: [String: Int], spaces: [[String: Any]]) throws -> [String: String] {
    let desktops = spaces.filter { ($0["type"] as? Int) == 0 }
    var desired: [String: String] = [:]
    for (identifier, number) in config {
        guard !identifier.isEmpty,
              identifier == identifier.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw SyncError(description: "Invalid application identifier")
        }
        let key = identifier.lowercased()
        guard desired[key] == nil else {
            throw SyncError(description: "Duplicate application identifier: \(identifier)")
        }
        guard number > 0, number <= desktops.count,
              let uuid = desktops[number - 1]["uuid"] as? String else {
            throw SyncError(description: "Desktop \(number) is unavailable for \(identifier); no changes made")
        }
        // The primary desktop legitimately uses an empty UUID.
        desired[key] = uuid
    }
    return desired
}

// React to preference changes and wake events; no polling timer is used.
final class DesktopMonitor {
    let home: URL
    let worker: URL
    var sources: [DispatchSourceFileSystemObject] = []
    var observers: [NSObjectProtocol] = []
    var pending: DispatchWorkItem?
    var refreshDock = false
    var snapshot = Data()

    init(home: URL, worker: URL) {
        self.home = home
        self.worker = worker
        snapshot = fingerprint()
    }

    func fingerprint() -> Data {
        let config = (try? Data(contentsOf: home.appendingPathComponent(".config/desktop-assignments.json"))) ?? Data()
        let path = home.appendingPathComponent("Library/Preferences/com.apple.spaces.plist")
        let data = (try? Data(contentsOf: path)) ?? Data()
        let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
        let display = plist["SpacesDisplayConfiguration"] as? [String: Any] ?? [:]
        let management = display["Management Data"] as? [String: Any] ?? [:]
        let monitors = management["Monitors"] as? [[String: Any]] ?? []
        let topology: [[String: Any]] = monitors.compactMap { monitor in
            guard let spaces = monitor["Spaces"] as? [[String: Any]] else { return nil }
            return ["display": monitor["Display Identifier"] as? String ?? "",
                    "spaces": spaces.map { ["uuid": $0["uuid"] as? String ?? "", "type": $0["type"] as? Int ?? -1] }]
        }
        let relevant: [String: Any] = ["bindings": plist["app-bindings"] as? [String: Any] ?? [:], "topology": topology]
        var result = config
        result.append((try? JSONSerialization.data(withJSONObject: relevant, options: [.sortedKeys])) ?? Data())
        return result
    }

    func schedule(forceRefresh: Bool = false, delay: Double = 1) {
        refreshDock = refreshDock || forceRefresh
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let process = Process()
            process.executableURL = self.worker
            process.arguments = self.refreshDock ? ["--refresh-dock"] : []
            self.refreshDock = false
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    print("\(ISO8601DateFormatter().string(from: Date())): recovery exited \(process.terminationStatus); waiting for the next event")
                }
            } catch {
                print("\(ISO8601DateFormatter().string(from: Date())): recovery could not start: \(error)")
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func start(observeWorkspace: Bool = true) throws {
        for directory in [".config", "Library/Preferences"] {
            let path = home.appendingPathComponent(directory).path
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { throw SyncError(description: "Cannot watch \(path)") }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let next = self.fingerprint()
                if next != self.snapshot {
                    self.snapshot = next
                    self.schedule()
                }
            }
            source.setCancelHandler { close(descriptor) }
            sources.append(source)
            source.resume()
        }
        if observeWorkspace {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                print("\(ISO8601DateFormatter().string(from: Date())): wake detected; scheduling Spaces recovery")
                self?.schedule(forceRefresh: true, delay: 4)
            }
            observers.append(observer)
        }
        schedule()
    }
}

do {
    if CommandLine.arguments.contains("--watch") {
        setbuf(stdout, nil)
        let monitor = DesktopMonitor(home: FileManager.default.homeDirectoryForCurrentUser,
                                     worker: URL(fileURLWithPath: CommandLine.arguments[0]))
        try monitor.start()
        print("\(ISO8601DateFormatter().string(from: Date())): monitoring Spaces assignments and wake events")
        withExtendedLifetime(monitor) { RunLoop.main.run() }
        exit(0)
    }
    if CommandLine.arguments.contains("--self-test") {
        let spaces: [[String: Any]] = [
            ["type": 0, "uuid": ""],
            ["type": 4, "uuid": "fullscreen"],
            ["type": 0, "uuid": "second"]
        ]
        let result = try resolve(["Primary.App": 1, "Second.App": 2], spaces: spaces)
        guard result == ["primary.app": "", "second.app": "second"] else {
            throw SyncError(description: "Resolution test failed")
        }
        for invalid in [["app": 0], ["app": 3], ["": 1], ["app ": 1], ["App": 1, "app": 2]] {
            var rejected = false
            do { _ = try resolve(invalid, spaces: spaces) } catch { rejected = true }
            guard rejected else { throw SyncError(description: "Invalid configuration accepted") }
        }
        for invalid in ["{\"app\":true}", "{\"app\":1.5}", "{\"app\":\"2\"}", "not json"] {
            var rejected = false
            do { _ = try JSONDecoder().decode([String: Int].self, from: Data(invalid.utf8)) }
            catch { rejected = true }
            guard rejected else { throw SyncError(description: "Invalid JSON accepted") }
        }
        guard try resolve([:], spaces: []) == [:] else {
            throw SyncError(description: "Empty configuration test failed")
        }
        print("Self-tests passed")
        exit(0)
    }

    let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/desktop-assignments.json")
    let config = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: configURL))
    guard let defaults = UserDefaults(suiteName: "com.apple.spaces"),
          let displayConfig = defaults.dictionary(forKey: "SpacesDisplayConfiguration"),
          let management = displayConfig["Management Data"] as? [String: Any],
          let monitors = management["Monitors"] as? [[String: Any]] else {
        throw SyncError(description: "Spaces are not ready; no changes made")
    }
    let activeMonitors = monitors.filter { $0["Spaces"] != nil }
    guard activeMonitors.count == 1,
          let spaces = activeMonitors[0]["Spaces"] as? [[String: Any]] else {
        throw SyncError(description: "This configuration requires one active display; no changes made")
    }
    let desired = try resolve(config, spaces: spaces)
    let savedBindings = defaults.dictionary(forKey: "app-bindings") ?? [:]
    var bindings = savedBindings
    var changes: [String] = []
    for key in desired.keys.sorted() {
        let uuid = desired[key]!
        if bindings[key] as? String != uuid {
            bindings[key] = uuid
            changes.append("Set \(key) -> Space \(uuid.isEmpty ? "primary" : uuid)")
        }
        // Dock assignment keys are lowercase, unlike some bundle identifiers.
        for alias in Array(bindings.keys) where alias != key && alias.lowercased() == key {
            bindings.removeValue(forKey: alias)
            changes.append("Removed redundant assignment key \(alias)")
        }
    }
    if CommandLine.arguments.contains("--diagnose") {
        let actual = savedBindings.reduce(into: [String: String]()) { result, entry in
            if desired[entry.key.lowercased()] != nil {
                result[entry.key] = (entry.value as? String) ?? "<invalid>"
            }
        }
        let desktops = spaces.filter { ($0["type"] as? Int) == 0 }
        let ordering = Dictionary(uniqueKeysWithValues: desktops.enumerated().map {
            (String($0.offset + 1), ($0.element["uuid"] as? String) ?? "<missing>")
        })
        let snapshot = ["actual": actual, "expected": desired, "desktops": ordering]
        let stateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/desktop-assignments-diagnostics.json")
        let previous = (try? Data(contentsOf: stateURL)).flatMap {
            try? JSONDecoder().decode([String: [String: String]].self, from: $0)
        }
        if previous != snapshot {
            try JSONEncoder().encode(snapshot).write(to: stateURL, options: .atomic)
            var observed: [String] = []
            if let previous {
                for key in Set(actual.keys).union(previous["actual", default: [:]].keys).sorted() {
                    let old = previous["actual"]?[key]
                    let new = actual[key]
                    if old != new {
                        observed.append("\(key): \(old ?? "<unassigned>") -> \(new ?? "<unassigned>")")
                    }
                }
                if previous["desktops"] != ordering { observed.append("Desktop UUIDs/order changed") }
                if previous["expected"] != desired { observed.append("Expected assignments changed") }
            } else {
                observed.append("Initial diagnostic snapshot")
            }
            let status = changes.isEmpty ? "Assignments match configuration" : "Mismatch: \(changes.joined(separator: "; "))"
            print("\(ISO8601DateFormatter().string(from: Date())): \(observed.joined(separator: "; ")); \(status); diagnostic only, no settings changed")
        }
        exit(0)
    }
    if CommandLine.arguments.contains("--check") {
        if changes.isEmpty {
            print("All configured assignments match macOS")
        } else {
            print(changes.joined(separator: "\n"))
            exit(2)
        }
        exit(0)
    }
    if changes.isEmpty && !CommandLine.arguments.contains("--refresh-dock") { exit(0) }
    if !changes.isEmpty {
        defaults.set(bindings, forKey: "app-bindings")
        guard defaults.synchronize() else {
            throw SyncError(description: "Could not synchronize assignments")
        }
    }
    if changes.isEmpty { changes.append("Refresh Dock after wake to restore Spaces shortcuts") }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["Dock"]
    try process.run()
    process.waitUntilExit()
    print("\(ISO8601DateFormatter().string(from: Date())): \(changes.joined(separator: "; ")); Dock reload status \(process.terminationStatus)")
    if process.terminationStatus != 0 { exit(1) }
} catch {
    let message = "\(ISO8601DateFormatter().string(from: Date())): desktop-assignments-sync: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
