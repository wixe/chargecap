import Foundation
import Network

public class StatusServer {
    private let port: UInt16
    private var listener: NWListener?
    private weak var governor: AIGovernor?
    
    public init(port: Int = 8772, governor: AIGovernor) {
        self.port = UInt16(port)
        self.governor = governor
    }
    
    public func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        
        do {
            let params = NWParameters.tcp
            self.listener = try NWListener(using: params, on: nwPort)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("⚡ ChargeCap Status Server listening on http://0.0.0.0:\(self.port)")
                case .failed(let err):
                    print("⚠️ ChargeCap Status Server error: \(err.localizedDescription)")
                default:
                    break
                }
            }
            
            listener?.start(queue: .global(qos: .utility))
        } catch {
            print("⚠️ Failed to bind HTTP server on port \(port): \(error.localizedDescription)")
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil,
                  let requestStr = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            let firstLine = requestStr.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.components(separatedBy: " ")
            let path = parts.count > 1 ? parts[1] : "/"
            
            self.routeRequest(path: path, connection: connection)
        }
    }
    
    private func routeRequest(path: String, connection: NWConnection) {
        guard let governor = governor else {
            sendResponse(connection: connection, statusCode: 500, body: "{\"error\":\"Governor offline\"}")
            return
        }
        
        if path.starts(with: "/api/set") {
            // Parse ?limit=XX
            if let components = URLComponents(string: path),
               let limitItem = components.queryItems?.first(where: { $0.name == "limit" || $0.name == "target" }),
               let valStr = limitItem.value, let val = Int(valStr), val >= 20 && val <= 100 {
                
                var cfg = governor.config
                cfg.targetLimit = val
                governor.updateConfig(cfg)
                
                let resp = ["success": true, "message": "Target limit updated to \(val)%"] as [String: Any]
                if let jsonData = try? JSONSerialization.data(withJSONObject: resp, options: .prettyPrinted),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    sendResponse(connection: connection, statusCode: 200, body: jsonStr)
                    return
                }
            }
            sendResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Invalid limit parameter (20-100)\"}")
            return
        }
        
        // Default /api/status or /
        let report = governor.getCombinedReport()
        if let jsonData = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            sendResponse(connection: connection, statusCode: 200, body: jsonStr)
        } else {
            sendResponse(connection: connection, statusCode: 500, body: "{\"error\":\"JSON serialization failure\"}")
        }
    }
    
    private func sendResponse(connection: NWConnection, statusCode: Int, body: String) {
        let statusText = (statusCode == 200) ? "OK" : ((statusCode == 400) ? "Bad Request" : "Error")
        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """
        
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        } else {
            connection.cancel()
        }
    }
}
