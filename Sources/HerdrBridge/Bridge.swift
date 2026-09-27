import AppKit
import BridgeCore
import Darwin

// All model/UI mutation is on the main queue. Management commands are FIFO,
// including cancellation and exit, so a late forward can never outlive Stop.
final class Bridge {
    enum State { case pending, activating, active, ignored, stopping, error(String) }
    struct Entry {
        var service: Service
        let token: UUID
        var state: State
    }
    private(set) var entries: [String: Entry] = [:]
    private(set) var generation = UUID()
    private(set) var connected = false
    private(set) var detectorReady = false
    private(set) var status = "Disconnected"
    var changed: (() -> Void)?
    var discovered: ((Entry, UUID) -> Void)?
    var clearNotifications: (() -> Void)?
    private var seen = Set<String>()
    private var master: Process?
    private var directory: URL?
    private var socket: String?
    private var alias = ""
    private var parser = StreamParser()
    private var heartbeat: Timer?
    private var lastSnapshot = ProcessInfo.processInfo.systemUptime
    private let management = DispatchQueue(label: "HerdrBridge.ssh.management")

    private static let strict = [
        "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
        "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
        "-o", "PreferredAuthentications=publickey",
        "-o", "ForwardAgent=no", "-o", "ForwardX11=no",
        "-o", "ForwardX11Trusted=no", "-o", "GatewayPorts=no",
        "-o", "Tunnel=no", "-o", "UpdateHostKeys=no",
        "-o", "PermitLocalCommand=no", "-o", "ConnectTimeout=10"
    ]
    func connect(alias candidate: String) {
        guard !connected else { return }
        guard SSHValidation.alias(candidate) else { status = "Invalid SSH alias"; changed?(); return }
        generation = UUID(); let epoch = generation
        alias = candidate; seen.removeAll(); entries.removeAll(); parser = StreamParser()
        do {
            // mkdtemp atomically creates a private 0700 directory; short socket path
            // avoids Darwin's sockaddr_un limit (NSTemporaryDirectory can be long).
            var template = Array("/tmp/herdr-\(getuid())-XXXXXX".utf8CString)
            let createdPath = template.withUnsafeMutableBufferPointer { buffer -> String? in
                guard let base = buffer.baseAddress, let created = mkdtemp(base) else { return nil }
                return String(cString: created)
            }
            guard let path = createdPath else { throw ProtocolError.invalid("cannot create private SSH directory") }
            let dir = URL(fileURLWithPath: path, isDirectory: true)
            directory = dir
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            let control = dir.appendingPathComponent("s").path; socket = control
            let process = Process(); let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = Self.strict + [
                "-T", "-M", "-S", control,
                "-o", "ControlMaster=yes", "-o", "ControlPersist=no",
                "-o", "ClearAllForwardings=yes", "-o", "ExitOnForwardFailure=yes",
                "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2",
                "-o", "ForkAfterAuthentication=no", "-o", "SessionType=default",
                "-o", "RemoteCommand=none", "-o", "RequestTTY=no",
                candidate, "~/.local/bin/herdr-bridge-agent --watch"
            ]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            // No stderr accumulation, password UI, or untrusted terminal escape rendering.
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    guard let self = self, self.generation == epoch else { return }
                    self.disconnect(reason: "SSH detector exited (\(process.terminationStatus))")
                }
            }
            master = process
            try process.run()
            connected = true; status = "Waiting for detector…"
            lastSnapshot = ProcessInfo.processInfo.systemUptime
            heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self = self, self.generation == epoch else { return }
                if ProcessInfo.processInfo.systemUptime - self.lastSnapshot >= 15 {
                    self.disconnect(reason: "Detector heartbeat timed out")
                }
            }
            // Keep the watchdog running while the status menu is tracking.
            if let heartbeat = heartbeat { RunLoop.main.add(heartbeat, forMode: .common) }
            // Fixed read size + synchronous delivery bounds memory even on hostile output.
            DispatchQueue.global(qos: .utility).async { [weak self] in
                defer { try? output.fileHandleForReading.close() }
                while true {
                    do {
                        // POSIX read returns available pipe bytes immediately. Foundation's
                        // read(upToCount:) can accumulate toward the requested count,
                        // starving our heartbeat on a sparse, never-ending stream.
                        var bytes = [UInt8](repeating: 0, count: 4096)
                        let count = bytes.withUnsafeMutableBytes { buffer in
                            Darwin.read(output.fileHandleForReading.fileDescriptor,
                                        buffer.baseAddress!, buffer.count)
                        }
                        if count < 0 {
                            if errno == EINTR { continue }
                            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                        }
                        let data = Data(bytes.prefix(count))
                        var keepReading = false
                        DispatchQueue.main.sync {
                            guard let self = self, self.generation == epoch, self.connected else { return }
                            if data.isEmpty {
                                do { try self.parser.finish(); self.disconnect(reason: "Detector stream closed") }
                                catch { self.disconnect(reason: error.localizedDescription) }
                            } else {
                                self.receive(data); keepReading = self.connected
                            }
                        }
                        if !keepReading { break }
                    } catch {
                        DispatchQueue.main.async {
                            guard let self = self, self.generation == epoch else { return }
                            self.disconnect(reason: "Detector read failed")
                        }
                        break
                    }
                }
            }
            changed?()
        } catch { disconnect(reason: "SSH startup failed: \(error.localizedDescription)") }
    }
    private func receive(_ data: Data) {
        do {
            for event in try parser.feed(data) {
                guard connected else { break }
                switch event {
                case .remoteError(let message): disconnect(reason: "Detector: \(message)")
                case .snapshot(let services):
                    detectorReady = true
                    lastSnapshot = ProcessInfo.processInfo.systemUptime
                    status = "Connected to \(alias)"
                    apply(services)
                }
            }
        } catch { disconnect(reason: error.localizedDescription) }
    }
    private func apply(_ services: [Service]) {
        let current = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
        guard seen.union(current.keys).count <= 512 else {
            disconnect(reason: "Too many distinct services; reconnect to reset discovery")
            return
        }
        if entries.keys.contains(where: { current[$0] == nil }) { clearNotifications?() }
        for (id, entry) in entries {
            if let new = current[id] {
                // An ID must not silently transfer approval to another endpoint/pane.
                if new.host != entry.service.host || new.port != entry.service.port || new.pane != entry.service.pane || new.project != entry.service.project {
                    disconnect(reason: "Detector reused a service ID for a different endpoint")
                    return
                }
            } else {
                cancelIfNeeded(entry)
                entries.removeValue(forKey: id)
            }
        }
        for service in services {
            if var entry = entries[service.id] { entry.service = service; entries[service.id] = entry }
            else {
                let first = seen.insert(service.id).inserted
                let entry = Entry(service: service, token: UUID(), state: first ? .pending : .ignored)
                entries[service.id] = entry
                if first { discovered?(entry, generation) }
            }
        }
        changed?()
    }
    func approve(id: String, token: UUID, epoch: UUID) {
        guard generation == epoch, connected, var entry = entries[id], entry.token == token,
              case .pending = entry.state else { return }
        entry.state = .activating; entries[id] = entry; changed?()
        command("forward", service: entry.service) { [weak self] result in
            guard let self = self, self.generation == epoch,
                  var live = self.entries[id], live.token == token,
                  case .activating = live.state else { return }
            switch result {
            case .success: live.state = .active
            case .failure(let error): live.state = .error(error.localizedDescription)
            }
            self.entries[id] = live; self.changed?()
        }
    }
    func ignore(id: String, token: UUID, epoch: UUID) {
        guard generation == epoch, var entry = entries[id], entry.token == token,
              case .pending = entry.state else { return }
        entry.state = .ignored; entries[id] = entry; changed?()
    }
    func stop(id: String, token: UUID) {
        guard var entry = entries[id], entry.token == token else { return }
        switch entry.state {
        case .active, .activating:
            let epoch = generation
            entry.state = .stopping; entries[id] = entry; changed?()
            command("cancel", service: entry.service) { [weak self] result in
                guard let self = self, self.generation == epoch else { return }
                if case .failure = result { self.disconnect(reason: "Could not confirm cancellation; closed SSH session"); return }
                guard var live = self.entries[id], live.token == token else { return }
                live.state = .ignored; self.entries[id] = live; self.changed?()
            }
        default: break
        }
    }
    private func cancelIfNeeded(_ entry: Entry) {
        switch entry.state {
        case .active, .activating:
            let epoch = generation
            command("cancel", service: entry.service) { [weak self] result in
                guard let self = self, self.generation == epoch else { return }
                if case .failure = result { self.disconnect(reason: "Tunnel cleanup failed; closed SSH session") }
            }
        default: break
        }
    }
    private func command(_ operation: String, service: Service,
                         completion: @escaping (Result<Void, Error>) -> Void) {
        guard let socket = socket else { return }
        let target = alias, epoch = generation
        management.async {
            let result = Self.control(operation, socket: socket, alias: target, spec: service.forwardSpec)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.generation == epoch else { return }
                if result.timedOut { self.disconnect(reason: "SSH management timed out; closed session") }
                else { completion(result.result) }
            }
        }
    }
    // Mux commands MUST NOT load alias config: ssh -O forward also applies any
    // configured LocalForward/RemoteForward. -F /dev/null here is safe because
    // -O requires the existing private socket and cannot establish a connection.
    private static func control(_ operation: String, socket: String, alias: String, spec: String? = nil)
        -> (result: Result<Void, Error>, timedOut: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var args = ["-F", "/dev/null", "-S", socket, "-O", operation] + strict + [
            "-o", "ControlMaster=no", "-o", "ExitOnForwardFailure=yes"
        ]
        if let spec = spec { args += ["-L", spec] }
        args.append(alias); process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() }
        catch { return (.failure(error), false) }
        if finished.wait(timeout: .now() + 8) == .timedOut {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return (.failure(ProtocolError.invalid("SSH control timeout")), true)
        }
        if process.terminationStatus == 0 { return (.success(()), false) }
        return (.failure(ProtocolError.invalid("SSH \(operation) failed (\(process.terminationStatus)); port may be occupied")), false)
    }
    func disconnect(reason: String = "Disconnected") {
        generation = UUID(); connected = false; detectorReady = false
        heartbeat?.invalidate(); heartbeat = nil
        let oldMaster = master, oldDirectory = directory, oldSocket = socket, oldAlias = alias
        master = nil; directory = nil; socket = nil
        entries.removeAll(); seen.removeAll(); parser = StreamParser()
        status = reason; clearNotifications?(); changed?()
        // Close master immediately; queued forward/cancel requests cannot reconnect.
        if let process = oldMaster, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        management.async {
            if let socket = oldSocket { _ = Self.control("exit", socket: socket, alias: oldAlias) }
            // Termination acknowledgement must precede application exit and unlink.
            // Never rely only on an async kill timer that dies with the app.
            if let process = oldMaster, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            if let dir = oldDirectory { try? FileManager.default.removeItem(at: dir) }
        }
    }
    func shutdown(completion: @escaping () -> Void) {
        disconnect()
        management.async { DispatchQueue.main.async(execute: completion) }
    }
}
