import CoreMachO
import Foundation
import MachOKit

public enum BrowserDocumentLoadError: LocalizedError, Equatable {
    case unsupportedFormat(URL)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(url):
            "\(url.lastPathComponent) is not a Mach-O file, universal binary, static library or dyld shared cache."
        }
    }
}

public struct BrowserDocumentService: Sendable {

    public init() {}

    public func load(url: URL) throws -> BrowserDocument {
        // MachOKit 的 `DyldCache(url:)` 用 `try!` 读取文件头：任何比 dyld_cache_header 短的文件
        // （小的目标文件、静态库、普通文本文件）都会直接让进程崩溃。先自行确认魔数和长度再交给 MachOKit。
        if Self.mayBeDyldCache(url: url) {
            if let document = try loadFullDyldCache(url: url) {
                return document
            }
            if let document = try loadDyldCache(url: url) {
                return document
            }
        }
        if let document = try MachOLayoutDocument.load(url: url) {
            return document
        }
        throw BrowserDocumentLoadError.unsupportedFormat(url)
    }

    public func loadMemoryImage(named name: String) throws -> BrowserDocument {
        guard let image = MachOImage(name: name) else {
            throw NSError(
                domain: "MachOKnifeKit.BrowserDocumentService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to locate the loaded Mach-O image named \(name)."]
            )
        }
        return BrowserDocument(
            sourceName: name,
            kind: .memoryImage,
            rootNodes: [makeMachONode(image, title: name, path: ["memory-image"])],
            hexSource: .unavailable(reason: "Hex view is unavailable for memory images in this pass.")
        )
    }

    /// 文件以 `dyld_` 开头且至少容纳一个完整的 dyld_cache_header 时才可能是 dyld 共享缓存。
    static func mayBeDyldCache(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer {
            try? handle.close()
        }
        guard let magic = try? handle.read(upToCount: 5), magic == Data("dyld_".utf8) else {
            return false
        }
        guard let size = try? handle.seekToEnd() else {
            return false
        }
        return size >= UInt64(DyldCacheHeader.layoutSize)
    }

    private func loadFullDyldCache(url: URL) throws -> BrowserDocument? {
        guard let cache = try? FullDyldCache(url: url) else {
            return nil
        }
        let size = (try? fileSize(url: url)) ?? 0

        return BrowserDocument(
            sourceName: url.lastPathComponent,
            kind: .fullDyldCache,
            rootNodes: [
                makeFullDyldCacheNode(cache, title: url.lastPathComponent, path: ["full-dyld-cache"]),
            ],
            hexSource: .file(url: url, size: size)
        )
    }

    private func loadDyldCache(url: URL) throws -> BrowserDocument? {
        guard let cache = try? DyldCache(url: url) else {
            return nil
        }
        let size = (try? fileSize(url: url)) ?? 0

        return BrowserDocument(
            sourceName: url.lastPathComponent,
            kind: .dyldCache,
            rootNodes: [
                makeDyldCacheNode(cache, title: url.lastPathComponent, path: ["dyld-cache"]),
            ],
            hexSource: .file(url: url, size: size)
        )
    }

    private func makeFullDyldCacheNode(_ cache: FullDyldCache, title: String, path: [String]) -> BrowserNode {
        var children = makeDyldCacheChildren(cache, path: path)
        let cacheFiles = cache.urls.enumerated().map { index, url in
            BrowserNode(
                id: (path + ["cache-files", "\(index)"]).joined(separator: "/"),
                title: url.lastPathComponent,
                subtitle: url.path,
                detailRows: [
                    .init(key: "path", value: url.path),
                ]
            )
        }
        children.insert(
            BrowserNode(
                id: (path + ["cache-files"]).joined(separator: "/"),
                title: "Cache Files",
                detailRows: [.init(key: "count", value: "\(cacheFiles.count)")],
                children: cacheFiles
            ),
            at: 1
        )

        if let symbolCache = try? cache.symbolCache {
            children.insert(
                makeDyldCacheNode(symbolCache, title: "Symbol Cache", path: path + ["symbol-cache"]),
                at: min(children.count, 2)
            )
        }

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: title,
            subtitle: "dyld_shared_cache",
            detailRows: makeDetailRows(cache),
            children: children
        )
    }

    private func makeDyldCacheNode(_ cache: some DyldCacheRepresentable, title: String, path: [String]) -> BrowserNode {
        BrowserNode(
            id: path.joined(separator: "/"),
            title: title,
            subtitle: "dyld_shared_cache",
            detailRows: makeDetailRows(cache),
            children: makeDyldCacheChildren(cache, path: path)
        )
    }

    private func makeDyldCacheChildren(_ cache: some DyldCacheRepresentable, path: [String]) -> [BrowserNode] {
        let mappingInfos = array(cache.mappingInfos)
        let mappingAndSlideInfos = array(cache.mappingAndSlideInfos)
        let imageInfos = array(cache.imageInfos)
        let imageTextInfos = array(cache.imageTextInfos)
        let subCaches = array(cache.subCaches)
        let dylibIndices = cache.dylibIndices
        let programOffsets = cache.programOffsets
        let tproMappings = array(cache.tproMappings)
        let images = dyldCacheMachOFiles(cache)

        return [
            makeGenericNode(title: "Header", value: cache.header, path: path + ["header"], depthLimit: 2),
            makeCollectionNode(title: "Mapping Infos", items: mappingInfos, path: path + ["mappingInfos"]) { index, _ in
                "Mapping \(index)"
            },
            makeCollectionNode(title: "Mapping And Slide Infos", items: mappingAndSlideInfos, path: path + ["mappingAndSlideInfos"]) { index, _ in
                "Mapping \(index)"
            },
            makeCollectionNode(title: "Image Infos", items: imageInfos, path: path + ["imageInfos"]) { index, info in
                dyldCacheImagePath(info, in: cache) ?? "Image \(index)"
            },
            makeCollectionNode(title: "Image Text Infos", items: imageTextInfos, path: path + ["imageTextInfos"]) { index, info in
                dyldCacheImageTextPath(info, in: cache) ?? "Text Image \(index)"
            },
            makeCollectionNode(title: "Sub Caches", items: subCaches, path: path + ["subCaches"]) { index, subCache in
                subCache.fileSuffix.isEmpty ? "Subcache \(index)" : subCache.fileSuffix
            },
            makeOptionalValueNode(title: "Local Symbols Info", value: cache.localSymbolsInfo, path: path + ["localSymbolsInfo"]),
            makeOptionalValueNode(title: "Dylibs Trie", value: cache.dylibsTrie, path: path + ["dylibsTrie"]),
            makeCollectionNode(title: "Dylib Indices", items: dylibIndices, path: path + ["dylibIndices"]) { _, entry in
                entry.name
            },
            makeOptionalValueNode(title: "Programs Trie", value: cache.programsTrie, path: path + ["programsTrie"]),
            makeCollectionNode(title: "Program Offsets", items: programOffsets, path: path + ["programOffsets"]) { _, entry in
                entry.name
            },
            makeOptionalValueNode(title: "Dylibs Prebuilt Loader Set", value: cache.dylibsPrebuiltLoaderSet, path: path + ["dylibsPrebuiltLoaderSet"]),
            makeOptionalValueNode(title: "Objective-C Optimization", value: cache.objcOptimization, path: path + ["objcOptimization"]),
            makeOptionalValueNode(title: "Legacy Objective-C Optimization", value: cache.oldObjcOptimization, path: path + ["oldObjcOptimization"]),
            makeOptionalValueNode(title: "Swift Optimization", value: cache.swiftOptimization, path: path + ["swiftOptimization"]),
            makeCollectionNode(title: "TPRO Mappings", items: tproMappings, path: path + ["tproMappings"]) { index, _ in
                "TPRO \(index)"
            },
            makeOptionalValueNode(title: "Function Variant Info", value: cache.functionVariantInfo, path: path + ["functionVariantInfo"]),
            makeOptionalValueNode(title: "Prewarming Data", value: cache.prewarmingData, path: path + ["prewarmingData"]),
            makeCollectionNode(title: "Mach-O Images", items: images, path: path + ["machOFiles"]) { index, machO in
                makeImageTitle(machO, fallback: "Image \(index)")
            },
            makeGenericNode(title: "Raw Object", value: cache, path: path + ["raw"], depthLimit: 2),
        ]
    }

    private func makeMachONode(
        _ machO: some MachORepresentable,
        title: String,
        path: [String],
        hexSource: BrowserHexSource? = nil
    ) -> BrowserNode {
        let loadCommands = Array(machO.loadCommands)
        let dependencies = machO.dependencies
        let rpaths = machO.rpaths
        let segments = machO.segments
        let sections = machO.sections
        let isRelocatableObject = machO.header.fileType == .object
        let indirectSymbols = isRelocatableObject ? [] : array(machO.indirectSymbols)
        let symbolStrings = isRelocatableObject ? [] : array(machO.symbolStrings)
        let cStrings = array(machO.cStrings)
        let allCStringTables = machO.allCStringTables
        let allCStrings = machO.allCStrings
        let uStrings = array(machO.uStrings)
        let cfStrings = array(machO.cfStrings)
        let rebaseOperations = isRelocatableObject ? [] : array(machO.rebaseOperations)
        let bindOperations = isRelocatableObject ? [] : array(machO.bindOperations)
        let weakBindOperations = isRelocatableObject ? [] : array(machO.weakBindOperations)
        let lazyBindOperations = isRelocatableObject ? [] : array(machO.lazyBindOperations)
        let exportTrie = isRelocatableObject ? [] : array(machO.exportTrie)
        let exportedSymbols = isRelocatableObject ? [] : machO.exportedSymbols
        let bindingSymbols = isRelocatableObject ? [] : machO.bindingSymbols
        let weakBindingSymbols = isRelocatableObject ? [] : machO.weakBindingSymbols
        let lazyBindingSymbols = isRelocatableObject ? [] : machO.lazyBindingSymbols
        let rebases = isRelocatableObject ? [] : machO.rebases
        let functionStarts = isRelocatableObject ? [] : array(machO.functionStarts)
        let dataInCode = isRelocatableObject ? [] : array(machO.dataInCode)
        let externalRelocations = isRelocatableObject ? [] : array(machO.externalRelocations)
        let classicBindingSymbols = isRelocatableObject ? [] : (canSafelyLoadClassicBindingSymbols(from: machO)
            ? (machO.classicBindingSymbols ?? [])
            : [])
        let classicLazyBindingSymbols = isRelocatableObject ? [] : (canSafelyLoadClassicBindingSymbols(from: machO)
            ? (machO.classicLazyBindingSymbols ?? [])
            : [])
        let sectionsBySegmentName = Dictionary(grouping: sections) { $0.segmentName }

        let stringTableNodes: [BrowserNode] = [
            makeCollectionNode(title: "Indirect Symbols", items: indirectSymbols, path: path + ["indirectSymbols"], hexSource: hexSource) { index, symbol in
                summarize(symbol).nonEmpty(or: "Indirect Symbol \(index)")
            },
            makeCollectionNode(title: "Symbol Strings", items: symbolStrings, path: path + ["symbolStrings"], hexSource: hexSource) { _, entry in
                entry.string
            },
            makeCollectionNode(title: "C Strings", items: cStrings, path: path + ["cStrings"], hexSource: hexSource) { _, entry in
                entry.string
            },
            makeCollectionNode(title: "All CString Tables", items: allCStringTables, path: path + ["allCStringTables"], hexSource: hexSource) { index, _ in
                "CString Table \(index)"
            },
            makeCollectionNode(title: "All C Strings", items: allCStrings, path: path + ["allCStrings"], hexSource: hexSource) { index, string in
                string.isEmpty ? "String \(index)" : string
            },
            makeCollectionNode(title: "UTF-16 Strings", items: uStrings, path: path + ["uStrings"], hexSource: hexSource) { _, entry in
                entry.string
            },
            makeCollectionNode(title: "CFStrings", items: cfStrings, path: path + ["cfStrings"], hexSource: hexSource) { index, string in
                summarize(string).nonEmpty(or: "CFString \(index)")
            },
            makeOptionalValueNode(title: "Embedded Info.plist", value: machO.embeddedInfoPlist, path: path + ["embeddedInfoPlist"], hexSource: hexSource),
        ]

        let bindingNodes: [BrowserNode] = [
            makeCollectionNode(title: "Rebase Operations", items: rebaseOperations, path: path + ["rebaseOperations"], hexSource: hexSource) { index, _ in
                "Rebase Op \(index)"
            },
            makeCollectionNode(title: "Bind Operations", items: bindOperations, path: path + ["bindOperations"], hexSource: hexSource) { index, _ in
                "Bind Op \(index)"
            },
            makeCollectionNode(title: "Weak Bind Operations", items: weakBindOperations, path: path + ["weakBindOperations"], hexSource: hexSource) { index, _ in
                "Weak Bind Op \(index)"
            },
            makeCollectionNode(title: "Lazy Bind Operations", items: lazyBindOperations, path: path + ["lazyBindOperations"], hexSource: hexSource) { index, _ in
                "Lazy Bind Op \(index)"
            },
            makeCollectionNode(title: "Binding Symbols", items: bindingSymbols, path: path + ["bindingSymbols"], hexSource: hexSource) { _, symbol in
                summarize(symbol).nonEmpty(or: "Binding Symbol")
            },
            makeCollectionNode(title: "Weak Binding Symbols", items: weakBindingSymbols, path: path + ["weakBindingSymbols"], hexSource: hexSource) { _, symbol in
                summarize(symbol).nonEmpty(or: "Weak Binding Symbol")
            },
            makeCollectionNode(title: "Lazy Binding Symbols", items: lazyBindingSymbols, path: path + ["lazyBindingSymbols"], hexSource: hexSource) { _, symbol in
                summarize(symbol).nonEmpty(or: "Lazy Binding Symbol")
            },
            makeCollectionNode(title: "Classic Binding Symbols", items: classicBindingSymbols, path: path + ["classicBindingSymbols"], hexSource: hexSource) { _, symbol in
                summarize(symbol).nonEmpty(or: "Classic Binding Symbol")
            },
            makeCollectionNode(title: "Classic Lazy Binding Symbols", items: classicLazyBindingSymbols, path: path + ["classicLazyBindingSymbols"], hexSource: hexSource) { _, symbol in
                summarize(symbol).nonEmpty(or: "Classic Lazy Binding Symbol")
            },
            makeCollectionNode(title: "Rebases", items: rebases, path: path + ["rebases"], hexSource: hexSource) { index, _ in
                "Rebase \(index)"
            },
        ]

        let exportNodes: [BrowserNode] = [
            makeCollectionNode(title: "Export Trie", items: exportTrie, path: path + ["exportTrie"], hexSource: hexSource) { _, entry in
                summarize(entry).nonEmpty(or: "Export Trie Entry")
            },
            makeCollectionNode(title: "Exported Symbols", items: exportedSymbols, path: path + ["exportedSymbols"], hexSource: hexSource) { _, symbol in
                summarize(symbol).nonEmpty(or: "Exported Symbol")
            },
        ]

        let fixupNodes: [BrowserNode] = [
            makeOptionalValueNode(title: "Dyld Chained Fixups", value: machO.dyldChainedFixups, path: path + ["dyldChainedFixups"], hexSource: hexSource),
            makeCollectionNode(title: "External Relocations", items: externalRelocations, path: path + ["externalRelocations"], hexSource: hexSource) { index, _ in
                "External Relocation \(index)"
            },
        ]

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: title,
            subtitle: machOSummary(for: machO),
            hexSource: hexSource,
            detailRows: makeMachORootDetailRows(machO),
            children: [
                makeGenericNode(title: "Header", value: machO.header, path: path + ["header"], depthLimit: 2, hexSource: hexSource),
                makeLoadCommandsNode(
                    loadCommands,
                    in: machO,
                    path: path + ["loadCommands"],
                    hexSource: hexSource
                ),
                makeIndexedSummaryNode(
                    id: (path + ["dependencies"]).joined(separator: "/"),
                    title: "Dynamic Libraries",
                    hexSource: hexSource,
                    childCount: dependencies.count,
                    childBuilder: { index in
                        let dependency = dependencies[index]
                        return makeGenericNode(
                            title: dependency.dylib.name,
                            value: dependency,
                            path: path + ["dependencies", "\(index)"],
                            depthLimit: 2,
                            hexSource: hexSource
                        )
                    }
                ),
                makeIndexedSummaryNode(
                    id: (path + ["rpaths"]).joined(separator: "/"),
                    title: "RPaths",
                    hexSource: hexSource,
                    childCount: rpaths.count,
                    childBuilder: { index in
                        let rpath = rpaths[index]
                        return BrowserNode(
                            id: (path + ["rpaths", "\(index)"]).joined(separator: "/"),
                            title: rpath,
                            hexSource: hexSource,
                            detailRows: [BrowserDetailRow(key: "Path", value: rpath)]
                        )
                    }
                ),
                makeIndexedSummaryNode(
                    id: (path + ["segments"]).joined(separator: "/"),
                    title: "Segments",
                    baseDetailRows: [],
                    hexSource: hexSource,
                    childCount: segments.count,
                    childBuilder: { index in
                        let segment = segments[index]
                        let segmentSections = sectionsBySegmentName[segment.segmentName] ?? []
                        return makeIndexedSummaryNode(
                            id: (path + ["segments", "\(index)"]).joined(separator: "/"),
                            title: segment.segmentName,
                            baseDetailRows: makeDetailRows(segment),
                            hexSource: hexSource,
                            childCount: segmentSections.count,
                            childBuilder: { sectionIndex in
                                let section = segmentSections[sectionIndex]
                                return makeGenericNode(
                                    title: "\(section.segmentName).\(section.sectionName)",
                                    value: section,
                                    path: path + ["segments", "\(index)", "sections", "\(sectionIndex)"],
                                    depthLimit: 2,
                                    hexSource: hexSource
                                )
                            }
                        )
                    }
                ),
                makeIndexedSummaryNode(
                    id: (path + ["sections"]).joined(separator: "/"),
                    title: "Sections",
                    hexSource: hexSource,
                    childCount: sections.count,
                    childBuilder: { index in
                        let section = sections[index]
                        return makeGenericNode(
                            title: "\(section.segmentName).\(section.sectionName)",
                            value: section,
                            path: path + ["sections", "\(index)"],
                            depthLimit: 2,
                            hexSource: hexSource
                        )
                    }
                ),
                makeIndexedSummaryNode(
                    id: (path + ["symbols"]).joined(separator: "/"),
                    title: "Symbols",
                    hexSource: hexSource,
                    childCount: isRelocatableObject ? 0 : machO.symbols.count,
                    childBuilder: { index in
                        let symbol = element(at: index, in: machO.symbols)
                        return makeGenericNode(
                            title: symbol.name.isEmpty ? "Symbol \(index)" : symbol.name,
                            value: symbol,
                            path: path + ["symbols", "\(index)"],
                            depthLimit: 2,
                            hexSource: hexSource
                        )
                    }
                ),
                makeSummaryNode(
                    id: (path + ["stringTables"]).joined(separator: "/"),
                    title: "String Tables",
                    hexSource: hexSource,
                    children: stringTableNodes
                ),
                makeSummaryNode(
                    id: (path + ["bindings"]).joined(separator: "/"),
                    title: "Bindings",
                    hexSource: hexSource,
                    children: bindingNodes
                ),
                makeSummaryNode(
                    id: (path + ["exports"]).joined(separator: "/"),
                    title: "Exports",
                    hexSource: hexSource,
                    children: exportNodes
                ),
                makeSummaryNode(
                    id: (path + ["fixups"]).joined(separator: "/"),
                    title: "Fixups",
                    hexSource: hexSource,
                    children: fixupNodes
                ),
                makeCollectionNode(title: "Function Starts", items: functionStarts, path: path + ["functionStarts"], hexSource: hexSource) { index, _ in
                    "Function Start \(index)"
                },
                makeCollectionNode(title: "Data In Code", items: dataInCode, path: path + ["dataInCode"], hexSource: hexSource) { index, _ in
                    "Data Entry \(index)"
                },
                makeOptionalValueNode(title: "Code Sign", value: machO.codeSign, path: path + ["codeSign"], hexSource: hexSource),
                makeGenericNode(title: "Raw Object", value: machO, path: path + ["raw"], depthLimit: 2, hexSource: hexSource),
            ]
        )
    }

    private func makeCollectionNode<T>(
        title: String,
        items: [T],
        path: [String],
        hexSource: BrowserHexSource? = nil,
        itemTitle: @escaping (Int, T) -> String
    ) -> BrowserNode {
        makeIndexedSummaryNode(
            id: path.joined(separator: "/"),
            title: title,
            hexSource: hexSource,
            childCount: items.count,
            childBuilder: { index in
                let item = items[index]
                return makeGenericNode(
                    title: itemTitle(index, item),
                    value: item,
                    path: path + ["\(index)"],
                    depthLimit: 2,
                    hexSource: hexSource
                )
            }
        )
    }

    private func makeLoadCommandsNode(
        _ loadCommands: [LoadCommand],
        in machO: some MachORepresentable,
        path: [String],
        hexSource: BrowserHexSource? = nil
    ) -> BrowserNode {
        let cache = LazyIndexedValueCache<BrowserNode>()

        func child(at index: Int) -> BrowserNode {
            if let cached = cache.values[index] {
                return cached
            }

            let node = makeLoadCommandNode(
                loadCommands[index],
                index: index,
                in: machO,
                path: path + ["\(index)"],
                hexSource: hexSource
            )
            cache.values[index] = node
            return node
        }

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: titleWithCount("Load Commands", count: loadCommands.count),
            summaryStyle: .group,
            hexSource: hexSource,
            detailCount: loadCommands.count,
            indexedDetailProvider: { index in
                let command = loadCommands[index]
                return BrowserDetailRow(
                    key: loadCommandDisplayName(command),
                    value: loadCommandSummaryValue(command, in: machO).nonEmpty(or: child(at: index).title),
                    rawAddress: child(at: index).rawAddress,
                    rvaAddress: child(at: index).rvaAddress,
                    groupIdentifier: UInt(index + 1)
                )
            },
            childCount: loadCommands.count,
            indexedChildProvider: child
        )
    }

    private func makeLoadCommandNode(
        _ command: LoadCommand,
        index: Int,
        in machO: some MachORepresentable,
        path: [String],
        hexSource: BrowserHexSource? = nil
    ) -> BrowserNode {
        let payload = associatedValue(of: command)
        let layout = payload.flatMap(loadCommandLayout)
        let relativeOffset = payload.flatMap(loadCommandOffset)
        let commandSize = loadCommandSize(payload) ?? 0
        let rawAddress = relativeOffset.flatMap { loadCommandRawAddress(relativeOffset: $0, in: machO) }

        let detailRows = makeLoadCommandDetailRows(
            command,
            in: machO,
            payload: payload,
            layout: layout,
            rawAddress: rawAddress
        )

        let children = layout.map {
            makeChildren(value: $0, path: path + ["layout"], depthLimit: 1, hexSource: hexSource)
        } ?? []

        let summaryValue = loadCommandSummaryValue(command, in: machO)
        let nodeTitle = loadCommandNodeTitle(command, in: machO, summaryValue: summaryValue)

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: nodeTitle,
            subtitle: summaryValue.isEmpty ? nil : summaryValue,
            summaryStyle: .representative,
            hexSource: hexSource,
            detailRows: detailRows,
            children: children,
            rawAddress: rawAddress,
            dataRange: rawAddress.flatMap { rawAddress in
                guard let offset = Int(exactly: rawAddress), commandSize > 0 else { return nil }
                return BrowserDataRange(offset: offset, length: commandSize)
            }
        )
    }

    private func makeLoadCommandDetailRows(
        _ command: LoadCommand,
        in machO: some MachORepresentable,
        payload: Any?,
        layout: Any?,
        rawAddress: UInt64?
    ) -> [BrowserDetailRow] {
        var rows: [BrowserDetailRow] = [
            BrowserDetailRow(
                key: "Load Command",
                value: loadCommandDisplayName(command),
                rawAddress: rawAddress,
                groupIdentifier: 1
            ),
        ]

        let decodedRows = loadCommandDecodedSummaryRows(command, in: machO)

        if let summaryValue = decodedRows.first?.value, summaryValue.isEmpty == false {
            rows.append(
                BrowserDetailRow(
                    key: decodedRows.first?.key ?? "Summary",
                    value: summaryValue,
                    rawAddress: rawAddress,
                    groupIdentifier: 1
                )
            )
        }

        rows.append(contentsOf: decodedRows.dropFirst().map {
            BrowserDetailRow(
                key: $0.key,
                value: $0.value,
                rawAddress: rawAddress,
                groupIdentifier: 1
            )
        })

        if let rawAddress {
            rows.append(
                BrowserDetailRow(
                    key: "Command RAW",
                    value: summarize(rawAddress, fieldName: "offset"),
                    rawAddress: rawAddress,
                    groupIdentifier: 1
                )
            )
        }

        if let offset = payload.flatMap(loadCommandOffset) {
            rows.append(
                BrowserDetailRow(
                    key: "Relative Offset",
                    value: summarize(UInt64(offset), fieldName: "offset"),
                    rawAddress: rawAddress,
                    groupIdentifier: 1
                )
            )
        }

        if let size = loadCommandSize(payload), size > 0 {
            rows.append(
                BrowserDetailRow(
                    key: "Command Size",
                    value: summarize(UInt64(size), fieldName: "size"),
                    rawAddress: rawAddress,
                    groupIdentifier: 1
                )
            )
        }

        if let layout {
            rows.append(contentsOf: makeDetailRows(layout).map {
                BrowserDetailRow(
                    key: $0.key,
                    value: $0.value,
                    dataPreview: $0.dataPreview,
                    rawAddress: $0.rawAddress ?? rawAddress,
                    rvaAddress: $0.rvaAddress,
                    groupIdentifier: 2
                )
            })
        } else if let payload {
            rows.append(contentsOf: makeDetailRows(payload).map {
                BrowserDetailRow(
                    key: $0.key,
                    value: $0.value,
                    dataPreview: $0.dataPreview,
                    rawAddress: $0.rawAddress ?? rawAddress,
                    rvaAddress: $0.rvaAddress,
                    groupIdentifier: 2
                )
            })
        }

        return rows
    }

    private func loadCommandNodeTitle(
        _ command: LoadCommand,
        in machO: some MachORepresentable,
        summaryValue: String
    ) -> String {
        let commandName = loadCommandDisplayName(command)
        let trimmedSummary = summaryValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSummary.isEmpty == false else {
            return commandName
        }

        switch command {
        case .loadDylib, .idDylib, .loadWeakDylib, .reexportDylib, .lazyLoadDylib, .loadUpwardDylib:
            let nodeSummary = loadCommandNodeSummary(summaryValue: trimmedSummary)
            return "\(commandName) \(nodeSummary)"
        default:
            return commandName
        }
    }

    private func loadCommandNodeSummary(summaryValue: String) -> String {
        let lastPathComponent = (summaryValue as NSString).lastPathComponent
        return lastPathComponent.nonEmpty(or: summaryValue)
    }

    private func loadCommandDisplayName(_ command: LoadCommand) -> String {
        let rawLabel = Mirror(reflecting: command).children.first?.label ?? String(describing: command)
        let words = rawLabel
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1_$2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Za-z])([0-9])", with: "$1_$2", options: .regularExpression)
            .replacingOccurrences(of: "([0-9])([A-Za-z])", with: "$1_$2", options: .regularExpression)
            .uppercased()
        return "LC_\(words)"
    }

    private func loadCommandSummaryValue(
        _ command: LoadCommand,
        in machO: some MachORepresentable
    ) -> String {
        loadCommandDecodedSummaryRows(command, in: machO).first?.value ?? ""
    }

    private func loadCommandDecodedSummaryRows(
        _ command: LoadCommand,
        in machO: some MachORepresentable
    ) -> [(key: String, value: String)] {
        switch command {
        case let .loadDylib(dylib),
             let .idDylib(dylib),
             let .loadWeakDylib(dylib),
             let .reexportDylib(dylib),
             let .lazyLoadDylib(dylib),
             let .loadUpwardDylib(dylib):
            guard let machO = machO as? MachOFile else { return [] }
            let library = dylib.dylib(in: machO)
            return [
                ("Library", library.name),
                ("Current Version", library.currentVersion.description),
                ("Compatibility Version", library.compatibilityVersion.description),
            ].filter { $0.value.isEmpty == false }
        case let .rpath(rpath):
            guard let machO = machO as? MachOFile else { return [] }
            return [("Path", rpath.path(in: machO))].filter { $0.value.isEmpty == false }
        case let .loadDylinker(dylinker),
             let .idDylinker(dylinker),
             let .dyldEnvironment(dylinker):
            guard let machO = machO as? MachOFile else { return [] }
            return [("Name", dylinker.name(in: machO))].filter { $0.value.isEmpty == false }
        case let .uuid(uuidCommand):
            return [("UUID", uuidCommand.uuid.uuidString)]
        case let .sourceVersion(sourceVersion):
            return [("Version", String(describing: sourceVersion.version))]
        case let .versionMinMacosx(versionMin),
             let .versionMinIphoneos(versionMin),
             let .versionMinTvos(versionMin),
             let .versionMinWatchos(versionMin):
            return [
                ("Minimum OS", String(describing: versionMin.version)),
                ("SDK", String(describing: versionMin.sdk)),
            ].filter { $0.value.isEmpty == false }
        case let .buildVersion(buildVersion):
            return [
                ("Platform", String(describing: buildVersion.platform)),
                ("Minimum OS", String(describing: buildVersion.minos)),
                ("SDK", String(describing: buildVersion.sdk)),
            ].filter { $0.value.isEmpty == false }
        case let .main(entryPoint):
            return [
                ("Entry Offset", summarize(entryPoint.layout.entryoff, fieldName: "entryoff")),
                ("Stack Size", summarize(entryPoint.layout.stacksize, fieldName: "stacksize")),
            ].filter { $0.value.isEmpty == false }
        default:
            return []
        }
    }

    private func associatedValue(of loadCommand: LoadCommand) -> Any? {
        Mirror(reflecting: loadCommand).children.first?.value
    }

    private func loadCommandLayout(_ payload: Any) -> Any? {
        Mirror(reflecting: payload).children.first(where: { $0.label == "layout" })?.value
    }

    private func loadCommandOffset(_ payload: Any) -> Int? {
        Mirror(reflecting: payload).children.first(where: { $0.label == "offset" })?.value as? Int
    }

    private func loadCommandSize(_ payload: Any?) -> Int? {
        guard let payload, let layout = loadCommandLayout(payload) else {
            return nil
        }
        if let cmdsize = Mirror(reflecting: layout).children.first(where: { $0.label == "cmdsize" })?.value {
            return numericValue(cmdsize).flatMap(Int.init)
        }
        return nil
    }

    private func loadCommandRawAddress(
        relativeOffset: Int,
        in machO: some MachORepresentable
    ) -> UInt64? {
        guard let machO = machO as? MachOFile else {
            return nil
        }
        return UInt64(machO.headerStartOffset + machO.cmdsStartOffset + relativeOffset)
    }

    private func makeIndexedSummaryNode(
        id: String,
        title: String,
        subtitle: String? = nil,
        baseDetailRows: [BrowserDetailRow] = [],
        hexSource: BrowserHexSource? = nil,
        childCount: Int,
        childBuilder: @escaping (Int) -> BrowserNode
    ) -> BrowserNode {
        let cache = LazyIndexedValueCache<BrowserNode>()

        func child(at index: Int) -> BrowserNode {
            if let cached = cache.values[index] {
                return cached
            }

            let node = childBuilder(index)
            cache.values[index] = node
            return node
        }

        return BrowserNode(
            id: id,
            title: title,
            subtitle: subtitle,
            summaryStyle: .group,
            hexSource: hexSource,
            detailCount: baseDetailRows.count + childCount,
            indexedDetailProvider: { index in
                if index < baseDetailRows.count {
                    return baseDetailRows[index]
                }
                return summaryDetailRow(for: child(at: index - baseDetailRows.count), groupIdentifier: UInt(index + 1))
            },
            childCount: childCount,
            indexedChildProvider: child
        )
    }

    private func makeSummaryNode(
        id: String,
        title: String,
        subtitle: String? = nil,
        baseDetailRows: [BrowserDetailRow] = [],
        hexSource: BrowserHexSource? = nil,
        children: [BrowserNode]
    ) -> BrowserNode {
        BrowserNode(
            id: id,
            title: title,
            subtitle: subtitle,
            summaryStyle: .group,
            hexSource: hexSource,
            detailCount: baseDetailRows.count + children.count,
            indexedDetailProvider: { index in
                if index < baseDetailRows.count {
                    return baseDetailRows[index]
                }
                return summaryDetailRow(for: children[index - baseDetailRows.count], groupIdentifier: UInt(index + 1))
            },
            children: children
        )
    }

    private func summaryDetailRow(for node: BrowserNode, groupIdentifier: UInt) -> BrowserDetailRow {
        let summaryStyle = switch node.summaryStyle {
        case .automatic:
            node.childCount > 0 ? BrowserNodeSummaryStyle.group : .representative
        case let style:
            style
        }

        if summaryStyle == .group {
            let summaryValue: String
            if let subtitle = node.subtitle, subtitle.isEmpty == false, subtitle != node.title {
                summaryValue = subtitle
            } else {
                summaryValue = node.childCount == 1 ? "1 item" : "\(node.childCount) items"
            }

            return BrowserDetailRow(
                key: node.title,
                value: summaryValue,
                rawAddress: node.rawAddress,
                rvaAddress: node.rvaAddress,
                groupIdentifier: groupIdentifier
            )
        }

        let detailCandidate = representativeDetailRow(for: node)
        return BrowserDetailRow(
            key: detailCandidate?.key ?? node.title,
            value: detailCandidate?.value ?? node.subtitle ?? node.title,
            dataPreview: detailCandidate?.dataPreview,
            rawAddress: detailCandidate?.rawAddress ?? node.rawAddress,
            rvaAddress: detailCandidate?.rvaAddress ?? node.rvaAddress,
            groupIdentifier: groupIdentifier
        )
    }

    private func representativeDetailRow(for node: BrowserNode) -> BrowserDetailRow? {
        guard node.detailCount > 0 else {
            return nil
        }

        let preferredIndex = (0..<node.detailCount).first { index in
            let key = normalizedFieldName(node.detailRow(at: index).key)
            return preferredSummaryFieldNames.contains(key)
        }
        if let preferredIndex {
            return node.detailRow(at: preferredIndex)
        }

        let fallbackIndex = (0..<node.detailCount).first { index in
            let key = normalizedFieldName(node.detailRow(at: index).key)
            return nonSummaryFieldNames.contains(key) == false
        } ?? 0

        return node.detailRow(at: fallbackIndex)
    }

    private func makeOptionalValueNode(title: String, value: Any?, path: [String], hexSource: BrowserHexSource? = nil) -> BrowserNode {
        guard let value else {
            return BrowserNode(
                id: path.joined(separator: "/"),
                title: title,
                hexSource: hexSource,
                detailRows: [.init(key: "status", value: "Not present")]
            )
        }

        return makeGenericNode(title: title, value: value, path: path, depthLimit: 2, hexSource: hexSource)
    }

    private func array<S: Sequence>(_ sequence: S?) -> [S.Element] {
        guard let sequence else { return [] }
        return Array(sequence)
    }

    private func dyldCacheImagePath(_ info: DyldCacheImageInfo, in cache: some DyldCacheRepresentable) -> String? {
        if let fullCache = cache as? FullDyldCache {
            return info.path(in: fullCache)
        }
        if let cache = cache as? DyldCache {
            return info.path(in: cache)
        }
        return nil
    }

    private func dyldCacheImageTextPath(_ info: DyldCacheImageTextInfo, in cache: some DyldCacheRepresentable) -> String? {
        if let fullCache = cache as? FullDyldCache {
            return info.path(in: fullCache)
        }
        if let cache = cache as? DyldCache {
            return info.path(in: cache)
        }
        return nil
    }

    private func dyldCacheMachOFiles(_ cache: some DyldCacheRepresentable) -> [MachOFile] {
        if let fullCache = cache as? FullDyldCache {
            return Array(fullCache.machOFiles())
        }
        if let cache = cache as? DyldCache {
            return Array(cache.machOFiles())
        }
        return []
    }

    private func canSafelyLoadClassicBindingSymbols(from machO: some MachORepresentable) -> Bool {
        guard machO.header.cpuType == .x86_64 else {
            return true
        }

        // MachOKit currently force-unwraps the first writable segment when
        // computing classic binding symbols for x86_64 images.
        return machO.segments.contains { $0.initialProtection.contains(.write) }
    }

    private func titleWithCount(_ title: String, count: Int) -> String {
        "\(title) (\(count))"
    }

    private func makeGenericNode(
        title: String,
        value: Any,
        path: [String],
        depthLimit: Int,
        hexSource: BrowserHexSource? = nil
    ) -> BrowserNode {
        let metadata = makeMetadata(for: value)
        let rows = makeDetailRows(value)
        let children: [BrowserNode]
        if depthLimit <= 0 {
            children = []
        } else {
            children = makeChildren(value: value, path: path, depthLimit: depthLimit - 1, hexSource: hexSource)
        }

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: title,
            subtitle: rows.first?.value,
            summaryStyle: .representative,
            hexSource: hexSource,
            detailRows: rows,
            children: children,
            rawAddress: metadata.rawAddress,
            rvaAddress: metadata.rvaAddress,
            dataRange: metadata.dataRange
        )
    }

    private func makeChildren(
        value: Any,
        path: [String],
        depthLimit: Int,
        hexSource: BrowserHexSource? = nil
    ) -> [BrowserNode] {
        if let fields = specializedFields(for: value) {
            return fields.enumerated().map { index, field in
                makeGenericNode(
                    title: field.key,
                    value: field.value,
                    path: path + [field.key.nonEmpty(or: "\(index)")],
                    depthLimit: depthLimit,
                    hexSource: hexSource
                )
            }
        }

        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .collection, .set:
            return mirror.children.enumerated().map { index, child in
                makeGenericNode(
                    title: child.label ?? "[\(index)]",
                    value: child.value,
                    path: path + ["\(index)"],
                    depthLimit: depthLimit,
                    hexSource: hexSource
                )
            }
        case .dictionary:
            return mirror.children.enumerated().map { index, child in
                makeGenericNode(
                    title: child.label ?? "Entry \(index)",
                    value: child.value,
                    path: path + ["\(index)"],
                    depthLimit: depthLimit,
                    hexSource: hexSource
                )
            }
        case .optional:
            guard let child = mirror.children.first else { return [] }
            return [
                makeGenericNode(
                    title: child.label ?? "value",
                    value: child.value,
                    path: path + ["wrapped"],
                    depthLimit: depthLimit,
                    hexSource: hexSource
                ),
            ]
        case .class, .struct, .tuple, .enum:
            return mirror.children.enumerated().map { index, child in
                makeGenericNode(
                    title: child.label ?? "Field \(index)",
                    value: child.value,
                    path: path + [child.label ?? "\(index)"],
                    depthLimit: depthLimit,
                    hexSource: hexSource
                )
            }
        case .none:
            return []
        case .foreignReference:
            return []
        @unknown default:
            return []
        }
    }

    private func makeDetailRows(_ value: Any) -> [BrowserDetailRow] {
        if let fields = specializedFields(for: value) {
            return fields.map { field in
                BrowserDetailRow(
                    key: field.key,
                    value: summarize(field.value, fieldName: field.key),
                    dataPreview: detailDataPreview(for: field.value),
                    rawAddress: rawAddress(forFieldNamed: field.key, value: field.value),
                    rvaAddress: rvaAddress(forFieldNamed: field.key, value: field.value),
                    groupIdentifier: 1
                )
            }
        }

        let mirror = Mirror(reflecting: value)

        if mirror.children.isEmpty {
            return [
                BrowserDetailRow(
                    key: "Value",
                    value: summarize(value),
                    dataPreview: detailDataPreview(for: value)
                )
            ]
        }

        return mirror.children.enumerated().map { index, child in
            let label = child.label ?? "field\(index)"
            return BrowserDetailRow(
                key: displayLabel(forFieldNamed: label),
                value: summarize(child.value, fieldName: label),
                dataPreview: detailDataPreview(for: child.value),
                rawAddress: rawAddress(forFieldNamed: label, value: child.value),
                rvaAddress: rvaAddress(forFieldNamed: label, value: child.value),
                groupIdentifier: 1
            )
        }
    }

    private func makeMetadata(for value: Any) -> BrowserNodeMetadata {
        if let fields = specializedFields(for: value) {
            let rawAddressValue = fields.lazy.compactMap { rawAddress(forFieldNamed: $0.key, value: $0.value) }.first
            let rvaAddressValue = fields.lazy.compactMap { rvaAddress(forFieldNamed: $0.key, value: $0.value) }.first
            let size = fields.lazy.compactMap { byteSize(forFieldNamed: $0.key, value: $0.value) }.first

            let dataRange: BrowserDataRange?
            if let rawAddressValue, let size, size > 0, let offset = Int(exactly: rawAddressValue), let length = Int(exactly: size) {
                dataRange = BrowserDataRange(offset: offset, length: length)
            } else {
                dataRange = nil
            }

            return BrowserNodeMetadata(rawAddress: rawAddressValue, rvaAddress: rvaAddressValue, dataRange: dataRange)
        }

        let mirror = Mirror(reflecting: value)
        var rawAddressValue: UInt64?
        var rvaAddressValue: UInt64?
        var size: UInt64?

        for child in mirror.children {
            guard let label = child.label else { continue }
            rawAddressValue = rawAddressValue ?? rawAddress(forFieldNamed: label, value: child.value)
            rvaAddressValue = rvaAddressValue ?? rvaAddress(forFieldNamed: label, value: child.value)
            size = size ?? byteSize(forFieldNamed: label, value: child.value)
        }

        let dataRange: BrowserDataRange?
        if let rawAddressValue, let size, size > 0, let offset = Int(exactly: rawAddressValue), let length = Int(exactly: size) {
            dataRange = BrowserDataRange(offset: offset, length: length)
        } else {
            dataRange = nil
        }

        return BrowserNodeMetadata(rawAddress: rawAddressValue, rvaAddress: rvaAddressValue, dataRange: dataRange)
    }

    private func rawAddress(forFieldNamed label: String, value: Any) -> UInt64? {
        let normalized = normalizedFieldName(label)
        guard rawAddressFieldNames.contains(normalized) else { return nil }
        return numericValue(value)
    }

    private func rvaAddress(forFieldNamed label: String, value: Any) -> UInt64? {
        let normalized = normalizedFieldName(label)
        guard rvaAddressFieldNames.contains(normalized) else { return nil }
        return numericValue(value)
    }

    private func byteSize(forFieldNamed label: String, value: Any) -> UInt64? {
        let normalized = normalizedFieldName(label)
        guard byteSizeFieldNames.contains(normalized) else { return nil }
        return numericValue(value)
    }

    private func normalizedFieldName(_ label: String) -> String {
        label.lowercased().replacingOccurrences(of: "_", with: "")
    }

    private var preferredSummaryFieldNames: Set<String> {
        [
            "name",
            "path",
            "segmentname",
            "sectionname",
            "categoryname",
            "classname",
            "objectcclassmethodname",
            "objectcmethodname",
            "objectcmethodtype",
            "objectcclassname",
            "string",
            "value",
        ]
    }

    private var nonSummaryFieldNames: Set<String> {
        rawAddressFieldNames
            .union(rvaAddressFieldNames)
            .union(byteSizeFieldNames)
            .union([
                "offset",
                "alignment",
                "flags",
                "attributes",
                "listentryraw",
                "nlist",
            ])
    }

    private func numericValue(_ value: Any) -> UInt64? {
        switch value {
        case let value as UInt8:
            return UInt64(value)
        case let value as UInt16:
            return UInt64(value)
        case let value as UInt32:
            return UInt64(value)
        case let value as UInt64:
            return value
        case let value as Int8:
            return value < 0 ? nil : UInt64(value)
        case let value as Int16:
            return value < 0 ? nil : UInt64(value)
        case let value as Int32:
            return value < 0 ? nil : UInt64(value)
        case let value as Int64:
            return value < 0 ? nil : UInt64(value)
        case let value as Int:
            return value < 0 ? nil : UInt64(value)
        default:
            return nil
        }
    }

    private func summarize(_ value: Any, fieldName: String? = nil) -> String {
        let optionalMirror = Mirror(reflecting: value)
        if optionalMirror.displayStyle == .optional {
            guard let wrapped = optionalMirror.children.first?.value else {
                return "Not present"
            }
            return summarize(wrapped, fieldName: fieldName)
        }

        if let semantic = semanticSummary(for: value) {
            return semantic
        }

        if let fieldName, let numericValue = numericValue(value) {
            let normalized = normalizedFieldName(fieldName)
            if rawAddressFieldNames.contains(normalized)
                || rvaAddressFieldNames.contains(normalized)
                || byteSizeFieldNames.contains(normalized)
                || normalized.contains("flags")
                || normalized.contains("offset")
                || normalized.contains("address")
                || normalized.contains("size")
            {
                return String(format: "0x%llX (%llu)", numericValue, numericValue)
            }
        }

        if let string = value as? String {
            return string
        }
        if let string = value as? Substring {
            return String(string)
        }
        if let url = value as? URL {
            return url.path
        }
        if let data = value as? Data {
            return "\(data.count) bytes"
        }

        let description = String(describing: value)
        if description.count <= 160 {
            return description
        }
        return String(description.prefix(157)) + "..."
    }

    private func specializedFields(for value: Any) -> [BrowserField]? {
        if let header = value as? MachHeader {
            return [
                .init(key: "Magic", value: header.magic as Any),
                .init(key: "CPU Type", value: header.cpuType as Any),
                .init(key: "CPU Subtype", value: header.cpuSubType as Any),
                .init(key: "File Type", value: header.fileType as Any),
                .init(key: "Number Of Commands", value: Int(header.layout.ncmds)),
                .init(key: "Size Of Commands", value: Int(header.layout.sizeofcmds)),
                .init(key: "Flags", value: header.flags),
            ]
        }

        if let segment = value as? any SegmentCommandProtocol {
            return [
                .init(key: "Segment Name", value: segment.segmentName),
                .init(key: "VM Address", value: segment.virtualMemoryAddress),
                .init(key: "VM Size", value: segment.virtualMemorySize),
                .init(key: "File Offset", value: segment.fileOffset),
                .init(key: "File Size", value: segment.fileSize),
                .init(key: "Max Protection", value: segment.maxProtection),
                .init(key: "Initial Protection", value: segment.initialProtection),
                .init(key: "Number Of Sections", value: segment.numberOfSections),
                .init(key: "Flags", value: segment.flags),
            ]
        }

        if let section = value as? any SectionProtocol {
            return [
                .init(key: "Section Name", value: section.sectionName),
                .init(key: "Segment Name", value: section.segmentName),
                .init(key: "Address", value: section.address),
                .init(key: "Size", value: section.size),
                .init(key: "Offset", value: section.offset),
                .init(key: "Alignment", value: section.align),
                .init(key: "Type", value: section.flags.type as Any),
                .init(key: "Attributes", value: section.flags.attributes),
                .init(key: "Indirect Symbol Index", value: section.indirectSymbolIndex as Any),
                .init(key: "Indirect Symbol Count", value: section.numberOfIndirectSymbols as Any),
            ]
        }

        if let symbol = value as? any SymbolProtocol {
            return [
                .init(key: "Name", value: symbol.name),
                .init(key: "Offset", value: symbol.offset),
                .init(key: "Nlist", value: symbol.nlist),
            ]
        }

        return nil
    }

    private func semanticSummary(for value: Any) -> String? {
        switch value {
        case let value as Magic:
            return formatSemanticValue(value.description, raw: UInt64(value.rawValue))
        case let value as CPUType:
            return formatSemanticValue(value.description, raw: UInt64(bitPattern: Int64(value.rawValue)))
        case let value as CPUSubType:
            return formatSemanticValue(value.description, raw: UInt64(bitPattern: Int64(value.rawValue)))
        case let value as FileType:
            return formatSemanticValue(value.description, raw: UInt64(value.rawValue))
        case let value as VMProtection:
            return formatSemanticValue(String(describing: value), raw: UInt64(bitPattern: Int64(value.rawValue)))
        case let value as MachHeader.Flags:
            return formatSemanticValue(String(describing: value), raw: UInt64(value.rawValue))
        case let value as SegmentCommandFlags:
            return formatSemanticValue(String(describing: value), raw: UInt64(value.rawValue))
        case let value as SectionFlags:
            return formatSemanticValue(sectionFlagsDescription(value), raw: UInt64(value.rawValue))
        case let value as SectionAttributes:
            return formatSemanticValue(String(describing: value), raw: UInt64(value.rawValue))
        case let value as SectionType:
            return formatSemanticValue(String(describing: value), raw: UInt64(bitPattern: Int64(value.rawValue)))
        default:
            return nil
        }
    }

    private func formatSemanticValue(_ description: String, raw: UInt64) -> String {
        let normalized = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return String(format: "0x%llX (%llu)", raw, raw)
        }
        return "\(normalized) (0x\(String(raw, radix: 16, uppercase: true)) / \(raw))"
    }

    private func sectionFlagsDescription(_ value: SectionFlags) -> String {
        let type = value.type.map(String.init(describing:)) ?? "Unknown"
        let attributes = String(describing: value.attributes)
        if attributes == "SectionAttributes(rawValue: 0)" || attributes == "[]" {
            return type
        }
        return "\(type) | \(attributes)"
    }

    private func displayLabel(forFieldNamed label: String) -> String {
        let normalized = label.replacingOccurrences(of: "_", with: " ")
        let separated = normalized.unicodeScalars.reduce(into: "") { partialResult, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar), partialResult.isEmpty == false {
                partialResult.append(" ")
            }
            partialResult.append(String(scalar))
        }
        return separated
            .split(separator: " ")
            .map { word in
                let text = String(word)
                return text.count <= 3 ? text.uppercased() : text.prefix(1).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
    }

    private func detailDataPreview(for value: Any) -> String? {
        let data: Data?

        switch value {
        case let value as Data:
            data = value
        case let value as String:
            data = value.data(using: .utf8)
        case let value as Substring:
            data = String(value).data(using: .utf8)
        case let value as UUID:
            data = withUnsafeBytes(of: value.uuid) { Data($0) }
        case let value as UInt8:
            data = Data([value])
        case let value as UInt16:
            data = withUnsafeBytes(of: value.littleEndian) { Data($0) }
        case let value as UInt32:
            data = withUnsafeBytes(of: value.littleEndian) { Data($0) }
        case let value as UInt64:
            data = withUnsafeBytes(of: value.littleEndian) { Data($0) }
        case let value as Int8:
            data = withUnsafeBytes(of: value.littleEndian) { Data($0) }
        case let value as Int16:
            data = withUnsafeBytes(of: value.littleEndian) { Data($0) }
        case let value as Int32:
            data = withUnsafeBytes(of: value.littleEndian) { Data($0) }
        case let value as Int64:
            data = withUnsafeBytes(of: value.littleEndian) { Data($0) }
        case let value as Int:
            data = withUnsafeBytes(of: value.littleEndian) { Data($0) }
        default:
            data = nil
        }

        guard let data, data.isEmpty == false else { return nil }
        return data
            .prefix(16)
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
    }

    private func makeImageTitle(_ machO: some MachORepresentable, fallback: String) -> String {
        if let machO = machO as? MachOFile {
            return machO.imagePath
        }
        if let machO = machO as? MachOImage, let path = machO.path, !path.isEmpty {
            return path
        }
        if let name = Mirror(reflecting: machO).children.first(where: { $0.label == "name" })?.value as? String, !name.isEmpty {
            return name
        }
        return fallback
    }

    private func makeMachORootDetailRows(_ machO: some MachORepresentable) -> [BrowserDetailRow] {
        let headerRows = makeDetailRows(machO.header).map {
            BrowserDetailRow(
                key: $0.key,
                value: $0.value,
                dataPreview: $0.dataPreview,
                rawAddress: $0.rawAddress,
                rvaAddress: $0.rvaAddress,
                groupIdentifier: 1
            )
        }

        let statsRows: [BrowserDetailRow] = [
            .init(key: "Load Commands", value: "\(Array(machO.loadCommands).count)", groupIdentifier: 2),
            .init(key: "Segments", value: "\(machO.segments.count)", groupIdentifier: 2),
            .init(key: "Sections", value: "\(machO.sections.count)", groupIdentifier: 2),
            .init(key: "Symbols", value: machO.header.fileType == .object ? "Object file symbols available on demand" : "\(machO.symbols.count)", groupIdentifier: 2),
            .init(key: "64-Bit", value: machO.is64Bit ? "true" : "false", groupIdentifier: 2),
        ]

        return headerRows + statsRows
    }

    private func machOSummary(for machO: some MachORepresentable) -> String {
        let header = machO.header
        return [
            summarize(header.magic as Any, fieldName: "Magic"),
            summarize(header.cpuType as Any, fieldName: "CPU Type"),
            summarize(header.cpuSubType as Any, fieldName: "CPU Subtype"),
            summarize(header.fileType as Any, fieldName: "File Type"),
        ]
        .filter { !$0.isEmpty && $0 != "Not present" }
        .joined(separator: "  •  ")
    }

    private func fileSize(url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize ?? 0
    }

    private func element<C: Collection>(at position: Int, in collection: C) -> C.Element {
        collection[collection.index(collection.startIndex, offsetBy: position)]
    }
}

