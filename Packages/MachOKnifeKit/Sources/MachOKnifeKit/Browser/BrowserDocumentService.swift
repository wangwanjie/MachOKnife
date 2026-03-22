import CoreMachO
import Foundation
import MachOKit

public struct BrowserDocumentService: Sendable {
    private let archiveInspector = ArchiveInspector()

    public init() {}

    public func load(url: URL) throws -> BrowserDocument {
        if let document = try loadFullDyldCache(url: url) {
            return document
        }
        if let document = try loadDyldCache(url: url) {
            return document
        }
        if let archiveInspection = try archiveInspector.inspect(url: url) {
            return try loadArchive(url: url, inspection: archiveInspection)
        }

        let loaded = try MachOKit.loadFromFile(url: url)
        let size = (try? fileSize(url: url)) ?? 0
        let hexSource: BrowserHexSource = .file(url: url, size: size)

        switch loaded {
        case let .machO(machO):
            if machO.header.fileType == .dylib {
                return BrowserDocument(
                    sourceName: url.lastPathComponent,
                    kind: .machOFile,
                    rootNodes: [makeDylibContainerNode(machO, sourceURL: url, hexSource: hexSource)],
                    hexSource: hexSource
                )
            }
            return BrowserDocument(
                sourceName: url.lastPathComponent,
                kind: .machOFile,
                rootNodes: [makeMachONode(
                    machO,
                    title: url.lastPathComponent,
                    path: ["root"],
                    fileBackedMachO: machO,
                    sourceURL: url,
                    hexSource: hexSource
                )],
                hexSource: hexSource
            )
        case let .fat(fat):
            return BrowserDocument(
                sourceName: url.lastPathComponent,
                kind: .fatFile,
                rootNodes: [makeFatNode(fat, sourceURL: url, title: url.lastPathComponent, hexSource: hexSource)],
                hexSource: hexSource
            )
        }
    }

