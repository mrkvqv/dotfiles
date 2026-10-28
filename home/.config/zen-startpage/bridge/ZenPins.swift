import Foundation
import Compression

// Exports only Essentials, never the rest of the saved browsing session.
final class ZenPins {
    private var cacheKey = ""
    private var cached: [String: Any]?

    func snapshot() throws -> [String: Any] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/zen")
        let profile = try Self.profile(in: root)
        let file = profile.appendingPathComponent("zen-sessions.jsonlz4")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let modified = attributes[.modificationDate] as? Date ?? Date.distantPast
        let key = file.path + "|" + String(modified.timeIntervalSince1970) + "|" + String(describing: attributes[.size])
        if key == cacheKey, let cached = cached { return cached }
        let data = try Data(contentsOf: file)
        let pins = try Self.parse(Self.decode(data))
        let result: [String: Any] = ["pins": pins, "source": "Zen Essentials", "updatedAt": ISO8601DateFormatter().string(from: modified)]
        cacheKey = key; cached = result
        return result
    }

    static func profile(in root: URL) throws -> URL {
        let text = try String(contentsOf: root.appendingPathComponent("profiles.ini"), encoding: .utf8)
        var sections: [(String, [String: String])] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("["), line.hasSuffix("]") { sections.append((String(line.dropFirst().dropLast()), [:])); continue }
            guard !line.hasPrefix(";"), !line.hasPrefix("#"), !sections.isEmpty, let equal = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equal]).trimmingCharacters(in: .whitespaces)
            sections[sections.count-1].1[key] = String(line[line.index(after: equal)...]).trimmingCharacters(in: .whitespaces)
        }
        let installed = sections.first { $0.0.hasPrefix("Install") && $0.1["Default"] != nil }?.1["Default"]
        let fallback = sections.first { $0.0.hasPrefix("Profile") && $0.1["Default"] == "1" }?.1["Path"]
        guard let path = installed ?? fallback ?? sections.first(where: { $0.0.hasPrefix("Profile") })?.1["Path"] else { throw Failure.invalidSession }
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
    }

    enum Failure: Error { case invalidSession }

    static func decode(_ data: Data) throws -> Data {
        guard data.count > 12, data.count <= 32 * 1024 * 1024,
              data.prefix(8) == Data([109,111,122,76,122,52,48,0]) else { throw Failure.invalidSession }
        let count = data[8..<12].enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
        guard count > 0, count <= 64 * 1024 * 1024 else { throw Failure.invalidSession }
        var result = Data(count: count)
        let length = result.withUnsafeMutableBytes { destination in
            data.dropFirst(12).withUnsafeBytes { source in
                compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, count,
                    source.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        guard length == count else { throw Failure.invalidSession }
        return result
    }

    static func safeImage(_ value: Any?) -> String? {
        guard let value = value as? String, value.utf8.count <= 512 * 1024,
              value.range(of: "^data:image/(png|jpeg|gif|webp|avif|x-icon|vnd.microsoft.icon|svg\\+xml)[;,]", options: .regularExpression) != nil else { return nil }
        return value
    }

    static func parse(_ data: Data) throws -> [[String: Any]] {
        guard let session = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tabs = session["tabs"] as? [[String: Any]] else { throw Failure.invalidSession }
        var seen = Set<String>()
        return tabs.compactMap { tab in
            guard tab["zenEssential"] as? Bool == true, tab["zenIsEmpty"] as? Bool != true else { return nil }
            let initial = tab["_zenPinnedInitialState"] as? [String: Any] ?? [:]
            let entry = initial["entry"] as? [String: Any] ?? (tab["entries"] as? [[String: Any]])?.last ?? [:]
            guard let text = entry["url"] as? String, let url = URLComponents(string: text),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil else { return nil }
            let id = tab["zenSyncId"] as? String ?? text
            guard seen.insert(id).inserted else { return nil }
            let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let custom = tab["zenPinnedIcon"] as? String ?? ""
            let image = safeImage(custom) ?? safeImage(tab["image"]) ?? safeImage(initial["image"])
            let symbol = custom.count <= 16 && !custom.contains(":") && !custom.contains("/") ? custom : ""
            return ["id": id, "url": text, "title": String((title.isEmpty ? host : title).prefix(160)),
                    "image": image as Any? ?? NSNull(), "symbol": symbol, "customIcon": !custom.isEmpty]
        }
    }
}