private struct BrowserNodeMetadata {
    let rawAddress: UInt64?
    let rvaAddress: UInt64?
    let dataRange: BrowserDataRange?
}

private final class LazyIndexedValueCache<Value> {
    var values: [Int: Value] = [:]
}

private struct BrowserField {
    let key: String
    let value: Any
}

private let rawAddressFieldNames: Set<String> = [
    "offset",
    "off",
    "fileoffset",
    "fileoff",
    "dataoffset",
    "dataoff",
    "symboloffset",
    "symoff",
    "stringtableoffset",
    "stroff",
    "relocationoffset",
    "reloff",
    "indirectsymboloffset",
    "indirectsymoff",
    "moduletableoffset",
    "extrefsymoff",
    "tocoff",
    "modtaboff",
    "extreloff",
    "locreloff",
    "rebaseoff",
    "bindoff",
    "weakbindoff",
    "lazybindoff",
    "exportoff",
    "cryptoffset",
]

private let rvaAddressFieldNames: Set<String> = [
    "address",
    "vmaddress",
    "vmaddr",
]

private let byteSizeFieldNames: Set<String> = [
    "size",
    "count",
    "filesize",
    "datasize",
    "vmsize",
    "cmdsize",
    "ncmds",
    "nsects",
    "nsyms",
    "stringtablesize",
    "strsize",
    "indirectsymbolcount",
    "indirectsyms",
    "rebasesize",
    "bindsize",
    "weakbindsize",
    "lazybindsize",
    "exportsize",
    "cryptsize",
]

private extension String {
    func nonEmpty(or fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