    private func loadArchive(url: URL, inspection: ArchiveInspection) throws -> BrowserDocument {
        let rootChildren = try inspection.architectures.map { architecture in
            let extraction = try archiveInspector.extractThinArchive(url: url, preferredArchitecture: architecture)
            return try makeArchiveArchitectureNode(
                architecture: extraction.architecture,
                thinArchiveURL: extraction.archiveURL,
                sourceURL: url,
                path: ["archive", extraction.architecture]
            )
        }
        let size = (try? fileSize(url: url)) ?? 0
        let rootTitle = switch inspection.kind {
        case .archive:
            "Static Library"
        case .fatArchive:
            "Fat Archive"
        }
        let rootDetailRows: [BrowserDetailRow] = [
            .init(key: "Source File", value: url.path, groupIdentifier: 1),
            .init(key: "Container", value: rootTitle, groupIdentifier: 1),
            .init(key: "Targets", value: "\(rootChildren.count)", groupIdentifier: 1),
        ]

        return BrowserDocument(
            sourceName: url.lastPathComponent,
            kind: .archive,
            rootNodes: [
                BrowserNode(
                    id: "archive-root",
                    title: rootTitle,
                    subtitle: url.lastPathComponent,
                    summaryStyle: .group,
                    detailRows: rootDetailRows,
                    children: rootChildren
                ),
            ],
            hexSource: .file(url: url, size: size)
        )
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

    private func makeDylibContainerNode(
        _ machO: MachOFile,
        sourceURL: URL,
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        let targetTitle = "Dynamic Link Library (\(platformArchitectureLabel(for: machO)))"
        let targetNode = makeMachONode(
            machO,
            title: targetTitle,
            path: ["dynamic-library", "target"],
            fileBackedMachO: machO,
            sourceURL: sourceURL,
            hexSource: hexSource
        )

        return BrowserNode(
            id: "dynamic-library-root",
            title: "Dynamic Link Library",
            subtitle: sourceURL.lastPathComponent,
            summaryStyle: .group,
            detailRows: [
                .init(key: "Source File", value: sourceURL.path, groupIdentifier: 1),
                .init(key: "Target", value: targetTitle, groupIdentifier: 1),
            ],
            children: [targetNode]
        )
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

    private func makeArchiveTargetDescriptor(
        architecture: String,
        members: [String],
        extractedMembersDirectory: URL
    ) -> ArchiveTargetDescriptor {
        for memberName in members {
            let memberURL = extractedMembersDirectory.appendingPathComponent(memberName)
            guard let loaded = try? MachOKit.loadFromFile(url: memberURL) else {
                continue
            }

            switch loaded {
            case let .machO(machO):
                let platformName = platformName(for: machO).nonEmpty(or: "unknown")
                return ArchiveTargetDescriptor(
                    platformName: platformName,
                    targetName: "Static Library (\(platformName)_\(architecture.uppercased()))"
                )
            case let .fat(fat):
                if let machO = try? fat.machOFiles().first {
                    let platformName = platformName(for: machO).nonEmpty(or: "unknown")
                    return ArchiveTargetDescriptor(
                        platformName: platformName,
                        targetName: "Static Library (\(platformName)_\(architecture.uppercased()))"
                    )
                }
            }
        }

        return ArchiveTargetDescriptor(
            platformName: "unknown",
            targetName: "Static Library (\(architecture.uppercased()))"
        )
    }

    private func makeFatNode(_ fat: FatFile, sourceURL: URL, title: String, hexSource: BrowserHexSource? = nil) -> BrowserNode {
        let arches = fat.arches.enumerated().map { index, arch in
            makeGenericNode(
                title: "Architecture \(index)",
                value: arch,
                path: ["fat", "arch", "\(index)"],
                depthLimit: 2,
                hexSource: hexSource
            )
        }
        let images = (try? fat.machOFiles().enumerated().map { index, machO in
            makeMachONode(
                machO,
                title: makeImageTitle(machO, fallback: "Slice \(index)"),
                path: ["fat", "image", "\(index)"],
                fileBackedMachO: machO,
                sourceURL: sourceURL,
                hexSource: hexSource
            )
        }) ?? []

        return BrowserNode(
            id: "fat-root",
            title: title,
            subtitle: "Universal Mach-O",
            hexSource: hexSource,
            detailRows: makeDetailRows(fat),
            children: [
                BrowserNode(id: "fat-arches", title: "Architectures", hexSource: hexSource, detailRows: [.init(key: "count", value: "\(arches.count)")], children: arches),
                BrowserNode(id: "fat-images", title: "Mach-O Images", hexSource: hexSource, detailRows: [.init(key: "count", value: "\(images.count)")], children: images),
                makeGenericNode(title: "Raw Object", value: fat, path: ["fat", "raw"], depthLimit: 2, hexSource: hexSource),
            ]
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

    private func makeArchiveArchitectureNode(
        architecture: String,
        thinArchiveURL: URL,
        sourceURL: URL,
        path: [String]
    ) throws -> BrowserNode {
        let extractedMembersDirectory = thinArchiveURL.deletingLastPathComponent().appendingPathComponent("members", isDirectory: true)
        try archiveInspector.extractMembers(from: thinArchiveURL, to: extractedMembersDirectory)

        let memberLayouts = try archiveInspector.memberLayouts(in: thinArchiveURL)
        let members = memberLayouts.filter { isArchiveObjectMember($0.name) }.map(\.name)
        let targetHexSource = BrowserHexSource.file(
            url: thinArchiveURL,
            size: (try? fileSize(url: thinArchiveURL)) ?? 0
        )
        let targetDescriptor = makeArchiveTargetDescriptor(
            architecture: architecture,
            members: members,
            extractedMembersDirectory: extractedMembersDirectory
        )
        let detailRows: [BrowserDetailRow] = [
            .init(key: "Source File", value: sourceURL.path, groupIdentifier: 1),
            .init(key: "Architecture", value: architecture, groupIdentifier: 1),
            .init(key: "Platform", value: targetDescriptor.platformName, groupIdentifier: 1),
            .init(key: "Target", value: targetDescriptor.targetName, groupIdentifier: 1),
            .init(key: "Members", value: "\(members.count)", groupIdentifier: 1),
            .init(key: "Archive", value: sourceURL.lastPathComponent, groupIdentifier: 1),
        ]
        let specialNodes = makeArchiveSpecialNodes(
            memberLayouts: memberLayouts,
            extractedMembersDirectory: extractedMembersDirectory,
            archiveURL: thinArchiveURL,
            path: path,
            hexSource: targetHexSource
        )
        let cache = LazyIndexedValueCache<BrowserNode>()
        let totalChildCount = specialNodes.count + members.count

        func child(at index: Int) -> BrowserNode {
            if let cached = cache.values[index] {
                return cached
            }

            let node: BrowserNode
            if index < specialNodes.count {
                node = specialNodes[index]
            } else {
                let memberIndex = index - specialNodes.count
                let memberName = members[memberIndex]
                let memberURL = extractedMembersDirectory.appendingPathComponent(memberName)
                node = makeArchiveMemberNode(
                    memberName: memberName,
                    memberURL: memberURL,
                    path: path + ["members", "\(memberIndex)"]
                )
            }

            cache.values[index] = node
            return node
        }

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: targetDescriptor.targetName,
            subtitle: sourceURL.path,
            summaryStyle: .group,
            hexSource: targetHexSource,
            detailCount: detailRows.count + totalChildCount,
            indexedDetailProvider: { index in
                if index < detailRows.count {
                    return detailRows[index]
                }
                return summaryDetailRow(for: child(at: index - detailRows.count), groupIdentifier: UInt(index + 1))
            },
            childCount: totalChildCount,
            indexedChildProvider: child(at:)
        )
    }

    private func makeArchiveMemberNode(
        memberName: String,
        memberURL: URL,
        path: [String]
    ) -> BrowserNode {
        if let loaded = try? MachOKit.loadFromFile(url: memberURL) {
            let memberHexSource = BrowserHexSource.file(
                url: memberURL,
                size: (try? fileSize(url: memberURL)) ?? 0
            )
            switch loaded {
            case let .machO(machO):
                if machO.header.fileType == .object {
                    return makeArchiveObjectNode(
                        machO,
                        title: memberName,
                        path: path,
                        sourceURL: memberURL,
                        hexSource: memberHexSource
                    )
                }
                return makeMachONode(
                    machO,
                    title: memberName,
                    path: path,
                    fileBackedMachO: machO,
                    sourceURL: memberURL,
                    hexSource: memberHexSource
                )
            case let .fat(fat):
                return makeFatNode(fat, sourceURL: memberURL, title: memberName, hexSource: memberHexSource)
            }
        }

        let fileSize = (try? fileSize(url: memberURL)) ?? 0
        return BrowserNode(
            id: path.joined(separator: "/"),
            title: memberName,
            subtitle: "Archive Member",
            hexSource: .file(url: memberURL, size: fileSize),
            detailRows: [
                .init(key: "Path", value: memberURL.path, groupIdentifier: 1),
                .init(key: "Size", value: "\(fileSize) bytes", groupIdentifier: 1),
            ]
        )
    }

    private func makeArchiveObjectNode(
        _ machO: MachOFile,
        title: String,
        path: [String],
        sourceURL: URL,
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        let objectHeaderNode = makeGenericNode(
            title: "Object Header",
            value: machO.header,
            path: path + ["objectHeader"],
            depthLimit: 2,
            hexSource: hexSource
        )

        var detailRows = makeMachORootDetailRows(machO)
        detailRows.insert(.init(key: "Path", value: sourceURL.path, groupIdentifier: 1), at: 0)

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: title,
            subtitle: machOSummary(for: machO),
            hexSource: hexSource,
            detailRows: detailRows,
            children: [
                objectHeaderNode,
                makeIndexedSummaryNode(
                    id: (path + ["sections"]).joined(separator: "/"),
                    title: "Sections",
                    hexSource: hexSource,
                    childCount: machO.sections.count,
                    childBuilder: { index in
                        let section = machO.sections[index]
                        return makeSectionNode(
                            section,
                            in: machO,
                            sourceURL: sourceURL,
                            path: path + ["sections", "\(index)"],
                            hexSource: hexSource
                        )
                    }
                ),
                makeGenericNode(title: "Raw Object", value: machO, path: path + ["raw"], depthLimit: 2, hexSource: hexSource),
            ]
        )
    }

    private func makeArchiveSpecialNodes(
        memberLayouts: [ArchiveMemberLayout],
        extractedMembersDirectory: URL,
        archiveURL: URL,
        path: [String],
        hexSource: BrowserHexSource
    ) -> [BrowserNode] {
        let archiveMembers = makeArchiveMemberContent(
            from: memberLayouts.filter { isArchiveObjectMember($0.name) },
            extractedMembersDirectory: extractedMembersDirectory
        )
        let symtabLayout = memberLayouts.first(where: { $0.name.hasPrefix("__.SYMDEF") })
        let stringTableLayout = memberLayouts.first(where: { $0.name == "//" })
        let archiveRange = BrowserDataRange(offset: 0, length: min(archiveMagicLength, (try? fileSize(url: archiveURL)) ?? archiveMagicLength))

        return [
            makeArchiveSummaryNode(
                id: (path + ["start"]).joined(separator: "/"),
                title: "Start",
                subtitle: archiveURL.lastPathComponent,
                rows: archiveMembers.map {
                    BrowserDetailRow(
                        key: $0.name,
                        value: "offset \(summarize(UInt64($0.layout.dataOffset), fieldName: "offset")) • size \($0.startLength) bytes",
                        rawAddress: UInt64($0.layout.dataOffset),
                        groupIdentifier: 1
                    )
                },
                dataRange: archiveRange,
                hexSource: hexSource
            ),
            makeArchiveSummaryNode(
                id: (path + ["symtabHeader"]).joined(separator: "/"),
                title: "Symtab Header",
                subtitle: symtabLayout?.name ?? "Not present",
                rows: archiveMembers.map {
                    if let symtabHeaderRange = $0.symtabHeaderRange {
                        return BrowserDetailRow(
                            key: $0.name,
                            value: "offset \(summarize(UInt64(symtabHeaderRange.offset), fieldName: "offset")) • size \(symtabHeaderRange.length) bytes",
                            rawAddress: UInt64(symtabHeaderRange.offset),
                            groupIdentifier: 1
                        )
                    }
                    return BrowserDetailRow(
                        key: $0.name,
                        value: "Not present",
                        groupIdentifier: 1
                    )
                },
                dataRange: symtabLayout.flatMap { BrowserDataRange(offset: $0.headerOffset, length: $0.headerSize) },
                hexSource: hexSource
            ),
            makeArchiveSummaryNode(
                id: (path + ["symbolTable"]).joined(separator: "/"),
                title: "Symbol Table",
                subtitle: archiveMembers.reduce(0) { $0 + $1.symbols.count } == 0
                    ? (symtabLayout.map { "\($0.dataSize) bytes" } ?? "Not present")
                    : "\(archiveMembers.reduce(0) { $0 + $1.symbols.count }) symbols",
                rows: archiveMembers.flatMap { member in
                    member.symbols.map {
                        BrowserDetailRow(
                            key: member.name,
                            value: $0,
                            rawAddress: member.symbolTableRange.map { UInt64($0.offset) },
                            groupIdentifier: 1
                        )
                    }
                },
                dataRange: symtabLayout.flatMap { BrowserDataRange(offset: $0.dataOffset, length: $0.dataSize) },
                hexSource: hexSource
            ),
            makeArchiveSummaryNode(
                id: (path + ["stringTable"]).joined(separator: "/"),
                title: "String Table",
                subtitle: archiveMembers.reduce(0) { $0 + $1.stringEntries.count } == 0
                    ? (stringTableLayout.map { "\($0.dataSize) bytes" } ?? "Not present")
                    : "\(archiveMembers.reduce(0) { $0 + $1.stringEntries.count }) strings",
                rows: archiveMembers.flatMap { member in
                    member.stringEntries.map {
                        BrowserDetailRow(
                            key: member.name,
                            value: $0,
                            rawAddress: member.stringTableRange.map { UInt64($0.offset) },
                            groupIdentifier: 1
                        )
                    }
                },
                dataRange: stringTableLayout.flatMap { BrowserDataRange(offset: $0.dataOffset, length: $0.dataSize) },
                hexSource: hexSource
            ),
        ]
    }

    private func makeArchiveSummaryNode(
        id: String,
        title: String,
        subtitle: String,
        rows: [BrowserDetailRow],
        dataRange: BrowserDataRange?,
        hexSource: BrowserHexSource
    ) -> BrowserNode {
        return BrowserNode(
            id: id,
            title: title,
            subtitle: subtitle,
            hexSource: hexSource,
            detailRows: rows.isEmpty ? [.init(key: "Status", value: "Not present", groupIdentifier: 1)] : rows,
            rawAddress: dataRange.map { UInt64($0.offset) },
            dataRange: dataRange
        )
    }

    private func isArchiveObjectMember(_ name: String) -> Bool {
        if name.hasPrefix("__.SYMDEF") || name == "/" || name == "//" {
            return false
        }
        return true
    }

    private func makeArchiveMemberContent(
        from memberLayouts: [ArchiveMemberLayout],
        extractedMembersDirectory: URL
    ) -> [ArchiveMemberContent] {
        memberLayouts.compactMap { layout in
            let memberURL = extractedMembersDirectory.appendingPathComponent(layout.name)
            guard
                let loaded = try? MachOKit.loadFromFile(url: memberURL),
                case let .machO(machO) = loaded
            else {
                return nil
            }

            let headerSize = machO.is64Bit ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
            let symtab: LoadCommandInfo<symtab_command>? = machO.loadCommands.info(of: LoadCommand.symtab)

            return ArchiveMemberContent(
                name: layout.name,
                layout: layout,
                startLength: min(headerSize, layout.dataSize),
                symtabHeaderRange: symtab.map {
                    BrowserDataRange(
                        offset: layout.dataOffset + machO.headerStartOffset + machO.cmdsStartOffset + $0.offset,
                        length: Int($0.layout.cmdsize)
                    )
                },
                symbolTableRange: symtab.map {
                    BrowserDataRange(
                        offset: layout.dataOffset + Int($0.layout.symoff),
                        length: Int($0.layout.nsyms) * (machO.is64Bit ? MemoryLayout<nlist_64>.size : MemoryLayout<nlist>.size)
                    )
                },
                stringTableRange: symtab.flatMap {
                    $0.layout.strsize > 0
                        ? BrowserDataRange(offset: layout.dataOffset + Int($0.layout.stroff), length: Int($0.layout.strsize))
                        : nil
                },
                symbols: objectFileSymbolNames(in: machO).filter { $0.isEmpty == false },
                stringEntries: objectFileStringTableEntries(in: machO)
            )
        }
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
        fileBackedMachO: MachOFile? = nil,
        sourceURL: URL? = nil,
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
                                if let fileBackedMachO, let sourceURL {
                                    return makeSectionNode(
                                        section,
                                        in: fileBackedMachO,
                                        sourceURL: sourceURL,
                                        path: path + ["segments", "\(index)", "sections", "\(sectionIndex)"],
                                        hexSource: hexSource
                                    )
                                }
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
                        if let fileBackedMachO, let sourceURL {
                            return makeSectionNode(
                                section,
                                in: fileBackedMachO,
                                sourceURL: sourceURL,
                                path: path + ["sections", "\(index)"],
                                hexSource: hexSource
                            )
                        }
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

    private func reflectLoadCommandString(from value: Any, member: String) -> String {
        guard let memberValue = Mirror(reflecting: value).children.first(where: { $0.label == member })?.value else {
            return ""
        }
        return summarize(memberValue, fieldName: member)
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

    private func makeSectionNode(
        _ section: any SectionProtocol,
        in machO: MachOFile,
        sourceURL: URL,
        path: [String],
        hexSource: BrowserHexSource? = nil
    ) -> BrowserNode {
        let absoluteOffset = machO.headerStartOffset + section.offset
        let baseDetailRows = makeDetailRows(section)
        let specialContent = makeSpecialSectionContent(
            section,
            in: machO,
            sourceURL: sourceURL,
            path: path,
            hexSource: hexSource
        )
        let detailCount = baseDetailRows.count + (specialContent?.detailCount ?? 0)

        return BrowserNode(
            id: path.joined(separator: "/"),
            title: sectionNodeTitle(for: section, specialContent: specialContent),
            subtitle: summarize(section.flags.type as Any, fieldName: "type"),
            hexSource: hexSource,
            detailCount: detailCount,
            indexedDetailProvider: detailCount == 0 ? nil : { index in
                if index < baseDetailRows.count {
                    return baseDetailRows[index]
                }
                guard let specialContent else {
                    return baseDetailRows[index]
                }
                return specialContent.detailRow(index - baseDetailRows.count)
            },
            childCount: specialContent?.childCount ?? 0,
            indexedChildProvider: specialContent?.child,
            rawAddress: UInt64(absoluteOffset),
            rvaAddress: UInt64(section.address),
            dataRange: BrowserDataRange(offset: absoluteOffset, length: section.size)
        )
    }

    private func makeSpecialSectionContent(
        _ section: any SectionProtocol,
        in machO: MachOFile,
        sourceURL: URL,
        path: [String],
        hexSource: BrowserHexSource? = nil
    ) -> SpecialSectionContent? {
        switch section.sectionName {
        case "__objc_classlist", "__objc_nlclslist":
            return parseObjCClassListSection(section, in: machO, sourceURL: sourceURL, path: path, hexSource: hexSource)
        case "__objc_catlist", "__objc_nlcatlist":
            return parseObjCCategoryListSection(section, in: machO, sourceURL: sourceURL, path: path, hexSource: hexSource)
        case "__objc_classrefs":
            return parseObjCReferenceSection(
                section,
                in: machO,
                sourceURL: sourceURL,
                path: path,
                kind: .classReference,
                hexSource: hexSource
            )
        case "__objc_superrefs":
            return parseObjCReferenceSection(
                section,
                in: machO,
                sourceURL: sourceURL,
                path: path,
                kind: .superReference,
                hexSource: hexSource
            )
        case "__objc_selrefs":
            return parseObjCReferenceSection(
                section,
                in: machO,
                sourceURL: sourceURL,
                path: path,
                kind: .selectorReference,
                hexSource: hexSource
            )
        case "__objc_classname":
            return parseCStringSection(
                section,
                in: machO,
                sourceURL: sourceURL,
                path: path,
                valueLabel: "Objective-C Class Name",
                hexSource: hexSource
            )
        case "__objc_methname":
            return parseCStringSection(
                section,
                in: machO,
                sourceURL: sourceURL,
                path: path,
                valueLabel: "Objective-C Method Name",
                hexSource: hexSource
            )
        case "__objc_methtype":
            return parseCStringSection(
                section,
                in: machO,
                sourceURL: sourceURL,
                path: path,
                valueLabel: "Objective-C Method Type",
                hexSource: hexSource
            )
        default:
            return nil
        }
    }

    private func parseObjCClassListSection(
        _ section: any SectionProtocol,
        in machO: MachOFile,
        sourceURL: URL,
        path: [String],
        hexSource: BrowserHexSource? = nil
    ) -> SpecialSectionContent? {
        let pointerSize = machO.is64Bit ? MemoryLayout<UInt64>.size : MemoryLayout<UInt32>.size
        guard pointerSize > 0, section.size >= pointerSize else {
            return nil
        }

        let count = section.size / pointerSize
        guard count > 0 else {
            return nil
        }

        let objectRelocations = machO.header.fileType == .object
            ? objcClassListRelocations(for: section, in: machO)
            : [:]

        return makeSpecialSectionContent(childCount: count, path: path, hexSource: hexSource) { index in
            let entrySliceOffset = section.offset + index * pointerSize
            let entryAbsoluteOffset = machO.headerStartOffset + entrySliceOffset
            let handle: FileHandle
            do {
                handle = try FileHandle(forReadingFrom: sourceURL)
            } catch {
                let detailRows: [BrowserDetailRow] = [
                    .init(key: "Error", value: "Unable to open file for Objective-C class inspection.")
                ]
                return SpecialSectionEntry(
                    title: "Class \(index)",
                    detailRows: detailRows,
                    summaryRow: .init(key: "Class \(index)", value: "Unable to inspect class.")
                )
            }
            defer {
                try? handle.close()
            }

            guard let rawPointer = readPointer(handle: handle, offset: entryAbsoluteOffset, is64Bit: machO.is64Bit) else {
                let detailRows: [BrowserDetailRow] = [
                    .init(
                        key: "List Entry RAW",
                        value: summarize(UInt64(entryAbsoluteOffset), fieldName: "offset"),
                        rawAddress: UInt64(entryAbsoluteOffset),
                        groupIdentifier: 1
                    )
                ]
                return SpecialSectionEntry(
                    title: "Class \(index)",
                    detailRows: detailRows,
                    summaryRow: .init(
                        key: "Class \(index)",
                        value: "Objective-C Class",
                        rawAddress: UInt64(entryAbsoluteOffset),
                        groupIdentifier: 1
                    )
                )
            }

            let classVMAddress = rawPointer != 0
                ? machO.stripPointerTags(of: rawPointer)
                : (machO.resolveOptionalRebase(at: UInt64(entrySliceOffset)).map { machO.stripPointerTags(of: $0) } ?? 0)

            let fallbackName = objectRelocations[index] ?? "Class \(index)"
            let className: String
            let classOffset: Int?
            let absoluteClassOffset: Int?

            if classVMAddress != 0 {
                className = resolveObjCClassName(
                    at: classVMAddress,
                    in: machO,
                    sourceURL: sourceURL,
                    fileHandle: handle
                ) ?? fallbackName
                classOffset = machO.fileOffset(of: classVMAddress).flatMap(Int.init)
                absoluteClassOffset = classOffset.map { machO.headerStartOffset + $0 }
            } else {
                className = fallbackName
                classOffset = nil
                absoluteClassOffset = nil
            }

            var detailRows: [BrowserDetailRow] = [
                .init(key: "Name", value: className, groupIdentifier: 1),
                .init(key: "List Entry RAW", value: summarize(UInt64(entryAbsoluteOffset), fieldName: "offset"), rawAddress: UInt64(entryAbsoluteOffset), groupIdentifier: 1),
            ]
            if classVMAddress != 0 {
                detailRows.insert(
                    .init(
                        key: "Address",
                        value: summarize(classVMAddress, fieldName: "address"),
                        rawAddress: absoluteClassOffset.map(UInt64.init),
                        rvaAddress: classVMAddress,
                        groupIdentifier: 1
                    ),
                    at: 0
                )
            }

            return SpecialSectionEntry(
                title: className,
                subtitle: classVMAddress == 0 ? nil : summarize(classVMAddress, fieldName: "address"),
                detailRows: detailRows,
                summaryRow: .init(
                    key: "Objective-C Class",
                    value: className,
                    rawAddress: absoluteClassOffset.map(UInt64.init),
                    rvaAddress: classVMAddress == 0 ? nil : classVMAddress,
                    groupIdentifier: 1
                ),
                rawAddress: absoluteClassOffset.map(UInt64.init),
                rvaAddress: classVMAddress == 0 ? nil : classVMAddress,
                dataRange: absoluteClassOffset.map { BrowserDataRange(offset: $0, length: machO.is64Bit ? 40 : 20) }
            )
        }
    }

    private func parseObjCCategoryListSection(
        _ section: any SectionProtocol,
        in machO: MachOFile,
        sourceURL: URL,
        path: [String],
        hexSource: BrowserHexSource? = nil
    ) -> SpecialSectionContent? {
        let pointerSize = machO.is64Bit ? MemoryLayout<UInt64>.size : MemoryLayout<UInt32>.size
        guard pointerSize > 0, section.size >= pointerSize else {
            return nil
        }

        let count = section.size / pointerSize
        guard count > 0 else {
            return nil
        }

        let objectRelocations = machO.header.fileType == .object
            ? objcCategoryListRelocations(for: section, in: machO)
            : [:]

        return makeSpecialSectionContent(childCount: count, path: path, hexSource: hexSource) { index in
            let entrySliceOffset = section.offset + index * pointerSize
            let entryAbsoluteOffset = machO.headerStartOffset + entrySliceOffset
            let handle: FileHandle
            do {
                handle = try FileHandle(forReadingFrom: sourceURL)
            } catch {
                let title = objectRelocations[index]?.displayName ?? "Category \(index)"
                let detailRows: [BrowserDetailRow] = [
                    .init(key: "Error", value: "Unable to open file for Objective-C category inspection.")
                ]
                return SpecialSectionEntry(
                    title: title,
                    detailRows: detailRows,
                    summaryRow: .init(key: title, value: "Objective-C Category")
                )
            }
            defer {
                try? handle.close()
            }

            let rawPointer = readPointer(handle: handle, offset: entryAbsoluteOffset, is64Bit: machO.is64Bit)
            let categoryVMAddress = rawPointer.flatMap { pointer -> UInt64? in
                let stripped = machO.stripPointerTags(of: pointer)
                if stripped != 0 {
                    return stripped
                }
                return machO.resolveOptionalRebase(at: UInt64(entrySliceOffset)).map { machO.stripPointerTags(of: $0) }
            } ?? 0

            let fallbackInfo = objectRelocations[index]
            let resolvedInfo = categoryVMAddress == 0
                ? nil
                : resolveObjCCategoryInfo(
                    at: categoryVMAddress,
                    in: machO,
                    fileHandle: handle
                )
            let categoryName = resolvedInfo?.categoryName ?? fallbackInfo?.categoryName ?? "Category \(index)"
            let className = resolvedInfo?.className ?? fallbackInfo?.className
            let title = className.map { "\($0) (\(categoryName))" } ?? categoryName
            let absoluteCategoryOffset = machO.fileOffset(of: categoryVMAddress)
                .flatMap(Int.init)
                .map { machO.headerStartOffset + $0 }

            var detailRows: [BrowserDetailRow] = [
                .init(key: "Category Name", value: categoryName, groupIdentifier: 1),
                .init(
                    key: "List Entry RAW",
                    value: summarize(UInt64(entryAbsoluteOffset), fieldName: "offset"),
                    rawAddress: UInt64(entryAbsoluteOffset),
                    groupIdentifier: 1
                ),
            ]
            if let className {
                detailRows.insert(.init(key: "Class Name", value: className, groupIdentifier: 1), at: 1)
            }
            if categoryVMAddress != 0 {
                detailRows.insert(
                    .init(
                        key: "Address",
                        value: summarize(categoryVMAddress, fieldName: "address"),
                        rawAddress: absoluteCategoryOffset.map(UInt64.init),
                        rvaAddress: categoryVMAddress,
                        groupIdentifier: 1
                    ),
                    at: 0
                )
            }

            return SpecialSectionEntry(
                title: title,
                subtitle: categoryVMAddress == 0 ? nil : summarize(categoryVMAddress, fieldName: "address"),
                detailRows: detailRows,
                summaryRow: .init(
                    key: "Objective-C Category",
                    value: title,
                    rawAddress: absoluteCategoryOffset.map(UInt64.init),
                    rvaAddress: categoryVMAddress == 0 ? nil : categoryVMAddress,
                    groupIdentifier: 1
                ),
                rawAddress: absoluteCategoryOffset.map(UInt64.init),
                rvaAddress: categoryVMAddress == 0 ? nil : categoryVMAddress,
                dataRange: absoluteCategoryOffset.map { BrowserDataRange(offset: $0, length: machO.is64Bit ? 48 : 24) }
            )
        }
    }

    private func parseObjCReferenceSection(
        _ section: any SectionProtocol,
        in machO: MachOFile,
        sourceURL: URL,
        path: [String],
        kind: ObjCReferenceKind,
        hexSource: BrowserHexSource? = nil
    ) -> SpecialSectionContent? {
        let pointerSize = machO.is64Bit ? MemoryLayout<UInt64>.size : MemoryLayout<UInt32>.size
        guard pointerSize > 0, section.size >= pointerSize else {
            return nil
        }

        let count = section.size / pointerSize
        guard count > 0 else {
            return nil
        }

        let objectRelocations = machO.header.fileType == .object
            ? objcReferenceRelocations(for: section, in: machO, kind: kind)
            : [:]

        return makeSpecialSectionContent(childCount: count, path: path, hexSource: hexSource) { index in
            let entrySliceOffset = section.offset + index * pointerSize
            let entryAbsoluteOffset = machO.headerStartOffset + entrySliceOffset
            let handle: FileHandle
            do {
                handle = try FileHandle(forReadingFrom: sourceURL)
            } catch {
                let title = objectRelocations[index] ?? "\(kind.itemLabel) \(index)"
                return SpecialSectionEntry(
                    title: title,
                    detailRows: [.init(key: "Error", value: "Unable to inspect Objective-C references.")],
                    summaryRow: .init(key: kind.rowValue, value: title)
                )
            }
            defer {
                try? handle.close()
            }

            let rawPointer = readPointer(handle: handle, offset: entryAbsoluteOffset, is64Bit: machO.is64Bit)
            let referenceVMAddress = rawPointer.flatMap { pointer -> UInt64? in
                let stripped = machO.stripPointerTags(of: pointer)
                if stripped != 0 {
                    return stripped
                }
                return machO.resolveOptionalRebase(at: UInt64(entrySliceOffset)).map { machO.stripPointerTags(of: $0) }
            } ?? 0

            let resolvedName = resolveObjCReferenceName(
                kind: kind,
                referenceVMAddress: referenceVMAddress,
                in: machO,
                fileHandle: handle
            )
            let title = resolvedName ?? objectRelocations[index] ?? "\(kind.itemLabel) \(index)"
            let absoluteReferenceOffset = machO.fileOffset(of: referenceVMAddress)
                .flatMap(Int.init)
                .map { machO.headerStartOffset + $0 }

            var detailRows: [BrowserDetailRow] = [
                .init(key: "Name", value: title, groupIdentifier: 1),
                .init(
                    key: "List Entry RAW",
                    value: summarize(UInt64(entryAbsoluteOffset), fieldName: "offset"),
                    rawAddress: UInt64(entryAbsoluteOffset),
                    groupIdentifier: 1
                ),
            ]
            if referenceVMAddress != 0 {
                detailRows.insert(
                    .init(
                        key: "Address",
                        value: summarize(referenceVMAddress, fieldName: "address"),
                        rawAddress: absoluteReferenceOffset.map(UInt64.init),
                        rvaAddress: referenceVMAddress,
                        groupIdentifier: 1
                    ),
                    at: 0
                )
            }

            return SpecialSectionEntry(
                title: title,
                subtitle: referenceVMAddress == 0 ? nil : summarize(referenceVMAddress, fieldName: "address"),
                detailRows: detailRows,
                summaryRow: .init(
                    key: kind.rowValue,
                    value: title,
                    rawAddress: absoluteReferenceOffset.map(UInt64.init),
                    rvaAddress: referenceVMAddress == 0 ? nil : referenceVMAddress,
                    groupIdentifier: 1
                ),
                rawAddress: absoluteReferenceOffset.map(UInt64.init),
                rvaAddress: referenceVMAddress == 0 ? nil : referenceVMAddress,
                dataRange: absoluteReferenceOffset.map { BrowserDataRange(offset: $0, length: pointerSize) }
            )
        }
    }

    private func parseCStringSection(
        _ section: any SectionProtocol,
        in machO: MachOFile,
        sourceURL: URL,
        path: [String],
        valueLabel: String,
        hexSource: BrowserHexSource? = nil
    ) -> SpecialSectionContent? {
        let absoluteOffset = machO.headerStartOffset + section.offset
        let stringOffsets = cStringEntryOffsets(
            sourceURL: sourceURL,
            absoluteOffset: absoluteOffset,
            length: section.size
        )
        guard stringOffsets.isEmpty == false else {
            return nil
        }

        return makeSpecialSectionContent(childCount: stringOffsets.count, path: path, hexSource: hexSource) { index in
            let stringOffset = stringOffsets[index]
            let stringValue = readCString(sourceURL: sourceURL, offset: stringOffset) ?? "String \(index)"
            let stringLength = stringValue.utf8.count + 1
            let relativeOffset = stringOffset - absoluteOffset
            let rawAddress = UInt64(stringOffset)
            let rvaAddress = UInt64(section.address) + UInt64(relativeOffset)
            let dataPreview = detailDataPreview(for: stringValue)

            let detailRows: [BrowserDetailRow] = [
                .init(
                    key: "Address",
                    value: summarize(rvaAddress, fieldName: "address"),
                    dataPreview: dataPreview,
                    rawAddress: rawAddress,
                    rvaAddress: rvaAddress,
                    groupIdentifier: 1
                ),
                .init(
                    key: valueLabel,
                    value: stringValue,
                    dataPreview: dataPreview,
                    rawAddress: rawAddress,
                    rvaAddress: rvaAddress,
                    groupIdentifier: 1
                ),
            ]

            return SpecialSectionEntry(
                title: stringValue,
                subtitle: summarize(rvaAddress, fieldName: "address"),
                detailRows: detailRows,
                summaryRow: .init(
                    key: valueLabel,
                    value: stringValue,
                    dataPreview: dataPreview,
                    rawAddress: rawAddress,
                    rvaAddress: rvaAddress,
                    groupIdentifier: 1
                ),
                rawAddress: rawAddress,
                rvaAddress: rvaAddress,
                dataRange: BrowserDataRange(offset: stringOffset, length: stringLength)
            )
        }
    }

    private func makeSpecialSectionContent(
        childCount: Int,
        path: [String],
        hexSource: BrowserHexSource? = nil,
        resolver: @escaping (Int) -> SpecialSectionEntry
    ) -> SpecialSectionContent {
        let cache = LazyIndexedValueCache<SpecialSectionEntry>()

        func entry(at index: Int) -> SpecialSectionEntry {
            if let cached = cache.values[index] {
                return cached
            }
            let resolved = resolver(index)
            cache.values[index] = resolved
            return resolved
        }

        return SpecialSectionContent(
            childCount: childCount,
            child: { index in
                let entry = entry(at: index)
                return BrowserNode(
                    id: (path + ["\(index)"]).joined(separator: "/"),
                    title: entry.title,
                    subtitle: entry.subtitle,
                    hexSource: hexSource,
                    detailRows: entry.detailRows,
                    rawAddress: entry.rawAddress,
                    rvaAddress: entry.rvaAddress,
                    dataRange: entry.dataRange
                )
            },
            detailCount: childCount,
            detailRow: { index in
                entry(at: index).summaryRow
            }
        )
    }

    private func titleWithCount(_ title: String, count: Int) -> String {
        "\(title) (\(count))"
    }

    private func sectionNodeTitle(for section: any SectionProtocol, specialContent: SpecialSectionContent?) -> String {
        let baseTitle = "\(section.segmentName).\(section.sectionName)"
        guard
            let specialContent,
            ["__objc_classlist", "__objc_nlclslist"].contains(section.sectionName)
        else {
            return baseTitle
        }

        return titleWithCount(baseTitle, count: specialContent.childCount)
    }

    private func resolveObjCCategoryInfo(
        at categoryVMAddress: UInt64,
        in machO: MachOFile,
        fileHandle: FileHandle
    ) -> ObjCCategoryInfo? {
        guard let categoryOffset = machO.fileOffset(of: categoryVMAddress).flatMap(Int.init) else {
            return nil
        }

        let absoluteOffset = machO.headerStartOffset + categoryOffset
        let pointerSize = machO.is64Bit ? 8 : 4

        guard
            let namePointer = readPointer(handle: fileHandle, offset: absoluteOffset, is64Bit: machO.is64Bit),
            let classPointer = readPointer(handle: fileHandle, offset: absoluteOffset + pointerSize, is64Bit: machO.is64Bit)
        else {
            return nil
        }

        let categoryName = resolveCString(
            at: machO.stripPointerTags(of: namePointer),
            in: machO,
            fileHandle: fileHandle
        )
        let className = resolveObjCClassName(
            at: machO.stripPointerTags(of: classPointer),
            in: machO,
            sourceURL: machO.url,
            fileHandle: fileHandle
        )

        if categoryName == nil, className == nil {
            return nil
        }

        return ObjCCategoryInfo(categoryName: categoryName, className: className)
    }

    private func resolveCString(
        at vmAddress: UInt64,
        in machO: MachOFile,
        fileHandle: FileHandle
    ) -> String? {
        guard vmAddress != 0, let offset = machO.fileOffset(of: vmAddress).flatMap(Int.init) else {
            return nil
        }

        return readCString(handle: fileHandle, offset: machO.headerStartOffset + offset)
    }

    private func resolveObjCClassName(
        at classVMAddress: UInt64,
        in machO: MachOFile,
        sourceURL: URL,
        fileHandle: FileHandle
    ) -> String? {
        guard let classOffset = machO.fileOffset(of: classVMAddress).flatMap(Int.init) else {
            return nil
        }

        let dataBitsOffset = classOffset + (machO.is64Bit ? 32 : 16)
        guard let dataBits = readPointer(
            handle: fileHandle,
            offset: machO.headerStartOffset + dataBitsOffset,
            is64Bit: machO.is64Bit
        ) else {
            return nil
        }

        let roAddress = machO.stripPointerTags(of: dataBits) & ~UInt64(0x7)
        guard let roOffset = machO.fileOffset(of: roAddress).flatMap(Int.init) else {
            return nil
        }

        let namePointerFieldOffset = roOffset + (machO.is64Bit ? 24 : 16)
        guard let namePointer = readPointer(
            handle: fileHandle,
            offset: machO.headerStartOffset + namePointerFieldOffset,
            is64Bit: machO.is64Bit
        ) else {
            return nil
        }

        let nameAddress = machO.stripPointerTags(of: namePointer)
        guard let nameOffset = machO.fileOffset(of: nameAddress).flatMap(Int.init) else {
            return nil
        }

        return readCString(handle: fileHandle, offset: machO.headerStartOffset + nameOffset)
    }

    private func readPointer(handle: FileHandle, offset: Int, is64Bit: Bool) -> UInt64? {
        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = handle.readData(ofLength: is64Bit ? 8 : 4)
            guard data.count == (is64Bit ? 8 : 4) else {
                return nil
            }

            if is64Bit {
                return data.withUnsafeBytes { buffer in
                    var value: UInt64 = 0
                    withUnsafeMutableBytes(of: &value) { destination in
                        destination.copyBytes(from: buffer)
                    }
                    return UInt64(littleEndian: value)
                }
            } else {
                return data.withUnsafeBytes { buffer in
                    var value: UInt32 = 0
                    withUnsafeMutableBytes(of: &value) { destination in
                        destination.copyBytes(from: buffer)
                    }
                    return UInt64(UInt32(littleEndian: value))
                }
            }
        } catch {
            return nil
        }
    }

    private func readCString(handle: FileHandle, offset: Int, maximumLength: Int = 4096) -> String? {
        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = handle.readData(ofLength: maximumLength)
            guard data.isEmpty == false else {
                return nil
            }
            let length = data.firstIndex(of: 0) ?? data.endIndex
            return String(data: data.prefix(upTo: length), encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func readLayout<T>(handle: FileHandle, offset: Int) -> T? {
        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = handle.readData(ofLength: MemoryLayout<T>.size)
            guard data.count == MemoryLayout<T>.size else {
                return nil
            }
            return data.withUnsafeBytes { $0.load(as: T.self) }
        } catch {
            return nil
        }
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

    private func platformArchitectureLabel(for machO: some MachORepresentable) -> String {
        "\(platformName(for: machO))_\(architectureName(for: machO).uppercased())"
    }

    private func platformName(for machO: some MachORepresentable) -> String {
        if let platform = machO.loadCommands.info(of: LoadCommand.buildVersion)?.platform {
            return normalizedPlatformName(shortPlatformName(platform), for: machO)
        }
        if machO.loadCommands.info(of: LoadCommand.versionMinMacosx) != nil {
            return "macos"
        }
        if machO.loadCommands.info(of: LoadCommand.versionMinIphoneos) != nil {
            return normalizedPlatformName("iphoneos", for: machO)
        }
        if machO.loadCommands.info(of: LoadCommand.versionMinTvos) != nil {
            return normalizedPlatformName("tvos", for: machO)
        }
        if machO.loadCommands.info(of: LoadCommand.versionMinWatchos) != nil {
            return normalizedPlatformName("watchos", for: machO)
        }
        return "unknown"
    }

    private func normalizedPlatformName(_ name: String, for machO: some MachORepresentable) -> String {
        guard let cpuType = machO.header.cpuType, isSimulatorArchitecture(cpuType) else {
            return name
        }

        switch name {
        case "iphoneos":
            return "iphonesimulator"
        case "tvos":
            return "tvossimulator"
        case "watchos":
            return "watchsimulator"
        default:
            return name
        }
    }

    private func isSimulatorArchitecture(_ cpuType: CPUType) -> Bool {
        switch cpuType {
        case .x86, .i386, .x86_64:
            return true
        default:
            return false
        }
    }

    private func shortPlatformName(_ platform: Platform) -> String {
        switch platform {
        case .macOS, .macOSExclaveCore, .macOSExclaveKit:
            "macos"
        case .iOS:
            "iphoneos"
        case .tvOS:
            "tvos"
        case .watchOS:
            "watchos"
        case .bridgeOS:
            "bridgeos"
        case .macCatalyst:
            "maccatalyst"
        case .iOSSimulator:
            "iphonesimulator"
        case .tvOSSimulator:
            "tvossimulator"
        case .watchOSSimulator:
            "watchsimulator"
        case .driverKit:
            "driverkit"
        case .visionOS:
            "xros"
        case .visionOSSimulator:
            "xrsimulator"
        case .firmware:
            "firmware"
        case .sepOS:
            "sepos"
        case .iOSExclaveCore, .iOSExclaveKit:
            "iosexclave"
        case .tvOSExclaveCore, .tvOSExclaveKit:
            "tvosexclave"
        case .watchOSExclaveCore, .watchOSExclaveKit:
            "watchosexclave"
        case .visionOSExclaveCore, .visionOSExclaveKit:
            "visionosexclave"
        case .unknown, .any:
            "unknown"
        }
    }

    private func architectureName(for machO: some MachORepresentable) -> String {
        switch machO.header.cpuType {
        case .arm64:
            return machO.header.cpuSubType?.description.contains("ARM64E") == true ? "arm64e" : "arm64"
        case .x86_64:
            return "x86_64"
        case .arm:
            return "arm"
        case .x86, .i386:
            return "i386"
        case .arm64_32:
            return "arm64_32"
        default:
            return String(describing: machO.header.cpuType)
                .replacingOccurrences(of: "CPU_TYPE_", with: "")
                .lowercased()
        }
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

    private func objcClassListRelocations(
        for section: any SectionProtocol,
        in machO: MachOFile
    ) -> [Int: String] {
        let symbols = objectFileSymbolNames(in: machO)
        var namesByIndex: [Int: String] = [:]

        for relocation in section.relocations(in: machO) {
            guard case let .general(info) = relocation.info,
                  let symbolIndex = info.symbolIndex,
                  symbols.indices.contains(symbolIndex) else {
                continue
            }

            let entryIndex = Int(info.layout.r_address) / (machO.is64Bit ? MemoryLayout<UInt64>.size : MemoryLayout<UInt32>.size)
            namesByIndex[entryIndex] = demangleObjCClassSymbol(symbols[symbolIndex])
        }

        return namesByIndex
    }

    private func objectFileSymbolNames(in machO: MachOFile) -> [String] {
        guard let symtab: LoadCommandInfo<symtab_command> = machO.loadCommands.info(of: LoadCommand.symtab) else {
            return []
        }

        let symbolCount = Int(symtab.nsyms)
        guard symbolCount > 0 else {
            return []
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: machO.url)
        } catch {
            return []
        }
        defer {
            try? handle.close()
        }

        let stringTableOffset = machO.headerStartOffset + Int(symtab.stroff)
        let stringTableSize = Int(symtab.strsize)
        let stringTable: Data
        do {
            try handle.seek(toOffset: UInt64(stringTableOffset))
            stringTable = handle.readData(ofLength: max(0, stringTableSize))
        } catch {
            return Array(repeating: "", count: symbolCount)
        }

        return (0..<symbolCount).map { symbolIndex in
            let symbolOffset = machO.headerStartOffset
                + Int(symtab.symoff)
                + symbolIndex * (machO.is64Bit ? MemoryLayout<nlist_64>.size : MemoryLayout<nlist>.size)
            let stringIndex: Int?

            if machO.is64Bit {
                guard let rawSymbol: nlist_64 = readLayout(handle: handle, offset: symbolOffset) else {
                    return ""
                }
                var symbol = rawSymbol
                if machO.isSwapped {
                    swap_nlist_64(&symbol, 1, NXHostByteOrder())
                }
                stringIndex = Int(symbol.n_un.n_strx)
            } else {
                guard let rawSymbol: nlist = readLayout(handle: handle, offset: symbolOffset) else {
                    return ""
                }
                var symbol = rawSymbol
                if machO.isSwapped {
                    swap_nlist(&symbol, 1, NXHostByteOrder())
                }
                stringIndex = Int(symbol.n_un.n_strx)
            }

            guard let stringIndex, stringIndex > 0, stringIndex < stringTable.count else {
                return ""
            }

            return stringTable.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return ""
                }
                return String(
                    cString: baseAddress.advanced(by: stringIndex).assumingMemoryBound(to: CChar.self),
                    encoding: .utf8
                ) ?? ""
            }
        }
    }

    private func objectFileStringTableEntries(in machO: MachOFile) -> [String] {
        guard let symtab: LoadCommandInfo<symtab_command> = machO.loadCommands.info(of: LoadCommand.symtab) else {
            return []
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: machO.url)
        } catch {
            return []
        }
        defer {
            try? handle.close()
        }

        let stringTableOffset = machO.headerStartOffset + Int(symtab.stroff)
        let stringTableSize = Int(symtab.strsize)
        guard stringTableSize > 0 else {
            return []
        }

        let stringTable: Data
        do {
            try handle.seek(toOffset: UInt64(stringTableOffset))
            stringTable = handle.readData(ofLength: stringTableSize)
        } catch {
            return []
        }

        return stringTable
            .split(separator: 0)
            .compactMap { String(data: $0, encoding: .utf8) }
            .filter { $0.isEmpty == false }
    }

    private func demangleObjCClassSymbol(_ symbolName: String) -> String {
        if let range = symbolName.range(of: "_OBJC_CLASS_$_") {
            return String(symbolName[range.upperBound...])
        }
        return symbolName.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func objcCategoryListRelocations(
        for section: any SectionProtocol,
        in machO: MachOFile
    ) -> [Int: ObjCCategorySymbol] {
        let symbols = objectFileSymbolNames(in: machO)
        var namesByIndex: [Int: ObjCCategorySymbol] = [:]

        for relocation in section.relocations(in: machO) {
            guard case let .general(info) = relocation.info,
                  let symbolIndex = info.symbolIndex,
                  symbols.indices.contains(symbolIndex) else {
                continue
            }

            let entryIndex = Int(info.layout.r_address) / (machO.is64Bit ? MemoryLayout<UInt64>.size : MemoryLayout<UInt32>.size)
            namesByIndex[entryIndex] = demangleObjCCategorySymbol(symbols[symbolIndex])
        }

        return namesByIndex
    }

    private func objcReferenceRelocations(
        for section: any SectionProtocol,
        in machO: MachOFile,
        kind: ObjCReferenceKind
    ) -> [Int: String] {
        let symbols = objectFileSymbolNames(in: machO)
        var namesByIndex: [Int: String] = [:]

        for relocation in section.relocations(in: machO) {
            guard case let .general(info) = relocation.info,
                  let symbolIndex = info.symbolIndex,
                  symbols.indices.contains(symbolIndex) else {
                continue
            }

            let entryIndex = Int(info.layout.r_address) / (machO.is64Bit ? MemoryLayout<UInt64>.size : MemoryLayout<UInt32>.size)
            namesByIndex[entryIndex] = demangleObjCReferenceSymbol(symbols[symbolIndex], kind: kind)
        }

        return namesByIndex
    }

    private func demangleObjCCategorySymbol(_ symbolName: String) -> ObjCCategorySymbol? {
        let trimmed = symbolName.trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        guard let markerRange = trimmed.range(of: "OBJC_$_CATEGORY_") ?? trimmed.range(of: "OBJC_CATEGORY_") else {
            return nil
        }

        let remainder = String(trimmed[markerRange.upperBound...])
        let components = remainder.components(separatedBy: "_$_")
        guard components.count >= 2 else {
            return nil
        }

        let className = components[0]
        let categoryName = components[1...].joined(separator: "_$_")
        return ObjCCategorySymbol(className: className, categoryName: categoryName)
    }

    private func demangleObjCReferenceSymbol(_ symbolName: String, kind: ObjCReferenceKind) -> String {
        switch kind {
        case .classReference, .superReference:
            return demangleObjCClassSymbol(symbolName)
        case .selectorReference:
            let trimmed = symbolName.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            for prefix in ["OBJC_SELECTOR_REFERENCES_", "OBJC_METH_VAR_NAME_", "OBJC_CLASS_NAME_"] {
                if let range = trimmed.range(of: prefix) {
                    return String(trimmed[range.upperBound...]).nonEmpty(or: trimmed)
                }
            }
            return trimmed
        }
    }

    private func resolveObjCReferenceName(
        kind: ObjCReferenceKind,
        referenceVMAddress: UInt64,
        in machO: MachOFile,
        fileHandle: FileHandle
    ) -> String? {
        switch kind {
        case .classReference, .superReference:
            return resolveObjCClassName(
                at: referenceVMAddress,
                in: machO,
                sourceURL: machO.url,
                fileHandle: fileHandle
            )
        case .selectorReference:
            return resolveCString(at: referenceVMAddress, in: machO, fileHandle: fileHandle)
        }
    }

    private func cStringEntryOffsets(
        sourceURL: URL,
        absoluteOffset: Int,
        length: Int,
        chunkSize: Int = 64 * 1024
    ) -> [Int] {
        guard length > 0 else {
            return []
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: sourceURL)
        } catch {
            return []
        }
        defer {
            try? handle.close()
        }

        do {
            try handle.seek(toOffset: UInt64(absoluteOffset))
        } catch {
            return []
        }

        var remaining = length
        var currentOffset = absoluteOffset
        var currentStringStart: Int?
        var offsets: [Int] = []

        while remaining > 0 {
            let bytesToRead = min(chunkSize, remaining)
            let data = handle.readData(ofLength: bytesToRead)
            if data.isEmpty {
                break
            }

            for (index, byte) in data.enumerated() {
                if byte == 0 {
                    if let stringStart = currentStringStart {
                        offsets.append(stringStart)
                        currentStringStart = nil
                    }
                } else if currentStringStart == nil {
                    currentStringStart = currentOffset + index
                }
            }

            currentOffset += data.count
            remaining -= data.count
        }

        if let currentStringStart {
            offsets.append(currentStringStart)
        }

        return offsets
    }

    private func readCString(sourceURL: URL, offset: Int, maximumLength: Int = 4096) -> String? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: sourceURL)
        } catch {
            return nil
        }
        defer {
            try? handle.close()
        }

