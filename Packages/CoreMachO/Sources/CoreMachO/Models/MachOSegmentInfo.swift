import Foundation

public struct SegmentProtection: OptionSet, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let read = SegmentProtection(rawValue: 1)
    public static let write = SegmentProtection(rawValue: 2)
    public static let execute = SegmentProtection(rawValue: 4)
}

public struct SegmentInfo: Sendable {
    public let command: UInt32
    public let commandOffset: Int
    public let name: String
    public let vmAddress: UInt64
    public let vmSize: UInt64
    public let fileOffset: UInt64
    public let fileSize: UInt64
    public let maxProtection: SegmentProtection
    public let initialProtection: SegmentProtection
    public let flags: UInt32
    public let sections: [SectionInfo]
}

public struct SectionInfo: Sendable {
    public let name: String
    public let segmentName: String
    public let address: UInt64
    public let size: UInt64
    public let fileOffset: UInt32
    public let alignment: UInt32
    public let relocationOffset: UInt32
    public let relocationCount: UInt32
    public let flags: UInt32
}
