import Foundation

/// Decodes Objective-C runtime structures (class_t, class_ro_t, method/ivar/property/protocol lists,
/// categories) from a Mach-O image into MachOView-style detail rows.
struct ObjCLayout {
    let slice: RawMachOImage

    private var pointerSize: Int { slice.pointerSize }

    static let classROFlags: [(UInt32, String)] = [
        (0x1, "RO_META"),
        (0x2, "RO_ROOT"),
        (0x4, "RO_HAS_CXX_STRUCTORS"),
        (0x10, "RO_HIDDEN"),
        (0x20, "RO_EXCEPTION"),
        (0x40, "RO_HAS_SWIFT_INITIALIZER"),
        (0x80, "RO_IS_ARC"),
        (0x100, "RO_HAS_CXX_DTOR_ONLY"),
        (0x200, "RO_HAS_WEAK_WITHOUT_ARC"),
        (0x400, "RO_FORBIDS_ASSOCIATED_OBJECTS"),
        (0x2000_0000, "RO_FROM_BUNDLE"),
        (0x4000_0000, "RO_FUTURE"),
        (0x8000_0000, "RO_REALIZED"),
    ]

    static let methodListFlags: [(UInt32, String)] = [
        (0x8000_0000, "Relative Method List"),
        (0x4000_0000, "Uses Direct Selectors"),
    ]

    static let imageInfoFlags: [(UInt32, String)] = [
        (0x1, "OBJC_IMAGE_IS_REPLACEMENT"),
        (0x2, "OBJC_IMAGE_SUPPORTS_GC"),
        (0x4, "OBJC_IMAGE_REQUIRES_GC"),
        (0x8, "OBJC_IMAGE_OPTIMIZED_BY_DYLD"),
        (0x10, "OBJC_IMAGE_SUPPORTS_COMPACTION"),
        (0x20, "OBJC_IMAGE_IS_SIMULATED"),
        (0x40, "OBJC_IMAGE_HAS_CATEGORY_CLASS_PROPERTIES"),
        (0x80, "OBJC_IMAGE_OPTIMIZED_BY_DYLD_CLOSURE"),
    ]

    // MARK: Resolution helpers

    func offset(_ pointer: ResolvedPointer) -> Int? {
        pointer.address.flatMap { slice.fileOffset(forVM: $0) }
    }

    func string(_ pointer: ResolvedPointer) -> String? {
        pointer.address.flatMap { slice.cString(atVM: $0) }
    }

    /// class_t.data carries flag bits in the low bits (Swift markers).
    func maskedDataPointer(_ pointer: ResolvedPointer) -> ResolvedPointer {
        guard case let .address(address) = pointer else { return pointer }
        return .address(address & ~UInt64(slice.is64 ? 7 : 3))
    }

    func roOffset(classOffset: Int) -> Int? {
        offset(maskedDataPointer(slice.resolvePointer(at: classOffset + 4 * pointerSize)))
    }

    func roNameOffset(_ ro: Int) -> Int {
        ro + (slice.is64 ? 16 : 12) + pointerSize
    }

    func className(classOffset: Int) -> String? {
        guard let ro = roOffset(classOffset: classOffset) else { return nil }
        return string(slice.resolvePointer(at: roNameOffset(ro)))
    }

    func className(_ pointer: ResolvedPointer) -> String {
        switch pointer {
        case .null:
            return "nil"
        case let .bind(name, _):
            return Self.stripClassPrefix(name)
        case let .address(address):
            if let classOffset = slice.fileOffset(forVM: address), let name = className(classOffset: classOffset) {
                return name
            }
            if let symbol = slice.symbolName(forVM: address) {
                return Self.stripClassPrefix(symbol)
            }
            return hex(address)
        }
    }

    static func stripClassPrefix(_ name: String) -> String {
        for prefix in ["_OBJC_CLASS_$_", "_OBJC_METACLASS_$_", "OBJC_CLASS_$_", "OBJC_METACLASS_$_"] where name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }

    func protocolName(_ pointer: ResolvedPointer) -> String {
        switch pointer {
        case .null:
            return "nil"
        case let .bind(name, _):
            return name.replacingOccurrences(of: "__OBJC_PROTOCOL_$_", with: "")
        case let .address(address):
            if let protocolOffset = slice.fileOffset(forVM: address),
               let name = string(slice.resolvePointer(at: protocolOffset + pointerSize)) {
                return name
            }
            return slice.describe(pointer)
        }
    }