        return readCString(handle: handle, offset: offset, maximumLength: maximumLength)
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

private struct SpecialSectionContent {
    let childCount: Int
    let child: (Int) -> BrowserNode
    let detailCount: Int
    let detailRow: (Int) -> BrowserDetailRow
}

private struct SpecialSectionEntry {
    let title: String
    let subtitle: String?
    let detailRows: [BrowserDetailRow]
    let summaryRow: BrowserDetailRow
    let rawAddress: UInt64?
    let rvaAddress: UInt64?
    let dataRange: BrowserDataRange?

    init(
        title: String,
        subtitle: String? = nil,
        detailRows: [BrowserDetailRow],
        summaryRow: BrowserDetailRow,
        rawAddress: UInt64? = nil,
        rvaAddress: UInt64? = nil,
        dataRange: BrowserDataRange? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detailRows = detailRows
        self.summaryRow = summaryRow
        self.rawAddress = rawAddress
        self.rvaAddress = rvaAddress
        self.dataRange = dataRange
    }
}

private struct ObjCCategorySymbol {
    let className: String
    let categoryName: String

    var displayName: String {
        "\(className) (\(categoryName))"
    }
}

private struct ObjCCategoryInfo {
    let categoryName: String?
    let className: String?
}

private struct ArchiveTargetDescriptor {
    let platformName: String
    let targetName: String
}

private struct ArchiveMemberContent {
    let name: String
    let layout: ArchiveMemberLayout
    let startLength: Int
    let symtabHeaderRange: BrowserDataRange?
    let symbolTableRange: BrowserDataRange?
    let stringTableRange: BrowserDataRange?
    let symbols: [String]
    let stringEntries: [String]
}

private let archiveMagicLength = 8

private final class LazyIndexedValueCache<Value> {
    var values: [Int: Value] = [:]
}

private enum ObjCReferenceKind {
    case classReference
    case superReference
    case selectorReference

    var itemLabel: String {
        switch self {
        case .classReference:
            "Class Reference"
        case .superReference:
            "Superclass Reference"
        case .selectorReference:
            "Selector Reference"
        }
    }

    var rowValue: String {
        switch self {
        case .classReference:
            "Objective-C Class Reference"
        case .superReference:
            "Objective-C Superclass Reference"
        case .selectorReference:
            "Objective-C Selector Reference"
        }
    }
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
