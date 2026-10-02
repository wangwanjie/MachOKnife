import Foundation

extension MachOLayoutBuilder {
    func loadCommandsNode() -> BrowserNode {
        let commands = slice.commands
        let slice = slice
        let start = slice.base + slice.headerSize
        return factory.node(
            id: id("loadCommands"),
            title: "Load Commands (\(commands.count))",
            summaryStyle: .group,
            range: range(start, Int(slice.sizeofcmds)),
            rows: {
                var rows = RowSink(slice: slice)
                for command in commands {
                    rows.field(command.offset, 4, MachOConstants.loadCommandName(command.cmd), loadCommandSummary(command))
                    rows.nextGroup()
                }
                return rows.rows
            },
            children: commands.map { command in { loadCommandNode(command) } }
        )
    }

    func loadCommandTitle(_ command: RawMachOImage.LoadCommandRecord) -> String {
        let name = MachOConstants.loadCommandName(command.cmd)
        let detail = loadCommandShortDetail(command)
        return detail.isEmpty ? name : "\(name) (\(detail))"
    }

    private func loadCommandShortDetail(_ command: RawMachOImage.LoadCommandRecord) -> String {
        switch command.cmd {
        case 0x1, 0x19:
            return slice.reader.fixedString(at: command.offset + 8, count: 16) ?? ""
        case 0xC, 0xD, 0x18 | MachOConstants.LC_REQ_DYLD, 0x1F | MachOConstants.LC_REQ_DYLD, 0x20, 0x23 | MachOConstants.LC_REQ_DYLD:
            let path = slice.loadCommandString(commandOffset: command.offset, commandSize: command.size, fieldOffset: 8)
            return libraryDisplayName(path)
        case 0x1C | MachOConstants.LC_REQ_DYLD:
            return slice.loadCommandString(commandOffset: command.offset, commandSize: command.size, fieldOffset: 8)
        case 0x32:
            return MachOConstants.platformName(slice.u32(command.offset + 8))
        default:
            return ""
        }
    }

    private func libraryDisplayName(_ path: String) -> String {
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }

    func loadCommandSummary(_ command: RawMachOImage.LoadCommandRecord) -> String {
        let o = command.offset
        switch command.cmd {
        case 0x1, 0x19:
            let name = slice.reader.fixedString(at: o + 8, count: 16) ?? ""
            return name.isEmpty ? "(unnamed)" : name
        case 0xC, 0xD, 0xE, 0xF, 0x27, 0x18 | MachOConstants.LC_REQ_DYLD, 0x1F | MachOConstants.LC_REQ_DYLD, 0x20,
             0x23 | MachOConstants.LC_REQ_DYLD, 0x1C | MachOConstants.LC_REQ_DYLD, 0x12, 0x13, 0x14, 0x15, 0x39:
            return slice.loadCommandString(commandOffset: o, commandSize: command.size, fieldOffset: 8)
        case 0x1B:
            return slice.uuid ?? ""
        case 0x32:
            return "\(MachOConstants.platformName(slice.u32(o + 8))) \(MachOConstants.version(slice.u32(o + 12)))"
        case 0x24, 0x25, 0x2F, 0x30:
            return MachOConstants.version(slice.u32(o + 8))
        case 0x2A:
            return MachOConstants.sourceVersion(slice.u64(o + 8))
        case 0x28 | MachOConstants.LC_REQ_DYLD:
            return "entryoff \(hex(slice.u64(o + 8)))"
        default:
            return "\(command.size) bytes"
        }
    }

    func loadCommandNode(_ command: RawMachOImage.LoadCommandRecord) -> BrowserNode {
        let slice = slice
        let builder = self
        var children: [() -> BrowserNode] = []
        if command.cmd == 0x1 || command.cmd == 0x19,
           let segment = slice.segments.first(where: { $0.commandIndex == command.index }) {
            children = slice.sections[segment.sectionRange].map { section in
                { builder.sectionHeaderNode(section) }
            }
        }
        return factory.node(
            id: id("loadCommands", "\(command.index)"),
            title: loadCommandTitle(command),
            range: range(command.offset, command.size),
            rows: { builder.loadCommandRows(command) },
            children: children
        )
    }

