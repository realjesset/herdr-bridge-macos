import Foundation
import CoreFoundation

public struct Service: Hashable {
    public let id: String
    public let pane: String
    public let project: String
    public let port: Int
    public let host: String
    public var forwardSpec: String {
        "127.0.0.1:\(port):\(host == "::1" ? "[::1]" : host):\(port)"
    }
}
public enum StreamEvent { case snapshot([Service]), remoteError(String) }
public enum ProtocolError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let reason): return "Invalid detector stream: \(reason)" }
    }
}
public enum SSHValidation {
    public static func alias(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && !value.hasPrefix("-") &&
        value.unicodeScalars.allSatisfy { scalar in
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.@-".unicodeScalars.contains(scalar)
        }
    }
}
public enum ProtocolDecoder {
    public static let maxFrame = 65536
    static func text(_ value: Any?, maximum: Int) -> String? {
        guard let s = value as? String, s.unicodeScalars.count <= maximum,
              !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return s
    }
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue >= 0, number.doubleValue <= 65535 else { return nil }
        return number.intValue
    }
    public static func decode(_ data: Data) throws -> StreamEvent {
        guard !data.isEmpty, data.count <= maxFrame,
              String(data: data, encoding: .utf8) != nil,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              integer(root["version"]) == 1, let type = root["type"] as? String else {
            throw ProtocolError.invalid("frame, version or envelope")
        }
        if type == "error" {
            guard Set(root.keys) == ["version", "type", "message"],
                  let message = text(root["message"], maximum: 1024), !message.isEmpty else {
                throw ProtocolError.invalid("error message")
            }
            return .remoteError(message)
        }
        guard type == "snapshot", Set(root.keys) == ["version", "type", "services"],
              let rows = root["services"] as? [[String: Any]], rows.count <= 128 else {
            throw ProtocolError.invalid("snapshot schema or service count")
        }
        var ids = Set<String>(), endpoints = Set<String>(), services: [Service] = []
        for row in rows {
            guard Set(row.keys) == ["id", "pane", "project", "port", "host"],
                  let id = text(row["id"], maximum: 128), !id.isEmpty,
                  id.unicodeScalars.allSatisfy({ "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:-".unicodeScalars.contains($0) }),
                  let pane = text(row["pane"], maximum: 128),
                  let project = text(row["project"], maximum: 128),
                  let port = integer(row["port"]), port >= 1024,
                  let host = row["host"] as? String, ["127.0.0.1", "::1"].contains(host),
                  ids.insert(id).inserted, endpoints.insert("\(host):\(port)").inserted else {
                throw ProtocolError.invalid("service fields or duplicate service")
            }
            services.append(Service(id: id, pane: pane, project: project, port: port, host: host))
        }
        return .snapshot(services)
    }
}
public struct StreamParser {
    private var buffer = Data()
    public init() {}
    public mutating func feed(_ data: Data) throws -> [StreamEvent] {
        var result: [StreamEvent] = []
        for byte in data {
            if byte == 10 {
                result.append(try ProtocolDecoder.decode(buffer))
                buffer.removeAll(keepingCapacity: true)
            } else {
                guard buffer.count < ProtocolDecoder.maxFrame else { throw ProtocolError.invalid("frame exceeds 64 KiB") }
                buffer.append(byte)
            }
        }
        return result
    }
    public func finish() throws {
        if !buffer.isEmpty { throw ProtocolError.invalid("truncated frame at EOF") }
    }
}