    func categoryNames(categoryOffset: Int) -> (category: String, cls: String) {
        let name = string(slice.resolvePointer(at: categoryOffset)) ?? "?"
        let cls = className(slice.resolvePointer(at: categoryOffset + pointerSize))
        return (name, cls)
    }

    func selectorName(selectorReference address: UInt64) -> String? {
        guard let selref = slice.fileOffset(forVM: address) else { return nil }
        return string(slice.resolvePointer(at: selref))
    }

    private func describeString(_ pointer: ResolvedPointer) -> String {
        if let text = string(pointer) { return text }
        return slice.describe(pointer)
    }

    @discardableResult
    private func pointerField(_ rows: inout RowSink, _ offset: Int, _ key: String, _ value: (ResolvedPointer) -> String) -> ResolvedPointer {
        let pointer = slice.resolvePointer(at: offset)
        rows.field(offset, pointerSize, key, value(pointer))
        return pointer
    }

    private func relativeTarget(_ fieldOffset: Int) -> UInt64? {
        guard let fieldVM = slice.rva(forFileOffset: fieldOffset) else { return nil }
        return UInt64(bitPattern: Int64(bitPattern: fieldVM) &+ Int64(slice.i32(fieldOffset)))
    }

    private func bounded(_ count: UInt64, entrySize: Int, from start: Int) -> Int {
        guard entrySize > 0, start < slice.limit else { return 0 }
        return Int(min(count, UInt64((slice.limit - start) / entrySize)))
    }

    // MARK: class_t

    /// Rows for a class_t, its class_ro_t and the lists it references. Returns the metaclass offset.
    @discardableResult
    func classRows(_ rows: inout RowSink, classOffset: Int) -> Int? {
        let isa = pointerField(&rows, classOffset, "Isa") { slice.describe($0) }
        pointerField(&rows, classOffset + pointerSize, "Super Class") { className($0) }
        pointerField(&rows, classOffset + 2 * pointerSize, "Cache") { slice.describe($0) }
        pointerField(&rows, classOffset + 3 * pointerSize, "VTable") { slice.describe($0) }
        let data = pointerField(&rows, classOffset + 4 * pointerSize, "Data") { slice.describe($0) }
        if case let .address(raw) = data, raw & 7 != 0 {
            if raw & 1 != 0 { rows.note(padded(1, width: 1), "FAST_IS_SWIFT_LEGACY") }
            if raw & 2 != 0 { rows.note(padded(2, width: 1), "FAST_IS_SWIFT_STABLE") }
        }
        if let ro = offset(maskedDataPointer(data)) {
            rows.nextGroup()
            classRORows(&rows, ro)
        }
        return offset(isa)
    }

    func classRORows(_ rows: inout RowSink, _ ro: Int) {
        let flags = rows.u32(ro, "Flags", format: { hex($0) })
        rows.flags(flags, Self.classROFlags)
        rows.u32(ro + 4, "Instance Start")
        rows.u32(ro + 8, "Instance Size")
        var cursor = ro + 12
        if slice.is64 {
            rows.u32(cursor, "Reserved", format: { hex($0) })
            cursor += 4
        }
        pointerField(&rows, cursor, "Ivar Layout") { slice.describe($0) }
        pointerField(&rows, cursor + pointerSize, "Name") { describeString($0) }
        let methods = pointerField(&rows, cursor + 2 * pointerSize, "Base Methods") { slice.describe($0) }
        let protocols = pointerField(&rows, cursor + 3 * pointerSize, "Base Protocols") { slice.describe($0) }
        let ivars = pointerField(&rows, cursor + 4 * pointerSize, "Ivars") { slice.describe($0) }
        pointerField(&rows, cursor + 5 * pointerSize, "Weak Ivar Layout") { slice.describe($0) }
        let properties = pointerField(&rows, cursor + 6 * pointerSize, "Base Properties") { slice.describe($0) }
        let isMeta = flags & 1 != 0

        if let list = offset(methods) {
            rows.nextGroup()
            methodListRows(&rows, list, title: isMeta ? "Class Methods" : "Instance Methods", prefix: isMeta ? "+" : "-")
        }
        if let list = offset(protocols) {
            rows.nextGroup()
            protocolListRows(&rows, list)
        }
        if let list = offset(ivars) {
            rows.nextGroup()
            ivarListRows(&rows, list)
        }
        if let list = offset(properties) {
            rows.nextGroup()
            propertyListRows(&rows, list, title: isMeta ? "Class Properties" : "Properties")
        }
    }