    func sectionHeaderNode(_ section: RawMachOImage.Section) -> BrowserNode {
        let slice = slice
        let size = slice.is64 ? 80 : 68
        return factory.node(
            id: id("sectionHeaders", "\(section.ordinal)"),
            title: "Section Header (\(section.name))",
            range: range(section.headerOffset, size),
            rows: {
                var rows = RowSink(slice: slice)
                let o = section.headerOffset
                rows.bytes(o, 16, "Section Name", section.name)
                rows.bytes(o + 16, 16, "Segment Name", section.segmentName)
                if slice.is64 {
                    rows.hex64(o + 32, "Address")
                    rows.u64(o + 40, "Size", format: byteCount)
                } else {
                    rows.hex32(o + 32, "Address")
                    rows.u32(o + 36, "Size", format: { byteCount(UInt64($0)) })
                }
                let f = o + (slice.is64 ? 48 : 40)
                rows.u32(f, "Offset", format: { section.isZerofill ? "\($0) (zero fill)" : hex($0) })
                rows.u32(f + 4, "Alignment", format: { "2^\($0) (\(1 << min($0, 63)))" })
                rows.u32(f + 8, "Relocations Offset", format: { hex($0) })
                rows.u32(f + 12, "Number of Relocations")
                rows.u32(f + 16, "Flags", format: { hex($0) })
                rows.note(padded(UInt64(section.type), width: 4), MachOConstants.sectionTypeName(section.type))
                rows.flags(section.flags & ~MachOConstants.SECTION_TYPE, MachOConstants.sectionAttributes)
                rows.u32(f + 20, "Reserved1", format: { value in
                    switch section.type {
                    case 0x6, 0x7, 0x8, 0x10, 0x14: return "\(value) (indirect symbol index)"
                    default: return "\(value)"
                    }
                })
                rows.u32(f + 24, "Reserved2", format: { value in
                    section.type == 0x8 ? "\(value) (stub size)" : "\(value)"
                })
                if slice.is64 {
                    rows.u32(f + 28, "Reserved3")
                }
                return rows.rows
            }
        )
    }

    // MARK: Command fields

