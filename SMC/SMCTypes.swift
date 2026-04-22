import Foundation

public typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

@frozen
public struct SMCVersion {
    public var major: UInt8
    public var minor: UInt8
    public var build: UInt8
    public var reserved: UInt8
    public var release: UInt16

    public init(
        major: UInt8 = 0,
        minor: UInt8 = 0,
        build: UInt8 = 0,
        reserved: UInt8 = 0,
        release: UInt16 = 0
    ) {
        self.major = major
        self.minor = minor
        self.build = build
        self.reserved = reserved
        self.release = release
    }
}

@frozen
public struct SMCPLimitData {
    public var version: UInt16
    public var length: UInt16
    public var cpuPLimit: UInt32
    public var gpuPLimit: UInt32
    public var memPLimit: UInt32

    public init(
        version: UInt16 = 0,
        length: UInt16 = 0,
        cpuPLimit: UInt32 = 0,
        gpuPLimit: UInt32 = 0,
        memPLimit: UInt32 = 0
    ) {
        self.version = version
        self.length = length
        self.cpuPLimit = cpuPLimit
        self.gpuPLimit = gpuPLimit
        self.memPLimit = memPLimit
    }
}

@frozen
public struct SMCKeyInfoData {
    public var dataSize: UInt32
    public var dataType: UInt32
    public var dataAttributes: UInt8

    public init(
        dataSize: UInt32 = 0,
        dataType: UInt32 = 0,
        dataAttributes: UInt8 = 0
    ) {
        self.dataSize = dataSize
        self.dataType = dataType
        self.dataAttributes = dataAttributes
    }
}

@frozen
public struct SMCParamStruct {
    public static let zeroBytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    public var key: UInt32
    public var vers: SMCVersion
    public var pLimitData: SMCPLimitData
    public var keyInfo: SMCKeyInfoData
    public var result: UInt8
    public var status: UInt8
    public var data8: UInt8
    public var data32: UInt32
    public var bytes: SMCBytes

    public init() {
        self.init(
            key: 0,
            vers: SMCVersion(),
            pLimitData: SMCPLimitData(),
            keyInfo: SMCKeyInfoData(),
            result: 0,
            status: 0,
            data8: 0,
            data32: 0,
            bytes: Self.zeroBytes
        )
    }

    public init(
        key: UInt32,
        vers: SMCVersion,
        pLimitData: SMCPLimitData,
        keyInfo: SMCKeyInfoData,
        result: UInt8,
        status: UInt8,
        data8: UInt8,
        data32: UInt32,
        bytes: SMCBytes
    ) {
        self.key = key
        self.vers = vers
        self.pLimitData = pLimitData
        self.keyInfo = keyInfo
        self.result = result
        self.status = status
        self.data8 = data8
        self.data32 = data32
        self.bytes = bytes
    }
}

public enum SMCSelector: UInt8 {
    case kSMCHandleYPCEvent = 2
    case kSMCReadKey = 5
    case kSMCWriteKey = 6
    case kSMCGetKeyCount = 7
    case kSMCGetKeyFromIndex = 8
    case kSMCGetKeyInfo = 9
}

public enum DataType: String {
    case fpe2 = "fpe2"
    case ui8 = "ui8"
    case ui16 = "ui16"
    case ui32 = "ui32"
    case flag = "flag"
    case sp78 = "sp78"
}

public extension String {
    /// Packs exactly four ASCII bytes into a big-endian UInt32 so SMC keys can be sent to AppleSMC.
    var fourCharCode: UInt32 {
        let asciiBytes = Array(utf8)
        guard asciiBytes.count == 4 else { return 0 }

        // Each byte is shifted into the next big-endian slot: b0 b1 b2 b3 -> 0xB0B1B2B3.
        return asciiBytes.reduce(0) { partialResult, byte in
            (partialResult << 8) | UInt32(byte)
        }
    }
}

public extension UInt32 {
    /// Unpacks a big-endian UInt32 back into a four-character ASCII key name.
    var toString: String {
        let bytes: [UInt8] = [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]

        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}

public enum SMCKey {
    public static let FAN_NUM = "FNum"
    public static let FAN_0_RPM = "F0Ac"
    public static let FAN_0_MIN = "F0Mn"
    public static let FAN_0_MAX = "F0Mx"
    public static let FAN_0_TGT = "F0Tg"
    public static let FAN_0_MODE = "F0Md"
    public static let FAN_FORCE = "FS! "
    public static let FAN_1_RPM = "F1Ac"
    public static let FAN_1_MIN = "F1Mn"
    public static let FAN_1_MAX = "F1Mx"
    public static let FAN_1_TGT = "F1Tg"
    public static let FAN_1_MODE = "F1Md"
}

public enum SMCError: LocalizedError {
    case connectionFailed
    case keyNotFound
    case unsupportedDataType
    case writeNotPermitted
    case firmwareLocked(message: String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Unable to open an AppleSMC connection."
        case .keyNotFound:
            return "The requested SMC key could not be read."
        case .unsupportedDataType:
            return "The SMC key uses an unsupported data type."
        case .writeNotPermitted:
            return "Firmware denied write access to the requested SMC key."
        case .firmwareLocked(let message):
            return message
        }
    }
}


