import AppKit
import EventKit
import Foundation
import Network

// Read-only EventKit bridge. No calendar data is written to disk or sent off-device.
final class CalendarBridge: NSObject, NSApplicationDelegate {
    private let store = EKEventStore()
    private let pins = ZenPins()
    private var listener: NWListener?
    private var token = ""
    private var port: UInt16 = 8766
    private var revision = 0
    private var browserRequests = 0
    private var lastBrowserRequest: Date?
    private let iso = ISO8601DateFormatter()
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let configURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/ZenCalendarBridge/config.json")
            let config = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
            guard let secret = config?["token"] as? String, secret.count >= 32,
                  let configuredPort = config?["port"] as? Int,
                  let parsedPort = UInt16(exactly: configuredPort) else { throw BridgeError.configuration }
            self.token = secret
            port = parsedPort
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            parameters.allowLocalEndpointReuse = true
            let server = try NWListener(using: parameters)
            listener = server
            server.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            server.stateUpdateHandler = { state in
                if case .failed = state { NSApplication.shared.terminate(nil) }
            }
            server.start(queue: .main)
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                self?.revision += 1
            }
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                NSApplication.shared.activate(ignoringOtherApps: true)
                store.requestFullAccessToEvents { [weak self] _, _ in
                    DispatchQueue.main.async { self?.revision += 1 }
                }
            }
        } catch {
            fputs("Calendar bridge could not start: invalid configuration or unavailable port.\n", stderr)
            NSApplication.shared.terminate(nil)
        }
    }

    private enum BridgeError: Error { case configuration }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { connection.cancel() }
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            var bytes = buffer
            if let data = data { bytes.append(data) }
            guard bytes.count <= 16_384, error == nil else { connection.cancel(); return }
            if let text = String(data: bytes, encoding: .utf8), text.contains("\r\n\r\n") {
                self?.handle(connection, request: text)
            } else if !complete {
                self?.receive(connection, buffer: bytes)
            } else { connection.cancel() }
        }
    }

    private func authorized(_ value: String) -> Bool {
        let expected = Array(("Bearer " + token).utf8), actual = Array(value.utf8)
        guard expected.count == actual.count else { return false }
        return zip(expected, actual).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private func handle(_ connection: NWConnection, request: String) {
        let lines = request.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count == 3 else { connection.cancel(); return }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let colon = line.firstIndex(of: ":") else { connection.cancel(); return }
            let name = line[..<colon].lowercased()
            guard headers[name] == nil else { connection.cancel(); return }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let origin = headers["origin"]
        let allowedOrigin = origin == "null"
        guard headers["host"] == "127.0.0.1:\(port)", origin == nil || allowedOrigin else {
            send(connection, status: 403, object: ["error": "forbidden_origin"], cors: false); return
        }
        if first[0] == "OPTIONS" {
            guard allowedOrigin, headers["access-control-request-method"] == "GET",
                  (headers["access-control-request-headers"] ?? "authorization").lowercased()
                    .split(separator: ",").allSatisfy({ $0.trimmingCharacters(in: .whitespaces) == "authorization" }) else {
                send(connection, status: 403, object: ["error": "forbidden_preflight"], cors: false); return
            }
            send(connection, status: 204, object: [:], cors: true); return
        }
        guard first[0] == "GET" else {
            send(connection, status: 405, object: ["error": "read_only"], cors: allowedOrigin); return
        }
        guard authorized(headers["authorization"] ?? "") else {
            send(connection, status: 401, object: ["error": "unauthorized"], cors: allowedOrigin); return
        }
        guard first[1].hasPrefix("/"), !first[1].hasPrefix("//"),
              let url = URLComponents(string: "http://127.0.0.1:\(port)" + first[1]) else {
            send(connection, status: 400, object: ["error": "invalid_request"], cors: allowedOrigin); return
        }
        if url.path == "/v1/status" {
            let access = accessStatus()
            let count = access == "granted" ? store.calendars(for: .event).count : 0
            send(connection, status: 200, object: ["access": access, "calendarCount": count, "revision": revision,
                "browserRequests": browserRequests, "lastBrowserRequest": timestamp(lastBrowserRequest)], cors: allowedOrigin)
            return
        }
        if url.path == "/v1/pins" {
            do { send(connection, status: 200, object: try pins.snapshot(), cors: allowedOrigin) }
            catch { send(connection, status: 503, object: ["error": "pins_unavailable"], cors: allowedOrigin) }
            return
        }
        guard url.path == "/v1/events" else {
            send(connection, status: 404, object: ["error": "not_found"], cors: allowedOrigin); return
        }
        guard accessStatus() == "granted" else {
            send(connection, status: 403, object: ["error": "calendar_permission", "access": accessStatus()], cors: allowedOrigin); return
        }
        let query = url.queryItems ?? []
        guard query.count == 2, Set(query.map { $0.name }) == Set(["start", "end"]),
              let startText = query.first(where: { $0.name == "start" })?.value,
              let endText = query.first(where: { $0.name == "end" })?.value,
              let start = dayFormatter.date(from: startText), let end = dayFormatter.date(from: endText),
              dayFormatter.string(from: start) == startText, dayFormatter.string(from: end) == endText,
              end > start, end.timeIntervalSince(start) <= 120 * 86_400 else {
            send(connection, status: 400, object: ["error": "invalid_date_range"], cors: allowedOrigin); return
        }
        let calendars = store.calendars(for: .event)
        if allowedOrigin { browserRequests += 1; lastBrowserRequest = Date() }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = calendars.isEmpty ? [] : store.events(matching: predicate)
        let payload: [String: Any] = [
            "access": "granted", "start": startText, "end": endText,
            "updatedAt": iso.string(from: Date()), "timeZone": TimeZone.autoupdatingCurrent.identifier,
            "revision": revision, "calendars": calendars.map(calendarJSON),
            "events": events.sorted { $0.startDate < $1.startDate }.map(eventJSON)
        ]
        send(connection, status: 200, object: payload, cors: allowedOrigin)
    }

    private func accessStatus() -> String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return "granted"
        case .writeOnly: return "write_only"
        case .notDetermined: return "not_determined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        @unknown default: return "unavailable"
        }
    }

    private func optional(_ value: String?) -> Any { if let value = value { return value }; return NSNull() }
    private func timestamp(_ value: Date?) -> Any { if let value = value { return iso.string(from: value) }; return NSNull() }

    private func calendarJSON(_ calendar: EKCalendar) -> [String: Any] {
        var color = "#b8b8ad"
        if let cg = calendar.cgColor, let rgb = NSColor(cgColor: cg)?.usingColorSpace(.deviceRGB) {
            color = String(format: "#%02x%02x%02x", Int(max(0, min(1, rgb.redComponent)) * 255), Int(max(0, min(1, rgb.greenComponent)) * 255), Int(max(0, min(1, rgb.blueComponent)) * 255))
        }
        return ["id": calendar.calendarIdentifier, "title": calendar.title, "color": color,
                "source": calendar.source.title, "sourceType": calendar.source.sourceType.rawValue,
                "readOnly": !calendar.allowsContentModifications, "subscribed": calendar.isSubscribed]
    }

    private func participantJSON(_ participant: EKParticipant) -> [String: Any] {
        return ["name": optional(participant.name), "url": participant.url.absoluteString,
                "status": participant.participantStatus.rawValue, "role": participant.participantRole.rawValue,
                "type": participant.participantType.rawValue, "isCurrentUser": participant.isCurrentUser]
    }

    private func eventJSON(_ event: EKEvent) -> [String: Any] {
        let rules: [[String: Any]] = (event.recurrenceRules ?? []).map { rule in
            let end: [String: Any] = ["date": timestamp(rule.recurrenceEnd?.endDate), "count": rule.recurrenceEnd?.occurrenceCount ?? 0]
            return ["frequency": rule.frequency.rawValue, "interval": rule.interval, "end": end,
                    "daysOfWeek": (rule.daysOfTheWeek ?? []).map { ["day": $0.dayOfTheWeek.rawValue, "week": $0.weekNumber] },
                    "daysOfMonth": (rule.daysOfTheMonth ?? []).map { $0.intValue },
                    "monthsOfYear": (rule.monthsOfTheYear ?? []).map { $0.intValue }]
        }
        let alarms: [[String: Any]] = (event.alarms ?? []).map {
            ["relativeOffset": $0.relativeOffset, "absoluteDate": timestamp($0.absoluteDate), "proximity": $0.proximity.rawValue]
        }
        var result: [String: Any] = [
            "id": event.calendarItemIdentifier, "externalId": optional(event.calendarItemExternalIdentifier),
            "eventIdentifier": optional(event.eventIdentifier), "title": event.title ?? "",
            "start": iso.string(from: event.startDate), "end": iso.string(from: event.endDate),
            "startDay": dayFormatter.string(from: event.startDate), "endDay": dayFormatter.string(from: event.endDate),
            "allDay": event.isAllDay, "calendarId": event.calendar.calendarIdentifier,
            "timeZone": optional(event.timeZone?.identifier), "location": optional(event.location),
            "notes": optional(event.notes), "url": optional(event.url?.absoluteString),
            "createdAt": timestamp(event.creationDate), "modifiedAt": timestamp(event.lastModifiedDate),
            "occurrenceDate": timestamp(event.occurrenceDate), "detached": event.isDetached,
            "recurrence": rules, "alarms": alarms, "status": event.status.rawValue,
            "availability": event.availability.rawValue, "attendees": (event.attendees ?? []).map(participantJSON)
        ]
        if let organizer = event.organizer { result["organizer"] = participantJSON(organizer) }
        if let location = event.structuredLocation {
            var structured: [String: Any] = ["title": optional(location.title), "radius": location.radius]
            if let geo = location.geoLocation { structured["latitude"] = geo.coordinate.latitude; structured["longitude"] = geo.coordinate.longitude }
            result["structuredLocation"] = structured
        }
        return result
    }

    private func send(_ connection: NWConnection, status: Int, object: [String: Any], cors: Bool) {
        guard let body = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            let error = Data("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: error, completion: .contentProcessed { _ in connection.cancel() }); return
        }
        let message = [200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "Error"
        let bytes = status == 204 ? Data() : body
        var header = "HTTP/1.1 \(status) \(message)\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\nContent-Length: \(bytes.count)\r\n"
        if cors { header += "Access-Control-Allow-Origin: null\r\nVary: Origin\r\nAccess-Control-Allow-Methods: GET\r\nAccess-Control-Allow-Headers: Authorization\r\nAccess-Control-Allow-Private-Network: true\r\nAccess-Control-Max-Age: 600\r\n" }
        connection.send(content: Data((header + "\r\n").utf8) + bytes, completion: .contentProcessed { _ in connection.cancel() })
    }
}

@main enum BridgeMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = CalendarBridge()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