    func loadCommandRows(_ command: RawMachOImage.LoadCommandRecord) -> [BrowserDetailRow] {
        var rows = sink()
        let o = command.offset
        let end = command.offset + command.size
        rows.field(o, 4, "Command", MachOConstants.loadCommandName(command.cmd))
        rows.u32(o + 4, "Command Size")

        func lcString(_ fieldOffset: Int, _ key: String) {
            let stringOffset = Int(slice.u32(o + fieldOffset))
            rows.u32(o + fieldOffset, "Str Offset")
            if stringOffset >= 8, stringOffset < command.size,
               let decoded = slice.reader.cString(at: o + stringOffset, limit: end) {
                rows.bytes(o + stringOffset, decoded.length + 1, key, decoded.string)
            }
        }

        func linkEditPair(_ offsetKey: String, _ sizeKey: String, at field: Int) {
            rows.u32(o + field, offsetKey, format: { hex($0) })
            rows.u32(o + field + 4, sizeKey)
        }

        switch command.cmd {
        case 0x1, 0x19:
            let wide = command.cmd == 0x19
            rows.bytes(o + 8, 16, "Segment Name", slice.reader.fixedString(at: o + 8, count: 16) ?? "")
            if wide {
                rows.hex64(o + 24, "VM Address")
                rows.u64(o + 32, "VM Size", format: byteCount)
                rows.u64(o + 40, "File Offset", format: { hex($0) })
                rows.u64(o + 48, "File Size", format: byteCount)
            } else {
                rows.hex32(o + 24, "VM Address")
                rows.u32(o + 28, "VM Size", format: { byteCount(UInt64($0)) })
                rows.u32(o + 32, "File Offset", format: { hex($0) })
                rows.u32(o + 36, "File Size", format: { byteCount(UInt64($0)) })
            }
            let p = o + (wide ? 56 : 40)
            rows.u32(p, "Maximum VM Protection", format: { MachOConstants.vmProtection(Int32(bitPattern: $0)) })
            rows.u32(p + 4, "Initial VM Protection", format: { MachOConstants.vmProtection(Int32(bitPattern: $0)) })
            rows.u32(p + 8, "Number of Sections")
            let flags = rows.u32(p + 12, "Flags", format: { hex($0) })
            rows.flags(flags, MachOConstants.segmentFlags)
        case 0x2:
            linkEditPair("Symbol Table Offset", "Number of Symbols", at: 8)
            linkEditPair("String Table Offset", "String Table Size", at: 16)
        case 0xB:
            let names = [
                ("LocSymbol Index", false), ("LocSymbol Number", false),
                ("Defined ExtSymbol Index", false), ("Defined ExtSymbol Number", false),
                ("Undefined ExtSymbol Index", false), ("Undefined ExtSymbol Number", false),
                ("TOC Offset", true), ("TOC Entries", false),
                ("Module Table Offset", true), ("Module Table Entries", false),
                ("ExtRef Table Offset", true), ("ExtRef Table Entries", false),
                ("IndSym Table Offset", true), ("IndSym Table Entries", false),
                ("ExtReloc Table Offset", true), ("ExtReloc Table Entries", false),
                ("LocReloc Table Offset", true), ("LocReloc Table Entries", false),
            ]
            for (index, entry) in names.enumerated() {
                rows.u32(o + 8 + index * 4, entry.0, format: { entry.1 ? hex($0) : "\($0)" })
            }
        case 0xC, 0xD, 0x18 | MachOConstants.LC_REQ_DYLD, 0x1F | MachOConstants.LC_REQ_DYLD, 0x20, 0x23 | MachOConstants.LC_REQ_DYLD:
            lcString(8, "Name")
            let marker = slice.u32(o + 12)
            if marker == 0x1A74_1800, command.size >= 28 {
                rows.u32(o + 12, "Marker", format: { "\(hex($0)) (dylib_use_command)" })
                rows.u32(o + 16, "Current Version", format: MachOConstants.version)
                rows.u32(o + 20, "Compatibility Version", format: MachOConstants.version)
                let flags = rows.u32(o + 24, "Flags", format: { hex($0) })
                rows.flags(flags, [
                    (UInt32(1), "DYLIB_USE_WEAK_LINK"), (2, "DYLIB_USE_REEXPORT"),
                    (4, "DYLIB_USE_UPWARD"), (8, "DYLIB_USE_DELAYED_INIT"),
                ])
            } else {
                rows.u32(o + 12, "Time Stamp", format: { value in
                    let date = Date(timeIntervalSince1970: TimeInterval(value))
                    return "\(value) (\(Self.timestampFormatter.string(from: date)))"
                })
                rows.u32(o + 16, "Current Version", format: MachOConstants.version)
                rows.u32(o + 20, "Compatibility Version", format: MachOConstants.version)
            }
        case 0xE, 0xF, 0x27:
            lcString(8, "Name")
        case 0x12:
            lcString(8, "Umbrella")
        case 0x13:
            lcString(8, "Sub Umbrella")
        case 0x14:
            lcString(8, "Client")
        case 0x15:
            lcString(8, "Sub Library")
        case 0x39:
            lcString(8, "Target Triple")
        case 0x1C | MachOConstants.LC_REQ_DYLD:
            lcString(8, "Path")
        case 0x1B:
            rows.bytes(o + 8, 16, "UUID", slice.uuid ?? "")
        case 0x24, 0x25, 0x2F, 0x30:
            rows.u32(o + 8, "Version", format: MachOConstants.version)
            rows.u32(o + 12, "SDK", format: MachOConstants.version)
        case 0x32:
            rows.u32(o + 8, "Platform", format: MachOConstants.platformName)
            rows.u32(o + 12, "Minimum OS Version", format: MachOConstants.version)
            rows.u32(o + 16, "SDK Version", format: MachOConstants.version)
            let count = rows.u32(o + 20, "Number of Tools")
            for index in 0..<Int(count) {
                let t = o + 24 + index * 8
                guard t + 8 <= end else { break }
                rows.nextGroup()
                rows.u32(t, "Tool", format: MachOConstants.toolName)
                rows.u32(t + 4, "Version", format: MachOConstants.version)
            }
        case 0x2A:
            rows.u64(o + 8, "Version", format: MachOConstants.sourceVersion)
        case 0x28 | MachOConstants.LC_REQ_DYLD:
            let entry = rows.u64(o + 8, "Entry Offset", format: { hex($0) })
            if let vm = slice.rva(forFileOffset: slice.base + Int(clamping: entry)) {
                rows.note("Entry Point", hex(vm))
            }
            rows.u64(o + 16, "Stack Size")
        case 0x1D, 0x1E, 0x26, 0x29, 0x2B, 0x2E, 0x33 | MachOConstants.LC_REQ_DYLD, 0x34 | MachOConstants.LC_REQ_DYLD, 0x36, 0x37, 0x38:
            linkEditPair("Data Offset", "Data Size", at: 8)
        case 0x22, 0x22 | MachOConstants.LC_REQ_DYLD:
            linkEditPair("Rebase Info Offset", "Rebase Info Size", at: 8)
            linkEditPair("Binding Info Offset", "Binding Info Size", at: 16)
            linkEditPair("Weak Binding Info Offset", "Weak Binding Info Size", at: 24)
            linkEditPair("Lazy Binding Info Offset", "Lazy Binding Info Size", at: 32)
            linkEditPair("Export Info Offset", "Export Info Size", at: 40)
        case 0x21, 0x2C:
            rows.u32(o + 8, "Crypt Offset", format: { hex($0) })
            rows.u32(o + 12, "Crypt Size")
            rows.u32(o + 16, "Crypt ID", format: { $0 == 0 ? "0 (not encrypted)" : "\($0)" })
            if command.cmd == 0x2C {
                rows.u32(o + 20, "Pad")
            }
        case 0x2D:
            let count = rows.u32(o + 8, "Number of Strings")
            var cursor = o + 12
            for index in 0..<Int(count) {
                guard cursor < end, let decoded = slice.reader.cString(at: cursor, limit: end) else { break }
                rows.bytes(cursor, decoded.length + 1, "String \(index)", decoded.string)
                cursor += decoded.length + 1
            }
        case 0x11, 0x1A:
            let wide = command.cmd == 0x1A
            let step = wide ? 8 : 4
            let names = ["Init Address", "Init Module", "Reserved1", "Reserved2", "Reserved3", "Reserved4", "Reserved5", "Reserved6"]
            for (index, name) in names.enumerated() {
                let field = o + 8 + index * step
                guard field + step <= end else { break }
                if wide {
                    rows.u64(field, name, format: { index == 0 ? hex($0) : "\($0)" })
                } else {
                    rows.u32(field, name, format: { index == 0 ? hex($0) : "\($0)" })
                }
            }
        case 0x4, 0x5:
            threadRows(&rows, start: o + 8, end: end)
        case 0x16:
            rows.u32(o + 8, "Offset", format: { hex($0) })
            rows.u32(o + 12, "Number of Hints")
        case 0x17:
            rows.u32(o + 8, "Checksum", format: { hex($0) })
        case 0x10:
            lcString(8, "Name")
            rows.u32(o + 12, "Number of Modules")
            rows.u32(o + 16, "Linked Modules Offset", format: { hex($0) })
        case 0x6, 0x7:
            lcString(8, "Name")
            rows.u32(o + 12, "Minor Version")
            rows.u32(o + 16, "Header Address", format: { hex($0) })
        case 0x9:
            lcString(8, "Name")
            rows.u32(o + 12, "Header Address", format: { hex($0) })
        case 0x3:
            rows.u32(o + 8, "Offset", format: { hex($0) })
            rows.u32(o + 12, "Size")
        case 0x31:
            rows.bytes(o + 8, 16, "Data Owner", slice.reader.fixedString(at: o + 8, count: 16) ?? "")
            rows.u64(o + 24, "Offset", format: { hex($0) })
            rows.u64(o + 32, "Size")
        case 0x35 | MachOConstants.LC_REQ_DYLD:
            rows.hex64(o + 8, "VM Address")
            rows.u64(o + 16, "File Offset", format: { hex($0) })
            lcString(24, "Entry ID")
            rows.u32(o + 28, "Reserved")
        default:
            var cursor = o + 8
            while cursor + 4 <= end {
                rows.hex32(cursor, "Data")
                cursor += 4
            }
        }
        return rows.rows
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter
    }()