    // MARK: Lists

    func methodListRows(_ rows: inout RowSink, _ list: Int, title: String, prefix: String) {
        let entsizeAndFlags = rows.u32(list, "\(title): Entry Size & Flags", format: { hex($0) })
        rows.flags(entsizeAndFlags & 0xFFFF_0000, Self.methodListFlags)
        let count = rows.u32(list + 4, "Count")
        let isRelative = entsizeAndFlags & 0x8000_0000 != 0
        let directSelectors = entsizeAndFlags & 0x4000_0000 != 0
        let entrySize = Int(entsizeAndFlags & 0xFFFC)
        let total = bounded(UInt64(count), entrySize: entrySize, from: list + 8)
        for index in 0..<min(total, 65_536) {
            let entry = list + 8 + index * entrySize
            rows.nextGroup()
            if isRelative {
                let nameTarget = relativeTarget(entry)
                let name = nameTarget.flatMap { directSelectors ? slice.cString(atVM: $0) : selectorName(selectorReference: $0) } ?? "?"
                rows.field(entry, 4, "Name", "\(prefix)\(name)")
                let types = relativeTarget(entry + 4).flatMap { slice.cString(atVM: $0) } ?? "?"
                rows.field(entry + 4, 4, "Types", types)
                let imp = relativeTarget(entry + 8)
                rows.field(entry + 8, 4, "Implementation", imp.map { slice.describe(.address($0)) } ?? "?")
            } else {
                let name = string(slice.resolvePointer(at: entry)) ?? "?"
                rows.field(entry, pointerSize, "Name", "\(prefix)\(name)")
                pointerField(&rows, entry + pointerSize, "Types") { describeString($0) }
                pointerField(&rows, entry + 2 * pointerSize, "Implementation") { slice.describe($0) }
            }
        }
    }

    func protocolListRows(_ rows: inout RowSink, _ list: Int) {
        let count = slice.pointer(list)
        rows.field(list, pointerSize, "Protocols: Count", "\(count)")
        let total = bounded(count, entrySize: pointerSize, from: list + pointerSize)
        for index in 0..<min(total, 65_536) {
            pointerField(&rows, list + pointerSize * (index + 1), "Protocol") { protocolName($0) }
        }
    }

    func ivarListRows(_ rows: inout RowSink, _ list: Int) {
        rows.u32(list, "Ivars: Entry Size")
        let entrySize = Int(slice.u32(list))
        let count = rows.u32(list + 4, "Count")
        let total = bounded(UInt64(count), entrySize: max(entrySize, 1), from: list + 8)
        for index in 0..<min(total, 65_536) where entrySize > 0 {
            let entry = list + 8 + index * entrySize
            rows.nextGroup()
            pointerField(&rows, entry, "Offset") { pointer in
                if let target = offset(pointer) {
                    return "\(slice.describe(pointer)) → \(slice.u32(target))"
                }
                return slice.describe(pointer)
            }
            pointerField(&rows, entry + pointerSize, "Name") { describeString($0) }
            pointerField(&rows, entry + 2 * pointerSize, "Type") { describeString($0) }
            rows.u32(entry + 3 * pointerSize, "Alignment") { raw in
                raw == UInt32.max ? "pointer" : (raw < 32 ? "\(raw) (\(1 << raw) bytes)" : "\(raw)")
            }
            rows.u32(entry + 3 * pointerSize + 4, "Size")
        }
    }

    func propertyListRows(_ rows: inout RowSink, _ list: Int, title: String) {
        rows.u32(list, "\(title): Entry Size")
        let entrySize = Int(slice.u32(list))
        let count = rows.u32(list + 4, "Count")
        let total = bounded(UInt64(count), entrySize: max(entrySize, 1), from: list + 8)
        for index in 0..<min(total, 65_536) where entrySize > 0 {
            let entry = list + 8 + index * entrySize
            rows.nextGroup()
            pointerField(&rows, entry, "Name") { describeString($0) }
            pointerField(&rows, entry + pointerSize, "Attributes") { describeString($0) }
        }
    }

