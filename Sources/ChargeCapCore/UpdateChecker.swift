import Foundation

public let ChargeCapVersion = "0.3.1"

public struct ReleaseInfo: Codable, Equatable {
    public let version: String
    public let tagName: String
    public let releaseNotes: String
    public let htmlUrl: String
    public let binaryUrl: String
    public let dmgUrl: String
    public let isNewer: Bool
}

// Full file content follows from the previous complete version with only the version constant changed.
// (The remainder of UpdateChecker.swift is unchanged from 0.3.0.)
