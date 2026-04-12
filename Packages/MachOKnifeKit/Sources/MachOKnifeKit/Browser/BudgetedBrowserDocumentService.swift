import CoreMachO
import Foundation

private enum BudgetedBrowserConstants {
    static let symbolsPerPage = 200
    static let stringEntriesPerBatch = 256
}

private enum BudgetedBrowserError: Error {
    case missingRootNode
    case missingLegacySliceNode(Int)
    case missingLegacyGroup(String)
}

private final class DeferredLegacySectionNodeResolver {
    private let title: String
    private let sourceURL: URL
    private let sliceIndex: Int
    private let loader: (URL, Int, String) throws -> BrowserNode
    private var cachedNode: BrowserNode?
    private var cachedError: Error?

    init(
        title: String,
        sourceURL: URL,
        sliceIndex: Int,
        loader: @escaping (URL, Int, String) throws -> BrowserNode
    ) {
        self.title = title
        self.sourceURL = sourceURL
        self.sliceIndex = sliceIndex
        self.loader = loader
    }

    func node() throws -> BrowserNode {
        if let cachedNode {
            return cachedNode
        }
        if let cachedError {
            throw cachedError
        }

        do {
            let node = try loader(sourceURL, sliceIndex, title)
            cachedNode = node
            return node
        } catch {
            cachedError = error
            throw error
        }
    }
}

public extension BrowserDocumentService {
    func loadBudgeted(url: URL, scan: MachOMetadataScan) throws -> BrowserDocument {
        let analysis = try DocumentAnalysisService().analyze(scan: scan)
        let hexSource: BrowserHexSource = .file(url: url, size: scan.fileSize)

        switch scan.kind {
        case .thin:
            guard
                let analysisSlice = analysis.slices.first,
                let scanSlice = scan.slices.first
            else {
                throw BudgetedBrowserError.missingRootNode
            }

            return BrowserDocument(
                sourceName: url.lastPathComponent,
                kind: .machOFile,
                rootNodes: [
                    makeBudgetedSliceNode(
                        title: url.lastPathComponent,
                        analysisSlice: analysisSlice,
                        scanSlice: scanSlice,
                        sliceIndex: 0,
                        path: ["root"],
                        sourceURL: url,
                        hexSource: hexSource
                    ),
                ],
                hexSource: hexSource
            )
        case .fat:
            let sliceNodes = zip(analysis.slices, scan.slices).enumerated().map { index, pair in
                let (analysisSlice, scanSlice) = pair
                return makeBudgetedSliceNode(
                    title: "Slice \(index)",
                    analysisSlice: analysisSlice,
                    scanSlice: scanSlice,
                    sliceIndex: index,
                    path: ["fat", "slice", "\(index)"],
                    sourceURL: url,
                    hexSource: hexSource
                )
            }

            return BrowserDocument(
                sourceName: url.lastPathComponent,
                kind: .fatFile,
                rootNodes: [
                    BrowserNode(
                        id: "fat-root",
                        title: url.lastPathComponent,
                        subtitle: "Universal Mach-O",
                        summaryStyle: .group,
                        hexSource: hexSource,
                        detailRows: [
                            BrowserDetailRow(key: "Source File", value: url.path),
                            BrowserDetailRow(key: "Slices", value: "\(sliceNodes.count)"),
                            BrowserDetailRow(key: "Analysis Mode", value: "Budgeted large-file mode"),
                        ],
                        children: sliceNodes
                    ),
                ],
                hexSource: hexSource
            )
        }
    }