    private func threadRows(_ rows: inout RowSink, start: Int, end: Int) {
        var cursor = start
        while cursor + 8 <= end {
            let flavor = slice.u32(cursor)
            let count = Int(slice.u32(cursor + 4))
            let names = threadRegisterNames(flavor: flavor)
            rows.u32(cursor, "Flavor", format: { "\($0) (\(names.flavor))" })
            rows.u32(cursor + 4, "Count")
            cursor += 8
            let stateEnd = min(end, cursor + count * 4)
            var registerIndex = 0
            while cursor < stateEnd {
                let width = registerIndex < names.registers.count ? names.registers[registerIndex].1 : 4
                guard cursor + width <= stateEnd else { break }
                let name = registerIndex < names.registers.count ? names.registers[registerIndex].0 : "state[\(registerIndex)]"
                if width == 8 {
                    rows.hex64(cursor, name)
                } else {
                    rows.hex32(cursor, name)
                }
                cursor += width
                registerIndex += 1
            }
            cursor = max(cursor, stateEnd)
            rows.nextGroup()
        }
    }

    private func threadRegisterNames(flavor: UInt32) -> (flavor: String, registers: [(String, Int)]) {
        switch (slice.cputype, flavor) {
        case (MachOConstants.CPU_TYPE_X86_64, 4):
            let names = ["rax", "rbx", "rcx", "rdx", "rdi", "rsi", "rbp", "rsp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip", "rflags", "cs", "fs", "gs"]
            return ("x86_THREAD_STATE64", names.map { ($0, 8) })
        case (MachOConstants.CPU_TYPE_X86, 1), (MachOConstants.CPU_TYPE_X86_64, 1):
            let names = ["eax", "ebx", "ecx", "edx", "edi", "esi", "ebp", "esp", "ss", "eflags", "eip", "cs", "ds", "es", "fs", "gs"]
            return ("x86_THREAD_STATE32", names.map { ($0, 4) })
        case (MachOConstants.CPU_TYPE_ARM64, 6), (MachOConstants.CPU_TYPE_ARM64_32, 6):
            let names = (0...28).map { ("x\($0)", 8) } + [("fp", 8), ("lr", 8), ("sp", 8), ("pc", 8), ("cpsr", 4), ("pad", 4)]
            return ("ARM_THREAD_STATE64", names)
        case (MachOConstants.CPU_TYPE_ARM, 1):
            let names = (0...12).map { ("r\($0)", 4) } + [("sp", 4), ("lr", 4), ("pc", 4), ("cpsr", 4)]
            return ("ARM_THREAD_STATE", names)
        default:
            return ("flavor \(flavor)", [])
        }
    }
}
