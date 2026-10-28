import Foundation
import Compression

@main enum PinTests {
    static func main() throws {
        func tab(_ id: String, _ url: String, essential: Bool = true) -> [String: Any] {
            return ["zenSyncId": id, "zenEssential": essential, "pinned": true,
                    "_zenPinnedInitialState": ["entry": ["url": url, "title": "Pinned " + id]],
                    "entries": [["url": "https://current.example/another-page", "title": "Private current page"]],
                    "storage": ["private": "not-exported"]]
        }
        var credentials = URLComponents(string: "https://bad.example/")!
        credentials.user = "test"; credentials.password = "example"
        let original: [String: Any] = ["tabs": [tab("b", "https://b.example/"), tab("a", "https://a.example/"),
            tab("ordinary", "https://ordinary.example/", essential: false), tab("b", "https://b.example/"),
            tab("unsafe", "javascript:alert(1)"), tab("credentials", credentials.string!)]]
        let json = try JSONSerialization.data(withJSONObject: original)
        let pins = try ZenPins.parse(json)
        assert(pins.count == 2)
        assert(pins.map { $0["id"] as! String } == ["b", "a"])
        assert(pins[0]["url"] as? String == "https://b.example/")
        assert(pins[0]["storage"] == nil && pins[0]["entries"] == nil)
        let changed = try ZenPins.parse(JSONSerialization.data(withJSONObject: ["tabs": [tab("new", "https://new.example/")]]))
        assert(changed.count == 1 && changed[0]["id"] as? String == "new")
        let empty = try ZenPins.parse(JSONSerialization.data(withJSONObject: ["tabs": []])); assert(empty.isEmpty)
        assert(ZenPins.safeImage("https://tracker.example/icon.png") == nil)
        assert(ZenPins.safeImage("data:text/html;base64,abc") == nil)
        assert(ZenPins.safeImage("data:image/png;base64,abc") != nil)
        assert(ZenPins.safeImage("data:image/svg+xml,%3Csvg%3E") != nil)
        var encoded = Data(count: json.count + 1024)
        let length = encoded.withUnsafeMutableBytes { destination in json.withUnsafeBytes { source in
            compression_encode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                source.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_LZ4_RAW)
        }}
        assert(length > 0)
        var file = Data([109,111,122,76,122,52,48,0])
        var size = UInt32(json.count).littleEndian
        withUnsafeBytes(of: &size) { file.append(contentsOf: $0) }
        file.append(encoded.prefix(length))
        let decoded = try ZenPins.decode(file); assert(decoded == json)
        do { _ = try ZenPins.decode(Data("invalid".utf8)); assertionFailure("Invalid header accepted") } catch {}
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "[Profile1]\nPath=other\nDefault=1\n[InstallABC]\nDefault=Profiles/real\n".write(to: folder.appendingPathComponent("profiles.ini"), atomically: true, encoding: .utf8)
        let profile = try ZenPins.profile(in: folder); assert(profile == folder.appendingPathComponent("Profiles/real"))
        print("PASS: saved order, Essentials only, pinned base URL, add/remove, empty list, no session leakage, safe icons, mozLz4 round trip, profile selection.")
    }
}