    private func makeBudgetedSliceNode(
        title: String,
        analysisSlice: SliceSummary,
        scanSlice: MachOMetadataSlice,
        sliceIndex: Int,
        path: [String],
        sourceURL: URL,
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        BrowserNode(
            id: path.joined(separator: "/"),
            title: title,
            subtitle: sliceSubtitle(for: analysisSlice),
            hexSource: hexSource,
            detailRows: [
                BrowserDetailRow(key: "Source File", value: sourceURL.path),
                BrowserDetailRow(key: "CPU Type", value: "\(analysisSlice.header.cpuType)"),
                BrowserDetailRow(key: "File Type", value: hex(analysisSlice.header.fileType)),
                BrowserDetailRow(key: "Load Commands", value: "\(analysisSlice.loadCommandCount)"),
                BrowserDetailRow(key: "Segments", value: "\(analysisSlice.segments.count)"),
                BrowserDetailRow(key: "Symbols", value: "\(analysisSlice.symbolCount)"),
                BrowserDetailRow(key: "Analysis Mode", value: "Budgeted large-file mode"),
            ],
            children: [
                makeBudgetedHeaderNode(slice: analysisSlice, scanSlice: scanSlice, path: path + ["header"], hexSource: hexSource),
                makeBudgetedLoadCommandsNode(slice: analysisSlice, path: path + ["loadCommands"], hexSource: hexSource),
                makeBudgetedDylibsNode(slice: analysisSlice, path: path + ["dylibs"], hexSource: hexSource),
                makeBudgetedRPathsNode(slice: analysisSlice, path: path + ["rpaths"], hexSource: hexSource),
                makeBudgetedSegmentsNode(
                    slice: analysisSlice,
                    sliceIndex: sliceIndex,
                    path: path + ["segments"],
                    sourceURL: sourceURL,
                    hexSource: hexSource
                ),
                makeBudgetedSectionsNode(
                    slice: analysisSlice,
                    sliceIndex: sliceIndex,
                    path: path + ["sections"],
                    sourceURL: sourceURL,
                    hexSource: hexSource
                ),
                makeBudgetedSymbolsNode(
                    sourceURL: sourceURL,
                    slice: analysisSlice,
                    scanSlice: scanSlice,
                    path: path + ["symbols"],
                    hexSource: hexSource
                ),
                makeBudgetedStringTablesNode(
                    sourceURL: sourceURL,
                    scanSlice: scanSlice,
                    path: path + ["stringTables"],
                    hexSource: hexSource
                ),
                makeDeferredLegacyGroupNode(
                    title: "Bindings",
                    subtitle: "Deferred until you expand this node",
                    path: path + ["bindings"],
                    hexSource: hexSource
                ) {
                    try loadLegacyHeavyGroup(
                        url: sourceURL,
                        sliceIndex: sliceIndex,
                        title: "Bindings"
                    )
                },
                makeDeferredLegacyGroupNode(
                    title: "Exports",
                    subtitle: "Deferred until you expand this node",
                    path: path + ["exports"],
                    hexSource: hexSource
                ) {
                    try loadLegacyHeavyGroup(
                        url: sourceURL,
                        sliceIndex: sliceIndex,
                        title: "Exports"
                    )
                },
                makeDeferredLegacyGroupNode(
                    title: "Fixups",
                    subtitle: "Deferred until you expand this node",
                    path: path + ["fixups"],
                    hexSource: hexSource
                ) {
                    try loadLegacyHeavyGroup(
                        url: sourceURL,
                        sliceIndex: sliceIndex,
                        title: "Fixups"
                    )
                },
            ]
        )
    }

    private func makeBudgetedHeaderNode(
        slice: SliceSummary,
        scanSlice: MachOMetadataSlice,
        path: [String],
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        let headerLength = scanSlice.header.is64Bit ? 32 : 28
        return BrowserNode(
            id: path.joined(separator: "/"),
            title: "Header",
            hexSource: hexSource,
            detailRows: [
                BrowserDetailRow(key: "CPU Type", value: "\(slice.header.cpuType)"),
                BrowserDetailRow(key: "CPU Subtype", value: "\(slice.header.cpuSubtype)"),
                BrowserDetailRow(key: "File Type", value: hex(slice.header.fileType)),
                BrowserDetailRow(key: "Number Of Commands", value: "\(slice.header.numberOfCommands)"),
                BrowserDetailRow(key: "Size Of Commands", value: "\(slice.header.sizeofCommands)"),
                BrowserDetailRow(key: "Flags", value: hex(slice.header.flags)),
                BrowserDetailRow(key: "Reserved", value: slice.header.reserved.map(hex) ?? "n/a"),
            ],
            rawAddress: UInt64(scanSlice.offset),
            dataRange: BrowserDataRange(offset: scanSlice.offset, length: headerLength)
        )
    }