    // MARK: protocol_t / category_t

    func protocolRows(_ rows: inout RowSink, _ protocolOffset: Int) {
        let p = pointerSize
        pointerField(&rows, protocolOffset, "Isa") { slice.describe($0) }
        pointerField(&rows, protocolOffset + p, "Name") { describeString($0) }
        let protocols = pointerField(&rows, protocolOffset + 2 * p, "Protocols") { slice.describe($0) }
        let instanceMethods = pointerField(&rows, protocolOffset + 3 * p, "Instance Methods") { slice.describe($0) }
        let classMethods = pointerField(&rows, protocolOffset + 4 * p, "Class Methods") { slice.describe($0) }
        let optionalInstance = pointerField(&rows, protocolOffset + 5 * p, "Optional Instance Methods") { slice.describe($0) }
        let optionalClass = pointerField(&rows, protocolOffset + 6 * p, "Optional Class Methods") { slice.describe($0) }
        let properties = pointerField(&rows, protocolOffset + 7 * p, "Instance Properties") { slice.describe($0) }
        let size = rows.u32(protocolOffset + 8 * p, "Size")
        rows.u32(protocolOffset + 8 * p + 4, "Flags", format: { hex($0) })
        let extendedStart = 8 * p + 8
        if Int(size) >= extendedStart + p {
            pointerField(&rows, protocolOffset + extendedStart, "Extended Method Types") { slice.describe($0) }
        }
        if Int(size) >= extendedStart + 2 * p {
            pointerField(&rows, protocolOffset + extendedStart + p, "Demangled Name") { describeString($0) }
        }
        var classProperties: ResolvedPointer = .null
        if Int(size) >= extendedStart + 3 * p {
            classProperties = pointerField(&rows, protocolOffset + extendedStart + 2 * p, "Class Properties") { slice.describe($0) }
        }

        if let list = offset(protocols) { rows.nextGroup(); protocolListRows(&rows, list) }
        if let list = offset(instanceMethods) { rows.nextGroup(); methodListRows(&rows, list, title: "Instance Methods", prefix: "-") }
        if let list = offset(classMethods) { rows.nextGroup(); methodListRows(&rows, list, title: "Class Methods", prefix: "+") }
        if let list = offset(optionalInstance) { rows.nextGroup(); methodListRows(&rows, list, title: "Optional Instance Methods", prefix: "-") }
        if let list = offset(optionalClass) { rows.nextGroup(); methodListRows(&rows, list, title: "Optional Class Methods", prefix: "+") }
        if let list = offset(properties) { rows.nextGroup(); propertyListRows(&rows, list, title: "Instance Properties") }
        if let list = offset(classProperties) { rows.nextGroup(); propertyListRows(&rows, list, title: "Class Properties") }
    }

    func categoryRows(_ rows: inout RowSink, _ categoryOffset: Int) {
        let p = pointerSize
        pointerField(&rows, categoryOffset, "Name") { describeString($0) }
        pointerField(&rows, categoryOffset + p, "Class") { className($0) }
        let instanceMethods = pointerField(&rows, categoryOffset + 2 * p, "Instance Methods") { slice.describe($0) }
        let classMethods = pointerField(&rows, categoryOffset + 3 * p, "Class Methods") { slice.describe($0) }
        let protocols = pointerField(&rows, categoryOffset + 4 * p, "Protocols") { slice.describe($0) }
        let properties = pointerField(&rows, categoryOffset + 5 * p, "Instance Properties") { slice.describe($0) }

        if let list = offset(instanceMethods) { rows.nextGroup(); methodListRows(&rows, list, title: "Instance Methods", prefix: "-") }
        if let list = offset(classMethods) { rows.nextGroup(); methodListRows(&rows, list, title: "Class Methods", prefix: "+") }
        if let list = offset(protocols) { rows.nextGroup(); protocolListRows(&rows, list) }
        if let list = offset(properties) { rows.nextGroup(); propertyListRows(&rows, list, title: "Instance Properties") }
    }
}
