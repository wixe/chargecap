import Foundation
import IOKit

public struct SMCKeyInfoData {
    public var dataSize: UInt32 = 0
    public var dataType: UInt32 = 0
    public var dataAttributes: UInt8 = 0
}

public struct SMCParamStruct {
    public var key: UInt32 = 0
    public var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0,0,0,0,0)
    public var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0,0,0,0,0)
    public var keyInfo = SMCKeyInfoData()
    public var padding: UInt8 = 0
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
        0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
    )
}

public class SMCDriver {
    private var connection: io_connect_t = 0
    private let lock = NSLock()
    
    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard kr == kIOReturnSuccess && connection != 0 else { return nil }
        
        // Open user client session
        _ = IOConnectCallScalarMethod(connection, 0, nil, 0, nil, nil)
    }
    
    deinit {
        close()
    }
    
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if connection != 0 {
            _ = IOConnectCallScalarMethod(connection, 1, nil, 0, nil, nil)
            IOServiceClose(connection)
            connection = 0
        }
    }
    
    private func fourCharCode(_ str: String) -> UInt32 {
        var res: UInt32 = 0
        for c in str.utf8.prefix(4) {
            res = (res << 8) | UInt32(c)
        }
        return res
    }
    
    public func getKeyInfo(_ keyStr: String) -> (size: Int, type: String)? {
        lock.lock()
        defer { lock.unlock() }
        guard connection != 0 else { return nil }
        
        var input = SMCParamStruct()
        input.key = fourCharCode(keyStr)
        input.data8 = 9 // kSMCGetKeyInfo
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        
        let kr = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outSize)
        guard kr == kIOReturnSuccess && output.result == 0 else { return nil }
        
        var typeStr = ""
        let t = output.keyInfo.dataType
        for shift in [24, 16, 8, 0] {
            let byte = UInt8((t >> shift) & 0xFF)
            if byte >= 32 && byte <= 126 {
                typeStr.append(Character(UnicodeScalar(byte)))
            }
        }
        return (Int(output.keyInfo.dataSize), typeStr)
    }
    
    public func readByte(_ keyStr: String) -> UInt8? {
        lock.lock()
        defer { lock.unlock() }
        guard connection != 0 else { return nil }
        
        var input = SMCParamStruct()
        input.key = fourCharCode(keyStr)
        input.data8 = 5 // kSMCReadKey
        input.keyInfo.dataSize = 1
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        
        let kr = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outSize)
        guard kr == kIOReturnSuccess && output.result == 0 else { return nil }
        return output.bytes.0
    }
    
    public func writeByte(_ keyStr: String, value: UInt8) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard connection != 0 else { return false }
        
        var input = SMCParamStruct()
        input.key = fourCharCode(keyStr)
        input.data8 = 6 // kSMCWriteKey
        input.keyInfo.dataSize = 1
        input.bytes.0 = value
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        
        let kr = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outSize)
        return kr == kIOReturnSuccess && output.result == 0
    }
}