    private func makeBudgetedLoadCommandsNode(
        slice: SliceSummary,
        path: [String],
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        BrowserNode(
            id: path.joined(separator: "/"),
            title: "Load Commands (\(slice.loadCommands.count))",
            summaryStyle: .group,
            hexSource: hexSource,
            detailCount: slice.loadCommands.count,
            indexedDetailProvider: { index in
                let command = slice.loadCommands[index]
                return BrowserDetailRow(
                    key: loadCommandName(for: command.command),
                    value: "offset=\(hex(UInt64(command.offset))) size=\(command.size)",
                    rawAddress: UInt64(command.offset),
                    groupIdentifier: UInt(index + 1)
                )
            },
            childCount: slice.loadCommands.count,
            indexedChildProvider: { index in
                let command = slice.loadCommands[index]
                return BrowserNode(
                    id: (path + ["\(index)"]).joined(separator: "/"),
                    title: "\(index). \(loadCommandName(for: command.command))",
                    subtitle: command.details.first?.value,
                    hexSource: hexSource,
                    detailRows: [
                        BrowserDetailRow(key: "Load Command", value: loadCommandName(for: command.command)),
                        BrowserDetailRow(key: "Offset", value: hex(UInt64(command.offset))),
                        BrowserDetailRow(key: "Command Size", value: "\(command.size)"),
                    ] + command.details.map {
                        BrowserDetailRow(key: $0.key, value: $0.value)
                    },
                    rawAddress: UInt64(command.offset),
                    dataRange: BrowserDataRange(offset: command.offset, length: Int(command.size))
                )
            }
        )
    }

    private func makeBudgetedDylibsNode(
        slice: SliceSummary,
        path: [String],
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        BrowserNode(
            id: path.joined(separator: "/"),
            title: "Dynamic Libraries",
            summaryStyle: .group,
            hexSource: hexSource,
            detailCount: slice.dylibReferences.count,
            indexedDetailProvider: { index in
                let dylib = slice.dylibReferences[index]
                return BrowserDetailRow(
                    key: loadCommandName(for: dylib.command),
                    value: dylib.path,
                    groupIdentifier: UInt(index + 1)
                )
            },
            childCount: slice.dylibReferences.count,
            indexedChildProvider: { index in
                let dylib = slice.dylibReferences[index]
                return BrowserNode(
                    id: (path + ["\(index)"]).joined(separator: "/"),
                    title: dylib.path,
                    hexSource: hexSource,
                    detailRows: [
                        BrowserDetailRow(key: "Command", value: loadCommandName(for: dylib.command)),
                        BrowserDetailRow(key: "Path", value: dylib.path),
                    ]
                )
            }
        )
    }

    private func makeBudgetedRPathsNode(
        slice: SliceSummary,
        path: [String],
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        BrowserNode(
            id: path.joined(separator: "/"),
            title: "RPaths",
            summaryStyle: .group,
            hexSource: hexSource,
            detailCount: slice.rpaths.count,
            indexedDetailProvider: { index in
                BrowserDetailRow(
                    key: "RPath \(index)",
                    value: slice.rpaths[index],
                    groupIdentifier: UInt(index + 1)
                )
            },
            childCount: slice.rpaths.count,
            indexedChildProvider: { index in
                BrowserNode(
                    id: (path + ["\(index)"]).joined(separator: "/"),
                    title: slice.rpaths[index],
                    hexSource: hexSource,
                    detailRows: [
                        BrowserDetailRow(key: "Path", value: slice.rpaths[index]),
                    ]
                )
            }
        )
    }

