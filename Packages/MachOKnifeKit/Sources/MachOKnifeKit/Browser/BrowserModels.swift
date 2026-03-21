import Foundation

public struct BrowserDetailRow {
    public let key: String
    public let value: String
    public let dataPreview: String?
    public let rawAddress: UInt64?
    public let rvaAddress: UInt64?
    public let groupIdentifier: UInt

    public init(
        key: String,
        value: String,
        dataPreview: String? = nil,
        rawAddress: UInt64? = nil,
        rvaAddress: UInt64? = nil,
        groupIdentifier: UInt = 0
    ) {
        self.key = key
        self.value = value
        self.dataPreview = dataPreview
        self.rawAddress = rawAddress
        self.rvaAddress = rvaAddress
        self.groupIdentifier = groupIdentifier
    }
}

public struct BrowserDataRange {
    public let offset: Int
    public let length: Int

    public init(offset: Int, length: Int) {
        self.offset = offset
        self.length = length
    }
}

public enum BrowserNodeSummaryStyle {
    case automatic
    case group
    case representative
}

public final class BrowserNode {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let summaryStyle: BrowserNodeSummaryStyle
    public let rawAddress: UInt64?
    public let rvaAddress: UInt64?
    public let dataRange: BrowserDataRange?
    public let detailCount: Int
    public let childCount: Int

    private let detailProvider: (() -> [BrowserDetailRow])?
    private let indexedDetailProvider: ((Int) -> BrowserDetailRow)?
    private let childProvider: (() -> [BrowserNode])?
    private let indexedChildProvider: ((Int) -> BrowserNode)?
    private var cachedDetailRows: [BrowserDetailRow]?
    private var indexedDetailRows: [Int: BrowserDetailRow]
    private var cachedChildren: [BrowserNode]?
    private var indexedChildren: [Int: BrowserNode]

    public var detailRows: [BrowserDetailRow] {
        if let cachedDetailRows {
            return cachedDetailRows
        }

        let loadedRows: [BrowserDetailRow]
        if let detailProvider {
            loadedRows = detailProvider()
        } else if indexedDetailProvider != nil {
            loadedRows = (0..<detailCount).map { detailRow(at: $0) }
        } else {
            loadedRows = []
        }

        cachedDetailRows = loadedRows
        return loadedRows
    }

    public var loadedDetailRows: [BrowserDetailRow] {
        if let cachedDetailRows {
            return cachedDetailRows
        }
        return (0..<detailCount).compactMap { indexedDetailRows[$0] }
    }

    public var children: [BrowserNode] {
        if let cachedChildren {
            return cachedChildren
        }

        let loadedChildren: [BrowserNode]
        if let childProvider {
            loadedChildren = childProvider()
        } else if indexedChildProvider != nil {
            loadedChildren = (0..<childCount).map { child(at: $0) }
        } else {
            loadedChildren = []
        }
        cachedChildren = loadedChildren
        return loadedChildren
    }

    public var loadedChildren: [BrowserNode] {
        if let cachedChildren {
            return cachedChildren
        }
        return (0..<childCount).compactMap { indexedChildren[$0] }
    }

    public func child(at index: Int) -> BrowserNode {
        precondition(index >= 0 && index < childCount, "Child index out of range")

        if let cachedChildren {
            return cachedChildren[index]
        }
        if let cached = indexedChildren[index] {
            return cached
        }
        if let indexedChildProvider {
            let child = indexedChildProvider(index)
            indexedChildren[index] = child
            return child
        }
        let loadedChildren = childProvider?() ?? []
        cachedChildren = loadedChildren
        return loadedChildren[index]
    }

    public func detailRow(at index: Int) -> BrowserDetailRow {
        precondition(index >= 0 && index < detailCount, "Detail row index out of range")

        if let cachedDetailRows {
            return cachedDetailRows[index]
        }
        if let cached = indexedDetailRows[index] {
            return cached
        }
        if let indexedDetailProvider {
            let row = indexedDetailProvider(index)
            indexedDetailRows[index] = row
            return row
        }

        let loadedRows = detailProvider?() ?? []
        cachedDetailRows = loadedRows
        return loadedRows[index]
    }

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        summaryStyle: BrowserNodeSummaryStyle = .automatic,
        detailRows: [BrowserDetailRow] = [],
        detailCount: Int? = nil,
        detailProvider: (() -> [BrowserDetailRow])? = nil,
        indexedDetailProvider: ((Int) -> BrowserDetailRow)? = nil,
        children: [BrowserNode] = [],
        childCount: Int? = nil,
        childProvider: (() -> [BrowserNode])? = nil,
        indexedChildProvider: ((Int) -> BrowserNode)? = nil,
        rawAddress: UInt64? = nil,
        rvaAddress: UInt64? = nil,
        dataRange: BrowserDataRange? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.summaryStyle = summaryStyle
        self.rawAddress = rawAddress
        self.rvaAddress = rvaAddress
        self.dataRange = dataRange
        self.detailCount = detailCount ?? detailRows.count
        self.childCount = childCount ?? children.count
        self.detailProvider = detailProvider
        self.indexedDetailProvider = indexedDetailProvider
        self.childProvider = childProvider
        self.indexedChildProvider = indexedChildProvider
        self.cachedDetailRows = detailRows.isEmpty && (detailProvider != nil || indexedDetailProvider != nil) ? nil : detailRows
        self.indexedDetailRows = [:]
        self.cachedChildren = children.isEmpty && (childProvider != nil || indexedChildProvider != nil) ? nil : children
        self.indexedChildren = [:]
    }
}

public enum BrowserHexSource {
    case file(url: URL, size: Int)
    case unavailable(reason: String)
}

public struct BrowserHexRow {
    public let address: String
    public let lowBytes: String
    public let highBytes: String
    public let ascii: String

    public init(address: String, lowBytes: String, highBytes: String, ascii: String) {
        self.address = address
        self.lowBytes = lowBytes
        self.highBytes = highBytes
        self.ascii = ascii
    }
}

public struct BrowserDocument {
    public enum Kind: String {
        case machOFile
        case fatFile
        case dyldCache
        case fullDyldCache
        case memoryImage
    }

    public let sourceName: String
    public let kind: Kind
    public let rootNodes: [BrowserNode]
    public let hexSource: BrowserHexSource

    public init(sourceName: String, kind: Kind, rootNodes: [BrowserNode], hexSource: BrowserHexSource) {
        self.sourceName = sourceName
        self.kind = kind
        self.rootNodes = rootNodes
        self.hexSource = hexSource
    }
}
