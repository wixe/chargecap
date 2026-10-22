import Foundation
import Darwin

public final class UnixSocketServer {
    public static let defaultSocketPath = "/var/run/chargecap.sock"
    
    private let socketPath: String
    private var serverFD: Int32 = -1
    private var isRunning = false
    private weak var governor: AIGovernor?
    private let acceptQueue = DispatchQueue(label: "com.wixe.chargecap.ipc", qos: .utility)
    
    public init(socketPath: String = UnixSocketServer.defaultSocketPath, governor: AIGovernor) {
        self.socketPath = socketPath
        self.governor = governor
    }
    
    deinit {
        stop()
    }
    
    public func start() {
        guard !isRunning else { return }
        
        unlink(socketPath)
        
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLen else {
            close(fd)
            return
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
            for (i, byte) in pathBytes.enumerated() {
                rawBuf[i] = UInt8(bitPattern: byte)
            }
        }
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, listen(fd, 8) == 0 else {
            close(fd)
            return
        }
        
        // Allow local processes to connect for read-only STATUS;
        // write commands (SET / SAILING) enforce root (euid == 0) via getpeereid().
        chmod(socketPath, 0o666)
        
        self.serverFD = fd
        self.isRunning = true
        
        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }
    
    public func stop() {
        isRunning = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
    }
    
    private func acceptLoop() {
        while isRunning && serverFD >= 0 {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverFD, sockPtr, &clientLen)
                }
            }
            if clientFD < 0 {
                if !isRunning { break }
                continue
            }
            handleClient(clientFD)
        }
    }
    
    private func handleClient(_ clientFD: Int32) {
        defer { close(clientFD) }
        
        // Prevent SIGPIPE if client disconnects early, and enforce 500ms read/write timeouts
        var noSigPipe: Int32 = 1
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        var euid: uid_t = 65534
        var egid: gid_t = 65534
        let credOK = (getpeereid(clientFD, &euid, &egid) == 0)
        
        var buffer = [UInt8](repeating: 0, count: 512)
        let bytesRead = read(clientFD, &buffer, buffer.count - 1)
        let request: String
        if bytesRead > 0 {
            request = String(decoding: buffer.prefix(bytesRead), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            request = "STATUS"
        }
        
        let response = processCommand(request, isRootPeer: credOK && euid == 0)
        _ = response.withCString { cStr in
            write(clientFD, cStr, strlen(cStr))
        }
    }
    
    private func processCommand(_ commandLine: String, isRootPeer: Bool) -> String {
        guard let governor = governor else {
            return "{\"error\":\"Governor unavailable\"}\n"
        }
        
        let parts = commandLine.split(separator: " ").map(String.init)
        let cmd = (parts.first ?? "STATUS").uppercased()
        
        switch cmd {
        case "STATUS", "GET":
            let report = governor.getCombinedReport()
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                return json + "\n"
            }
            return "{\"error\":\"Serialization failed\"}\n"
            
        case "SET":
            guard isRootPeer else {
                return "{\"error\":\"Permission denied: root (sudo) privileges required to control power\"}\n"
            }
            guard parts.count >= 2, let limit = Int(parts[1]), (20...100).contains(limit) else {
                return "{\"error\":\"Invalid limit: must be 20-100\"}\n"
            }
            var cfg = governor.config
            cfg.targetLimit = limit
            governor.updateConfig(cfg)
            return "{\"success\":true,\"target_limit\":\(limit)}\n"
            
        case "SAILING":
            guard isRootPeer else {
                return "{\"error\":\"Permission denied: root (sudo) privileges required to control power\"}\n"
            }
            guard parts.count >= 2 else {
                return "{\"error\":\"Usage: SAILING <on|off> [delta]\"}\n"
            }
            let enabled = ["on", "true", "1"].contains(parts[1].lowercased())
            var delta = governor.config.sailingDelta
            if parts.count >= 3, let d = Int(parts[2]), (1...10).contains(d) {
                delta = d
            }
            var cfg = governor.config
            cfg.sailingEnabled = enabled
            cfg.sailingDelta = delta
            governor.updateConfig(cfg)
            return "{\"success\":true,\"sailing_enabled\":\(enabled),\"sailing_delta\":\(delta)}\n"
            
        default:
            return "{\"error\":\"Unknown command. Supported: STATUS, SET <20-100>, SAILING <on|off> [1-10]\"}\n"
        }
    }
}

public enum UnixSocketClient {
    public static func send(_ command: String, socketPath: String = UnixSocketServer.defaultSocketPath) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLen else { return nil }
        
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
            for (i, byte) in pathBytes.enumerated() {
                rawBuf[i] = UInt8(bitPattern: byte)
            }
        }
        
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }
        
        let payload = command.hasSuffix("\n") ? command : (command + "\n")
        _ = payload.withCString { cStr in
            write(fd, cStr, strlen(cStr))
        }
        
        var output = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            output.append(buf, count: n)
        }
        return output.isEmpty ? nil : String(data: output, encoding: .utf8)
    }
}