    private func makeBudgetedSegmentsNode(
        slice: SliceSummary,
        sliceIndex: Int,
        path: [String],
        sourceURL: URL,
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        BrowserNode(
            id: path.joined(separator: "/"),
            title: "Segments",
            summaryStyle: .group,
            hexSource: hexSource,
            childCount: slice.segments.count,
            indexedChildProvider: { index in
                let segment = slice.segments[index]
                return BrowserNode(
                    id: (path + ["\(index)"]).joined(separator: "/"),
                    title: segment.name,
                    subtitle: "sections=\(segment.sections.count)",
                    hexSource: hexSource,
                    detailRows: [
                        BrowserDetailRow(key: "VM Address", value: hex(segment.vmAddress)),
                        BrowserDetailRow(key: "VM Size", value: hex(segment.vmSize)),
                        BrowserDetailRow(key: "File Offset", value: hex(segment.fileOffset)),
                        BrowserDetailRow(key: "File Size", value: hex(segment.fileSize)),
                        BrowserDetailRow(key: "Max Protection", value: "\(segment.maxProtection)"),
                        BrowserDetailRow(key: "Initial Protection", value: "\(segment.initialProtection)"),
                        BrowserDetailRow(key: "Flags", value: hex(segment.flags)),
                    ],
                    childCount: segment.sections.count,
                    indexedChildProvider: { sectionIndex in
                        let section = segment.sections[sectionIndex]
                        return makeBudgetedSectionNode(
                            section: section,
                            sliceIndex: sliceIndex,
                            is64Bit: slice.is64Bit,
                            title: "\(section.segmentName).\(section.name)",
                            path: path + ["\(index)", "section", "\(sectionIndex)"],
                            sourceURL: sourceURL,
                            hexSource: hexSource
                        )
                    },
                    rawAddress: segment.fileOffset,
                    dataRange: dataRange(offset: segment.fileOffset, length: segment.fileSize)
                )
            }
        )
    }

    private func makeBudgetedSectionsNode(
        slice: SliceSummary,
        sliceIndex: Int,
        path: [String],
        sourceURL: URL,
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        let sections = slice.segments.flatMap(\.sections)
        return BrowserNode(
            id: path.joined(separator: "/"),
            title: "Sections",
            summaryStyle: .group,
            hexSource: hexSource,
            childCount: sections.count,
            indexedChildProvider: { index in
                let section = sections[index]
                return makeBudgetedSectionNode(
                    section: section,
                    sliceIndex: sliceIndex,
                    is64Bit: slice.is64Bit,
                    title: "\(section.segmentName).\(section.name)",
                    path: path + ["\(index)"],
                    sourceURL: sourceURL,
                    hexSource: hexSource
                )
            }
        )
    }

