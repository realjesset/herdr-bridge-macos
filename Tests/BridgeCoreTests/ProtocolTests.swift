import XCTest
@testable import BridgeCore

final class ProtocolTests: XCTestCase {
    let valid = #"{"version":1,"type":"snapshot","services":[{"id":"a","pane":"p","project":"demo","port":5173,"host":"127.0.0.1"}]}"#
    func testSnapshotAndFragmentation() throws {
        var parser = StreamParser()
        XCTAssertTrue(try parser.feed(Data(valid.prefix(20).utf8)).isEmpty)
        let events = try parser.feed(Data((String(valid.dropFirst(20)) + "\n").utf8))
        guard case .snapshot(let services) = events.first else { return XCTFail() }
        XCTAssertEqual(services.first?.port, 5173)
        XCTAssertEqual(services.first?.forwardSpec, "127.0.0.1:5173:127.0.0.1:5173")
    }
    func testRejectUnsafeFrames() {
        let invalid = [valid.replacingOccurrences(of: "5173", with: "true"),
                       valid.replacingOccurrences(of: "5173", with: "80"),
                       valid.replacingOccurrences(of: "127.0.0.1", with: "0.0.0.0"),
                       valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"),
                       valid.replacingOccurrences(of: "\"a\"", with: "\"bad id\""),
                       valid.replacingOccurrences(of: "\"demo\"", with: "\"bad\\u0000\""),
                       valid.replacingOccurrences(of: "5173", with: "5173.5")]
        for frame in invalid { XCTAssertThrowsError(try ProtocolDecoder.decode(Data(frame.utf8)), frame) }
        XCTAssertThrowsError(try ProtocolDecoder.decode(Data([0xff])))
    }
    func testDuplicateAndCountLimits() throws {
        let object = try JSONSerialization.jsonObject(with: Data(valid.utf8)) as! [String: Any]
        let service = (object["services"] as! [[String: Any]])[0]
        for count in [2, 129] {
            let data = try JSONSerialization.data(withJSONObject: ["version": 1, "type": "snapshot", "services": Array(repeating: service, count: count)])
            XCTAssertThrowsError(try ProtocolDecoder.decode(data))
        }
        var other = service; other["id"] = "b"
        let duplicateEndpoint = try JSONSerialization.data(withJSONObject: ["version": 1, "type": "snapshot", "services": [service, other]])
        XCTAssertThrowsError(try ProtocolDecoder.decode(duplicateEndpoint))
    }
    func testBoundsAndEOF() throws {
        var parser = StreamParser()
        XCTAssertThrowsError(try parser.feed(Data(repeating: 65, count: 65537)))
        parser = StreamParser()
        _ = try parser.feed(Data(valid.utf8))
        XCTAssertThrowsError(try parser.finish())
        XCTAssertTrue(SSHValidation.alias("dev-box"))
        for alias in ["", "-bad", "host;touch", "host name", "a\nb"] { XCTAssertFalse(SSHValidation.alias(alias)) }
    }
    func testExactFrameAndServiceLimits() throws {
        var parser = StreamParser()
        let empty = #"{"version":1,"type":"snapshot","services":[]}"#
        let padded = empty + String(repeating: " ", count: 65536 - empty.utf8.count)
        XCTAssertEqual(try parser.feed(Data((padded + "\n").utf8)).count, 1)
        XCTAssertNoThrow(try parser.finish())
        var services: [[String: Any]] = []
        for index in 0..<128 {
            services.append(["id": "id-\(index)", "pane": "pane", "project": "demo", "port": 1024 + index, "host": "127.0.0.1"])
        }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "type": "snapshot", "services": services])
        guard case .snapshot(let decoded) = try ProtocolDecoder.decode(data) else { return XCTFail() }
        XCTAssertEqual(decoded.count, 128)
        for port in [1024, 65535] {
            XCTAssertNoThrow(try ProtocolDecoder.decode(Data(valid.replacingOccurrences(of: "5173", with: String(port)).utf8)))
        }
        for port in [0, 1023, 65536] {
            XCTAssertThrowsError(try ProtocolDecoder.decode(Data(valid.replacingOccurrences(of: "5173", with: String(port)).utf8)))
        }
    }
    func testErrorAndIPv6() throws {
        guard case .remoteError(let message) = try ProtocolDecoder.decode(Data(#"{"version":1,"type":"error","message":"failure"}"#.utf8)) else { return XCTFail() }
        XCTAssertEqual(message, "failure")
        guard case .snapshot(let services) = try ProtocolDecoder.decode(Data(valid.replacingOccurrences(of: "127.0.0.1", with: "::1").utf8)) else { return XCTFail() }
        XCTAssertEqual(services[0].forwardSpec, "127.0.0.1:5173:[::1]:5173")
    }
}