    private func makeBudgetedSectionNode(
        section: SectionSummary,
        sliceIndex: Int,
        is64Bit: Bool,
        title: String,
        path: [String],
        sourceURL: URL,
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        let baseDetailRows = [
            BrowserDetailRow(key: "Address", value: hex(section.address)),
            BrowserDetailRow(key: "Size", value: hex(section.size)),
            BrowserDetailRow(key: "File Offset", value: hex(UInt64(section.fileOffset))),
            BrowserDetailRow(key: "Alignment", value: "\(section.alignment)"),
            BrowserDetailRow(key: "Relocation Offset", value: hex(UInt64(section.relocationOffset))),
            BrowserDetailRow(key: "Relocation Count", value: "\(section.relocationCount)"),
            BrowserDetailRow(key: "Flags", value: hex(section.flags)),
        ]

        if let entryCount = deferredLegacySectionEntryCount(for: section, is64Bit: is64Bit) {
            return makeDeferredLegacySpecialSectionNode(
                section: section,
                sliceIndex: sliceIndex,
                title: title,
                path: path,
                sourceURL: sourceURL,
                hexSource: hexSource,
                baseDetailRows: deferredLegacySectionBaseDetailRows(for: section),
                entryCount: entryCount
            )
        }

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: title,
            subtitle: "size=\(hex(section.size))",
            hexSource: hexSource,
            detailRows: baseDetailRows,
            rawAddress: UInt64(section.fileOffset),
            dataRange: dataRange(offset: UInt64(section.fileOffset), length: section.size)
        )
    }

    private func deferredLegacySectionEntryCount(for section: SectionSummary, is64Bit: Bool) -> Int? {
        let pointerSizedSections: Set<String> = [
            "__objc_classlist",
            "__objc_nlclslist",
            "__objc_catlist",
            "__objc_nlcatlist",
            "__objc_classrefs",
            "__objc_superrefs",
            "__objc_selrefs",
        ]

        guard pointerSizedSections.contains(section.name) else {
            return nil
        }

        let pointerSize = is64Bit ? MemoryLayout<UInt64>.size : MemoryLayout<UInt32>.size
        guard pointerSize > 0 else { return nil }
        return Int(section.size) / pointerSize
    }

    private func deferredLegacySectionBaseDetailRows(for section: SectionSummary) -> [BrowserDetailRow] {
        [
            BrowserDetailRow(key: "Section Name", value: section.name),
            BrowserDetailRow(key: "Segment Name", value: section.segmentName),
            BrowserDetailRow(key: "Address", value: hex(section.address)),
            BrowserDetailRow(key: "Size", value: hex(section.size)),
            BrowserDetailRow(key: "Offset", value: hex(UInt64(section.fileOffset))),
            BrowserDetailRow(key: "Alignment", value: "\(section.alignment)"),
            BrowserDetailRow(key: "Type", value: hex(UInt64(section.flags))),
            BrowserDetailRow(key: "Attributes", value: hex(UInt64(section.flags))),
            BrowserDetailRow(key: "Indirect Symbol Index", value: "n/a"),
            BrowserDetailRow(key: "Indirect Symbol Count", value: "n/a"),
        ]
    }

    private func makeDeferredLegacySpecialSectionNode(
        section: SectionSummary,
        sliceIndex: Int,
        title: String,
        path: [String],
        sourceURL: URL,
        hexSource: BrowserHexSource,
        baseDetailRows: [BrowserDetailRow],
        entryCount: Int
    ) -> BrowserNode {
        let titleWithCount = entryCount > 0 ? "\(title) (\(entryCount))" : title
        let resolver = DeferredLegacySectionNodeResolver(
            title: title,
            sourceURL: sourceURL,
            sliceIndex: sliceIndex
        ) { sourceURL, sliceIndex, title in
            return try self.loadLegacySectionNode(
                url: sourceURL,
                sliceIndex: sliceIndex,
                title: title
            )
        }

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: titleWithCount,
            subtitle: "size=\(hex(section.size))",
            hexSource: hexSource,
            detailCount: baseDetailRows.count + entryCount,
            indexedDetailProvider: { index in
                if index < baseDetailRows.count {
                    return baseDetailRows[index]
                }

                do {
                    return try resolver.node().detailRow(at: index)
                } catch {
                    return BrowserDetailRow(
                        key: "Deferred Section Error",
                        value: error.localizedDescription
                    )
                }
            },
            childCount: entryCount,
            indexedChildProvider: { index in
                do {
                    return try resolver.node().child(at: index)
                } catch {
                    return self.makeDeferredFailureNode(
                        title: "\(title) Failed",
                        error: error,
                        path: path + ["error", "\(index)"],
                        hexSource: hexSource
                    )
                }
            },
            rawAddress: UInt64(section.fileOffset),
            dataRange: dataRange(offset: UInt64(section.fileOffset), length: section.size)
        )
    }

    private func makeBudgetedSymbolsNode(
        sourceURL: URL,
        slice: SliceSummary,
        scanSlice: MachOMetadataSlice,
        path: [String],
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        guard slice.symbolCount > 0 else {
            return BrowserNode(
                id: path.joined(separator: "/"),
                title: "Symbols",
                summaryStyle: .group,
                hexSource: hexSource,
                detailRows: [
                    BrowserDetailRow(key: "Status", value: "No symbols available"),
                ]
            )
        }

        let pageCount = Int(ceil(Double(slice.symbolCount) / Double(BudgetedBrowserConstants.symbolsPerPage)))
        let reader = MachOSymbolTablePageReader()

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: "Symbols",
            subtitle: "\(slice.symbolCount) symbols deferred",
            summaryStyle: .group,
            hexSource: hexSource,
            detailRows: [
                BrowserDetailRow(key: "Count", value: "\(slice.symbolCount)"),
                BrowserDetailRow(key: "Status", value: "Deferred pages"),
            ],
            childCount: pageCount,
            indexedChildProvider: { pageIndex in
                let startIndex = pageIndex * BudgetedBrowserConstants.symbolsPerPage
                let count = min(BudgetedBrowserConstants.symbolsPerPage, max(slice.symbolCount - startIndex, 0))
                return BrowserNode(
                    id: (path + ["page", "\(pageIndex)"]).joined(separator: "/"),
                    title: "Symbols \(startIndex)-\(startIndex + max(count - 1, 0))",
                    subtitle: "Deferred page",
                    summaryStyle: .group,
                    hexSource: hexSource,
                    detailRows: [
                        BrowserDetailRow(key: "Start Index", value: "\(startIndex)"),
                        BrowserDetailRow(key: "Page Size", value: "\(count)"),
                    ],
                    childCount: count,
                    childProvider: {
                        do {
                            let page = try reader.readPage(
                                url: sourceURL,
                                slice: scanSlice,
                                startIndex: startIndex,
                                maximumCount: count
                            )
                            return page.symbols.enumerated().map { offset, symbol in
                                makeBudgetedSymbolNode(
                                    symbol: symbol,
                                    index: startIndex + offset,
                                    path: path + ["page", "\(pageIndex)", "symbol", "\(startIndex + offset)"],
                                    hexSource: hexSource
                                )
                            }
                        } catch {
                            return Array(repeating: makeDeferredFailureNode(
                                title: "Failed to Load Symbols",
                                error: error,
                                path: path + ["page", "\(pageIndex)", "error"],
                                hexSource: hexSource
                            ), count: max(count, 1))
                        }
                    }
                )
            }
        )
    }

    private func makeBudgetedSymbolNode(
        symbol: SymbolInfo,
        index: Int,
        path: [String],
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        BrowserNode(
            id: path.joined(separator: "/"),
            title: symbol.name.isEmpty ? "Symbol \(index)" : symbol.name,
            hexSource: hexSource,
            detailRows: [
                BrowserDetailRow(key: "Name", value: symbol.name.isEmpty ? "(anonymous)" : symbol.name),
                BrowserDetailRow(key: "Type", value: hex(UInt64(symbol.type))),
                BrowserDetailRow(key: "Section", value: "\(symbol.sectionNumber)"),
                BrowserDetailRow(key: "Description", value: hex(UInt64(symbol.description))),
                BrowserDetailRow(key: "Value", value: hex(symbol.value)),
            ]
        )
    }

    private func makeBudgetedStringTablesNode(
        sourceURL: URL,
        scanSlice: MachOMetadataSlice,
        path: [String],
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        guard
            let symbolTable = scanSlice.symbolTable,
            symbolTable.stringTableSize > 0
        else {
            return BrowserNode(
                id: path.joined(separator: "/"),
                title: "String Tables",
                summaryStyle: .group,
                hexSource: hexSource,
                detailRows: [
                    BrowserDetailRow(key: "Status", value: "No string table available"),
                ]
            )
        }

        let reader = MachOStringTableBatchReader()
        let totalEntryCount = (try? reader.readBatch(
            url: sourceURL,
            slice: scanSlice,
            startIndex: 0,
            maximumCount: 1
        ).totalEntryCount) ?? 0
        let batchCount = totalEntryCount == 0
            ? 0
            : Int(ceil(Double(totalEntryCount) / Double(BudgetedBrowserConstants.stringEntriesPerBatch)))

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: "String Tables",
            subtitle: "\(symbolTable.stringTableSize) bytes deferred",
            summaryStyle: .group,
            hexSource: hexSource,
            detailRows: [
                BrowserDetailRow(key: "String Table Size", value: "\(symbolTable.stringTableSize)"),
                BrowserDetailRow(key: "Entry Count", value: "\(totalEntryCount)"),
                BrowserDetailRow(key: "Status", value: "Deferred batches"),
            ],
            childCount: batchCount,
            indexedChildProvider: { batchIndex in
                let startIndex = batchIndex * BudgetedBrowserConstants.stringEntriesPerBatch
                let count = min(BudgetedBrowserConstants.stringEntriesPerBatch, max(totalEntryCount - startIndex, 0))
                return BrowserNode(
                    id: (path + ["batch", "\(batchIndex)"]).joined(separator: "/"),
                    title: "String Table Batch \(startIndex)-\(startIndex + max(count - 1, 0))",
                    subtitle: "Deferred batch",
                    summaryStyle: .group,
                    hexSource: hexSource,
                    detailRows: [
                        BrowserDetailRow(key: "Start Index", value: "\(startIndex)"),
                        BrowserDetailRow(key: "Batch Size", value: "\(count)"),
                    ],
                    childCount: count,
                    childProvider: {
                        do {
                            let batch = try reader.readBatch(
                                url: sourceURL,
                                slice: scanSlice,
                                startIndex: startIndex,
                                maximumCount: count
                            )
                            return batch.entries.enumerated().map { offset, entry in
                                BrowserNode(
                                    id: (path + ["batch", "\(batchIndex)", "entry", "\(startIndex + offset)"]).joined(separator: "/"),
                                    title: entry.string.isEmpty ? "String \(startIndex + offset)" : entry.string,
                                    hexSource: hexSource,
                                    detailRows: [
                                        BrowserDetailRow(key: "Index", value: "\(entry.stringTableIndex)"),
                                        BrowserDetailRow(key: "Value", value: entry.string),
                                    ]
                                )
                            }
                        } catch {
                            return Array(repeating: makeDeferredFailureNode(
                                title: "Failed to Load String Table",
                                error: error,
                                path: path + ["batch", "\(batchIndex)", "error"],
                                hexSource: hexSource
                            ), count: max(count, 1))
                        }
                    }
                )
            }
        )
    }

    private func makeDeferredLegacyGroupNode(
        title: String,
        subtitle: String,
        path: [String],
        hexSource: BrowserHexSource,
        loader: @escaping () throws -> BrowserNode
    ) -> BrowserNode {
        BrowserNode(
            id: path.joined(separator: "/"),
            title: title,
            subtitle: subtitle,
            summaryStyle: .group,
            hexSource: hexSource,
            detailRows: [
                BrowserDetailRow(key: "Status", value: subtitle),
                BrowserDetailRow(key: "Mode", value: "Lazy legacy loader"),
            ],
            childCount: 1,
            childProvider: {
                do {
                    return [try loader()]
                } catch {
                    return [makeDeferredFailureNode(
                        title: "\(title) Failed",
                        error: error,
                        path: path + ["error"],
                        hexSource: hexSource
                    )]
                }
            }
        )
    }

    private func loadLegacyHeavyGroup(url: URL, sliceIndex: Int, title: String) throws -> BrowserNode {
        let document = try load(url: url)
        let sliceNode = try legacySliceNode(in: document, sliceIndex: sliceIndex)
        guard let groupNode = sliceNode.children.first(where: { $0.title == title }) else {
            throw BudgetedBrowserError.missingLegacyGroup(title)
        }
        return groupNode
    }

    private func loadLegacySectionNode(url: URL, sliceIndex: Int, title: String) throws -> BrowserNode {
        let document = try load(url: url)
        let sliceNode = try legacySliceNode(in: document, sliceIndex: sliceIndex)
        guard let sectionsNode = sliceNode.children.first(where: { $0.title == "Sections" }) else {
            throw BudgetedBrowserError.missingLegacyGroup("Sections")
        }

        guard let sectionNode = sectionsNode.children.first(where: {
            $0.title == title || $0.title.hasPrefix("\(title) (")
        }) else {
            throw BudgetedBrowserError.missingLegacyGroup(title)
        }

        return sectionNode
    }

    private func legacySliceNode(in document: BrowserDocument, sliceIndex: Int) throws -> BrowserNode {
        guard let rootNode = document.rootNodes.first else {
            throw BudgetedBrowserError.missingRootNode
        }

        if rootNode.children.contains(where: { $0.title == "Header" }) {
            return rootNode
        }

        if document.kind == .fatFile {
            if let imagesNode = rootNode.children.first(where: { $0.title == "Mach-O Images" }),
               imagesNode.childCount > sliceIndex {
                return imagesNode.child(at: sliceIndex)
            }
            throw BudgetedBrowserError.missingLegacySliceNode(sliceIndex)
        }

        if rootNode.childCount > sliceIndex {
            let candidate = rootNode.child(at: sliceIndex)
            if candidate.children.contains(where: { $0.title == "Header" }) {
                return candidate
            }
        }

        throw BudgetedBrowserError.missingLegacySliceNode(sliceIndex)
    }

    private func makeDeferredFailureNode(
        title: String,
        error: Error,
        path: [String],
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        BrowserNode(
            id: path.joined(separator: "/"),
            title: title,
            subtitle: String(describing: error),
            hexSource: hexSource,
            detailRows: [
                BrowserDetailRow(key: "Status", value: "Deferred load failed"),
                BrowserDetailRow(key: "Error", value: String(describing: error)),
                BrowserDetailRow(key: "Retry", value: "Re-expand the node after the underlying file becomes available."),
            ]
        )
    }

    private func sliceSubtitle(for slice: SliceSummary) -> String {
        [
            slice.is64Bit ? "64-bit" : "32-bit",
            "cpu=\(slice.header.cpuType)",
            "type=\(hex(slice.header.fileType))",
        ].joined(separator: " • ")
    }

    private func dataRange(offset: UInt64, length: UInt64) -> BrowserDataRange? {
        guard
            let normalizedOffset = Int(exactly: offset),
            let normalizedLength = Int(exactly: length),
            normalizedLength > 0
        else {
            return nil
        }

        return BrowserDataRange(offset: normalizedOffset, length: normalizedLength)
    }

    private func hex(_ value: UInt32) -> String {
        "0x" + String(value, radix: 16, uppercase: true)
    }

    private func hex(_ value: UInt64) -> String {
        "0x" + String(value, radix: 16, uppercase: true)
    }

    private func loadCommandName(for command: UInt32) -> String {
        switch command {
        case 0x1:
            "LC_SEGMENT"
        case 0x19:
            "LC_SEGMENT_64"
        case 0xD:
            "LC_ID_DYLIB"
        case 0xC:
            "LC_LOAD_DYLIB"
        case 0x80000018:
            "LC_LOAD_WEAK_DYLIB"
        case 0x8000001F:
            "LC_REEXPORT_DYLIB"
        case 0x8000001C:
            "LC_RPATH"
        case 0x24:
            "LC_VERSION_MIN_MACOSX"
        case 0x25:
            "LC_VERSION_MIN_IPHONEOS"
        case 0x26:
            "LC_FUNCTION_STARTS"
        case 0x29:
            "LC_DATA_IN_CODE"
        case 0x2B:
            "LC_DYLIB_CODE_SIGN_DRS"
        case 0x2C:
            "LC_ENCRYPTION_INFO_64"
        case 0x32:
            "LC_BUILD_VERSION"
        default:
            "LC_\(String(command, radix: 16, uppercase: true))"
        }
    }
}
