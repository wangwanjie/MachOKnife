import Foundation

/// Symbolic names for Mach-O constants, matching the spelling used by `<mach-o/loader.h>` and MachOView.
enum MachOConstants {
    // MARK: Magic

    static let MH_MAGIC: UInt32 = 0xFEED_FACE
    static let MH_CIGAM: UInt32 = 0xCEFA_EDFE
    static let MH_MAGIC_64: UInt32 = 0xFEED_FACF
    static let MH_CIGAM_64: UInt32 = 0xCFFA_EDFE
    static let FAT_MAGIC: UInt32 = 0xCAFE_BABE
    static let FAT_MAGIC_64: UInt32 = 0xCAFE_BABF

    static func magicName(_ magic: UInt32) -> String {
        switch magic {
        case MH_MAGIC: return "MH_MAGIC"
        case MH_CIGAM: return "MH_CIGAM"
        case MH_MAGIC_64: return "MH_MAGIC_64"
        case MH_CIGAM_64: return "MH_CIGAM_64"
        case FAT_MAGIC: return "FAT_MAGIC"
        case FAT_MAGIC_64: return "FAT_MAGIC_64"
        default: return hex(magic)
        }
    }

    // MARK: CPU

    static let CPU_ARCH_ABI64: Int32 = 0x0100_0000
    static let CPU_ARCH_ABI64_32: Int32 = 0x0200_0000
    static let CPU_TYPE_X86: Int32 = 7
    static let CPU_TYPE_X86_64: Int32 = 7 | 0x0100_0000
    static let CPU_TYPE_ARM: Int32 = 12
    static let CPU_TYPE_ARM64: Int32 = 12 | 0x0100_0000
    static let CPU_TYPE_ARM64_32: Int32 = 12 | 0x0200_0000
    static let CPU_TYPE_POWERPC: Int32 = 18
    static let CPU_TYPE_POWERPC64: Int32 = 18 | 0x0100_0000

    static func cpuTypeName(_ type: Int32) -> String {
        switch type {
        case -1: return "CPU_TYPE_ANY"
        case 1: return "CPU_TYPE_VAX"
        case 6: return "CPU_TYPE_MC680x0"
        case CPU_TYPE_X86: return "CPU_TYPE_X86"
        case CPU_TYPE_X86_64: return "CPU_TYPE_X86_64"
        case 10: return "CPU_TYPE_MC98000"
        case 11: return "CPU_TYPE_HPPA"
        case CPU_TYPE_ARM: return "CPU_TYPE_ARM"
        case CPU_TYPE_ARM64: return "CPU_TYPE_ARM64"
        case CPU_TYPE_ARM64_32: return "CPU_TYPE_ARM64_32"
        case 13: return "CPU_TYPE_MC88000"
        case 14: return "CPU_TYPE_SPARC"
        case 15: return "CPU_TYPE_I860"
        case CPU_TYPE_POWERPC: return "CPU_TYPE_POWERPC"
        case CPU_TYPE_POWERPC64: return "CPU_TYPE_POWERPC64"
        default: return hex(UInt32(bitPattern: type))
        }
    }

    static let CPU_SUBTYPE_MASK: UInt32 = 0xFF00_0000

    static func cpuSubtypeName(cpuType: Int32, subtype rawSubtype: Int32) -> String {
        let subtype = UInt32(bitPattern: rawSubtype) & ~CPU_SUBTYPE_MASK
        let base: String
        switch cpuType {
        case CPU_TYPE_X86, CPU_TYPE_X86_64:
            switch subtype {
            case 3: base = cpuType == CPU_TYPE_X86_64 ? "CPU_SUBTYPE_X86_64_ALL" : "CPU_SUBTYPE_I386_ALL"
            case 4: base = "CPU_SUBTYPE_X86_ARCH1"
            case 8: base = "CPU_SUBTYPE_X86_64_H"
            default: base = "CPU_SUBTYPE_X86_\(subtype)"
            }
        case CPU_TYPE_ARM:
            switch subtype {
            case 0: base = "CPU_SUBTYPE_ARM_ALL"
            case 5: base = "CPU_SUBTYPE_ARM_V4T"
            case 6: base = "CPU_SUBTYPE_ARM_V6"
            case 7: base = "CPU_SUBTYPE_ARM_V5TEJ"
            case 8: base = "CPU_SUBTYPE_ARM_XSCALE"
            case 9: base = "CPU_SUBTYPE_ARM_V7"
            case 10: base = "CPU_SUBTYPE_ARM_V7F"
            case 11: base = "CPU_SUBTYPE_ARM_V7S"
            case 12: base = "CPU_SUBTYPE_ARM_V7K"
            case 13: base = "CPU_SUBTYPE_ARM_V8"
            case 14: base = "CPU_SUBTYPE_ARM_V6M"
            case 15: base = "CPU_SUBTYPE_ARM_V7M"
            case 16: base = "CPU_SUBTYPE_ARM_V7EM"
            case 17: base = "CPU_SUBTYPE_ARM_V8M"
            default: base = "CPU_SUBTYPE_ARM_\(subtype)"
            }
        case CPU_TYPE_ARM64:
            switch subtype {
            case 0: base = "CPU_SUBTYPE_ARM64_ALL"
            case 1: base = "CPU_SUBTYPE_ARM64_V8"
            case 2: base = "CPU_SUBTYPE_ARM64E"
            default: base = "CPU_SUBTYPE_ARM64_\(subtype)"
            }
        case CPU_TYPE_ARM64_32:
            switch subtype {
            case 0: base = "CPU_SUBTYPE_ARM64_32_ALL"
            case 1: base = "CPU_SUBTYPE_ARM64_32_V8"
            default: base = "CPU_SUBTYPE_ARM64_32_\(subtype)"
            }
        case CPU_TYPE_POWERPC, CPU_TYPE_POWERPC64:
            base = subtype == 0 ? "CPU_SUBTYPE_POWERPC_ALL" : "CPU_SUBTYPE_POWERPC_\(subtype)"
        default:
            base = hex(subtype)
        }
        return base
    }

    /// Names for the capability bits stored in the high byte of `cpusubtype`.
    static func cpuSubtypeCapabilityNames(cpuType: Int32, subtype rawSubtype: Int32) -> [(UInt32, String)] {
        let raw = UInt32(bitPattern: rawSubtype)
        var result: [(UInt32, String)] = []
        if cpuType == CPU_TYPE_ARM64, raw & ~CPU_SUBTYPE_MASK == 2 {
            if raw & 0x8000_0000 != 0 { result.append((0x8000_0000, "CPU_SUBTYPE_PTRAUTH_ABI")) }
            if raw & 0x4000_0000 != 0 { result.append((0x4000_0000, "CPU_SUBTYPE_ARM64E_KERNEL_ABI")) }
            let version = (raw & 0x0F00_0000) >> 24
            if version != 0 { result.append((raw & 0x0F00_0000, "ptrauth ABI version \(version)")) }
        } else if raw & 0x8000_0000 != 0 {
            result.append((0x8000_0000, "CPU_SUBTYPE_LIB64"))
        }
        return result
    }

    static func architectureName(cpuType: Int32, subtype: Int32) -> String {
        let masked = UInt32(bitPattern: subtype) & ~CPU_SUBTYPE_MASK
        switch cpuType {
        case CPU_TYPE_X86_64: return masked == 8 ? "x86_64h" : "x86_64"
        case CPU_TYPE_X86: return "i386"
        case CPU_TYPE_ARM64: return masked == 2 ? "arm64e" : "arm64"
        case CPU_TYPE_ARM64_32: return "arm64_32"
        case CPU_TYPE_ARM:
            switch masked {
            case 6: return "armv6"
            case 9: return "armv7"
            case 11: return "armv7s"
            case 12: return "armv7k"
            case 14: return "armv6m"
            case 15: return "armv7m"
            case 16: return "armv7em"
            default: return "arm"
            }
        case CPU_TYPE_POWERPC: return "ppc"
        case CPU_TYPE_POWERPC64: return "ppc64"
        default: return "unknown"
        }
    }

    /// Architecture spelling used by MachOView-style titles (`ARM64`, `X86_64`, `I386`, `ARM_V7`).
    static func displayArchitecture(cpuType: Int32, subtype: Int32) -> String {
        let masked = UInt32(bitPattern: subtype) & ~CPU_SUBTYPE_MASK
        switch cpuType {
        case CPU_TYPE_X86_64: return masked == 8 ? "X86_64H" : "X86_64"
        case CPU_TYPE_X86: return "I386"
        case CPU_TYPE_ARM64: return masked == 2 ? "ARM64E" : "ARM64"
        case CPU_TYPE_ARM64_32: return "ARM64_32"
        case CPU_TYPE_ARM: return architectureName(cpuType: cpuType, subtype: subtype).uppercased()
        case CPU_TYPE_POWERPC: return "PPC"
        case CPU_TYPE_POWERPC64: return "PPC64"
        default: return "UNKNOWN"
        }
    }

    // MARK: File type / header flags

    static func fileTypeName(_ type: UInt32) -> String {
        switch type {
        case 0x1: return "MH_OBJECT"
        case 0x2: return "MH_EXECUTE"
        case 0x3: return "MH_FVMLIB"
        case 0x4: return "MH_CORE"
        case 0x5: return "MH_PRELOAD"
        case 0x6: return "MH_DYLIB"
        case 0x7: return "MH_DYLINKER"
        case 0x8: return "MH_BUNDLE"
        case 0x9: return "MH_DYLIB_STUB"
        case 0xA: return "MH_DSYM"
        case 0xB: return "MH_KEXT_BUNDLE"
        case 0xC: return "MH_FILESET"
        case 0xD: return "MH_GPU_EXECUTE"
        case 0xE: return "MH_GPU_DYLIB"
        default: return hex(type)
        }
    }

    /// Human readable file type used for slice titles ("Executable", "Dynamic Library", ...).
    static func fileTypeTitle(_ type: UInt32) -> String {
        switch type {
        case 0x1: return "Object"
        case 0x2: return "Executable"
        case 0x3: return "Fixed VM Library"
        case 0x4: return "Core"
        case 0x5: return "Preloaded Executable"
        case 0x6: return "Dynamic Link Library"
        case 0x7: return "Dynamic Linker"
        case 0x8: return "Bundle"
        case 0x9: return "Dynamic Library Stub"
        case 0xA: return "Debug Symbols"
        case 0xB: return "Kernel Extension"
        case 0xC: return "File Set"
        default: return "Mach-O"
        }
    }

    static let headerFlags: [(UInt32, String)] = [
        (0x1, "MH_NOUNDEFS"),
        (0x2, "MH_INCRLINK"),
        (0x4, "MH_DYLDLINK"),
        (0x8, "MH_BINDATLOAD"),
        (0x10, "MH_PREBOUND"),
        (0x20, "MH_SPLIT_SEGS"),
        (0x40, "MH_LAZY_INIT"),
        (0x80, "MH_TWOLEVEL"),
        (0x100, "MH_FORCE_FLAT"),
        (0x200, "MH_NOMULTIDEFS"),
        (0x400, "MH_NOFIXPREBINDING"),
        (0x800, "MH_PREBINDABLE"),
        (0x1000, "MH_ALLMODSBOUND"),
        (0x2000, "MH_SUBSECTIONS_VIA_SYMBOLS"),
        (0x4000, "MH_CANONICAL"),
        (0x8000, "MH_WEAK_DEFINES"),
        (0x10000, "MH_BINDS_TO_WEAK"),
        (0x20000, "MH_ALLOW_STACK_EXECUTION"),
        (0x40000, "MH_ROOT_SAFE"),
        (0x80000, "MH_SETUID_SAFE"),
        (0x100000, "MH_NO_REEXPORTED_DYLIBS"),
        (0x200000, "MH_PIE"),
        (0x400000, "MH_DEAD_STRIPPABLE_DYLIB"),
        (0x800000, "MH_HAS_TLV_DESCRIPTORS"),
        (0x1000000, "MH_NO_HEAP_EXECUTION"),
        (0x2000000, "MH_APP_EXTENSION_SAFE"),
        (0x4000000, "MH_NLIST_OUTOFSYNC_WITH_DYLDINFO"),
        (0x8000000, "MH_SIM_SUPPORT"),
        (0x10000000, "MH_IMPLICIT_PAGEZERO"),
        (0x80000000, "MH_DYLIB_IN_CACHE"),
    ]

    // MARK: Load commands

    static let LC_REQ_DYLD: UInt32 = 0x8000_0000

    static func loadCommandName(_ cmd: UInt32) -> String {
        switch cmd {
        case 0x1: return "LC_SEGMENT"
        case 0x2: return "LC_SYMTAB"
        case 0x3: return "LC_SYMSEG"
        case 0x4: return "LC_THREAD"
        case 0x5: return "LC_UNIXTHREAD"
        case 0x6: return "LC_LOADFVMLIB"
        case 0x7: return "LC_IDFVMLIB"
        case 0x8: return "LC_IDENT"
        case 0x9: return "LC_FVMFILE"
        case 0xA: return "LC_PREPAGE"
        case 0xB: return "LC_DYSYMTAB"
        case 0xC: return "LC_LOAD_DYLIB"
        case 0xD: return "LC_ID_DYLIB"
        case 0xE: return "LC_LOAD_DYLINKER"
        case 0xF: return "LC_ID_DYLINKER"
        case 0x10: return "LC_PREBOUND_DYLIB"
        case 0x11: return "LC_ROUTINES"
        case 0x12: return "LC_SUB_FRAMEWORK"
        case 0x13: return "LC_SUB_UMBRELLA"
        case 0x14: return "LC_SUB_CLIENT"
        case 0x15: return "LC_SUB_LIBRARY"
        case 0x16: return "LC_TWOLEVEL_HINTS"
        case 0x17: return "LC_PREBIND_CKSUM"
        case 0x18 | LC_REQ_DYLD: return "LC_LOAD_WEAK_DYLIB"
        case 0x19: return "LC_SEGMENT_64"
        case 0x1A: return "LC_ROUTINES_64"
        case 0x1B: return "LC_UUID"
        case 0x1C | LC_REQ_DYLD: return "LC_RPATH"
        case 0x1D: return "LC_CODE_SIGNATURE"
        case 0x1E: return "LC_SEGMENT_SPLIT_INFO"
        case 0x1F | LC_REQ_DYLD: return "LC_REEXPORT_DYLIB"
        case 0x20: return "LC_LAZY_LOAD_DYLIB"
        case 0x21: return "LC_ENCRYPTION_INFO"
        case 0x22: return "LC_DYLD_INFO"
        case 0x22 | LC_REQ_DYLD: return "LC_DYLD_INFO_ONLY"
        case 0x23 | LC_REQ_DYLD: return "LC_LOAD_UPWARD_DYLIB"
        case 0x24: return "LC_VERSION_MIN_MACOSX"
        case 0x25: return "LC_VERSION_MIN_IPHONEOS"
        case 0x26: return "LC_FUNCTION_STARTS"
        case 0x27: return "LC_DYLD_ENVIRONMENT"
        case 0x28 | LC_REQ_DYLD: return "LC_MAIN"
        case 0x29: return "LC_DATA_IN_CODE"
        case 0x2A: return "LC_SOURCE_VERSION"
        case 0x2B: return "LC_DYLIB_CODE_SIGN_DRS"
        case 0x2C: return "LC_ENCRYPTION_INFO_64"
        case 0x2D: return "LC_LINKER_OPTION"
        case 0x2E: return "LC_LINKER_OPTIMIZATION_HINT"
        case 0x2F: return "LC_VERSION_MIN_TVOS"
        case 0x30: return "LC_VERSION_MIN_WATCHOS"
        case 0x31: return "LC_NOTE"
        case 0x32: return "LC_BUILD_VERSION"
        case 0x33 | LC_REQ_DYLD: return "LC_DYLD_EXPORTS_TRIE"
        case 0x34 | LC_REQ_DYLD: return "LC_DYLD_CHAINED_FIXUPS"
        case 0x35 | LC_REQ_DYLD: return "LC_FILESET_ENTRY"
        case 0x36: return "LC_ATOM_INFO"
        case 0x37: return "LC_FUNCTION_VARIANTS"
        case 0x38: return "LC_FUNCTION_VARIANT_FIXUPS"
        case 0x39: return "LC_TARGET_TRIPLE"
        default: return "LC_UNKNOWN (\(hex(cmd)))"
        }
    }

    // MARK: Segments / sections

    static func vmProtection(_ prot: Int32) -> String {
        let value = UInt32(bitPattern: prot)
        if value == 0 { return "VM_PROT_NONE" }
        var parts: [String] = []
        if value & 1 != 0 { parts.append("VM_PROT_READ") }
        if value & 2 != 0 { parts.append("VM_PROT_WRITE") }
        if value & 4 != 0 { parts.append("VM_PROT_EXECUTE") }
        let rest = value & ~7
        if rest != 0 { parts.append(hex(rest)) }
        return parts.joined(separator: " | ")
    }

    static func vmProtectionShort(_ prot: Int32) -> String {
        let value = UInt32(bitPattern: prot)
        return (value & 1 != 0 ? "r" : "-") + (value & 2 != 0 ? "w" : "-") + (value & 4 != 0 ? "x" : "-")
    }

    static let segmentFlags: [(UInt32, String)] = [
        (0x1, "SG_HIGHVM"),
        (0x2, "SG_FVMLIB"),
        (0x4, "SG_NORELOC"),
        (0x8, "SG_PROTECTED_VERSION_1"),
        (0x10, "SG_READ_ONLY"),
    ]

    static let SECTION_TYPE: UInt32 = 0x0000_00FF

    enum SectionType: UInt32 {
        case regular = 0x0
        case zerofill = 0x1
        case cstringLiterals = 0x2
        case fourByteLiterals = 0x3
        case eightByteLiterals = 0x4
        case literalPointers = 0x5
        case nonLazySymbolPointers = 0x6
        case lazySymbolPointers = 0x7
        case symbolStubs = 0x8
        case modInitFuncPointers = 0x9
        case modTermFuncPointers = 0xA
        case coalesced = 0xB
        case gbZerofill = 0xC
        case interposing = 0xD
        case sixteenByteLiterals = 0xE
        case dtraceDOF = 0xF
        case lazyDylibSymbolPointers = 0x10
        case threadLocalRegular = 0x11
        case threadLocalZerofill = 0x12
        case threadLocalVariables = 0x13
        case threadLocalVariablePointers = 0x14
        case threadLocalInitFunctionPointers = 0x15
        case initFuncOffsets = 0x16
    }

    static func sectionTypeName(_ type: UInt32) -> String {
        switch type {
        case 0x0: return "S_REGULAR"
        case 0x1: return "S_ZEROFILL"
        case 0x2: return "S_CSTRING_LITERALS"
        case 0x3: return "S_4BYTE_LITERALS"
        case 0x4: return "S_8BYTE_LITERALS"
        case 0x5: return "S_LITERAL_POINTERS"
        case 0x6: return "S_NON_LAZY_SYMBOL_POINTERS"
        case 0x7: return "S_LAZY_SYMBOL_POINTERS"
        case 0x8: return "S_SYMBOL_STUBS"
        case 0x9: return "S_MOD_INIT_FUNC_POINTERS"
        case 0xA: return "S_MOD_TERM_FUNC_POINTERS"
        case 0xB: return "S_COALESCED"
        case 0xC: return "S_GB_ZEROFILL"
        case 0xD: return "S_INTERPOSING"
        case 0xE: return "S_16BYTE_LITERALS"
        case 0xF: return "S_DTRACE_DOF"
        case 0x10: return "S_LAZY_DYLIB_SYMBOL_POINTERS"
        case 0x11: return "S_THREAD_LOCAL_REGULAR"
        case 0x12: return "S_THREAD_LOCAL_ZEROFILL"
        case 0x13: return "S_THREAD_LOCAL_VARIABLES"
        case 0x14: return "S_THREAD_LOCAL_VARIABLE_POINTERS"
        case 0x15: return "S_THREAD_LOCAL_INIT_FUNCTION_POINTERS"
        case 0x16: return "S_INIT_FUNC_OFFSETS"
        default: return hex(type)
        }
    }

    static func isZerofill(_ flags: UInt32) -> Bool {
        let type = flags & SECTION_TYPE
        return type == 0x1 || type == 0xC || type == 0x12
    }

    static let sectionAttributes: [(UInt32, String)] = [
        (0x8000_0000, "S_ATTR_PURE_INSTRUCTIONS"),
        (0x4000_0000, "S_ATTR_NO_TOC"),
        (0x2000_0000, "S_ATTR_STRIP_STATIC_SYMS"),
        (0x1000_0000, "S_ATTR_NO_DEAD_STRIP"),
        (0x0800_0000, "S_ATTR_LIVE_SUPPORT"),
        (0x0400_0000, "S_ATTR_SELF_MODIFYING_CODE"),
        (0x0200_0000, "S_ATTR_DEBUG"),
        (0x0000_0400, "S_ATTR_SOME_INSTRUCTIONS"),
        (0x0000_0200, "S_ATTR_EXT_RELOC"),
        (0x0000_0100, "S_ATTR_LOC_RELOC"),
    ]

    // MARK: Symbols

    static let N_STAB: UInt8 = 0xE0
    static let N_PEXT: UInt8 = 0x10
    static let N_TYPE: UInt8 = 0x0E
    static let N_EXT: UInt8 = 0x01

    static func symbolTypeName(_ type: UInt8) -> String {
        switch type & N_TYPE {
        case 0x0: return "N_UNDF"
        case 0x2: return "N_ABS"
        case 0xE: return "N_SECT"
        case 0xC: return "N_PBUD"
        case 0xA: return "N_INDR"
        default: return hex(UInt32(type & N_TYPE))
        }
    }

    static func stabName(_ type: UInt8) -> String {
        switch type {
        case 0x20: return "N_GSYM"
        case 0x22: return "N_FNAME"
        case 0x24: return "N_FUN"
        case 0x26: return "N_STSYM"
        case 0x28: return "N_LCSYM"
        case 0x2E: return "N_BNSYM"
        case 0x32: return "N_AST"
        case 0x3C: return "N_OPT"
        case 0x40: return "N_RSYM"
        case 0x44: return "N_SLINE"
        case 0x4E: return "N_ENSYM"
        case 0x60: return "N_SSYM"
        case 0x64: return "N_SO"
        case 0x66: return "N_OSO"
        case 0x6C: return "N_LIB"
        case 0x80: return "N_LSYM"
        case 0x82: return "N_BINCL"
        case 0x84: return "N_SOL"
        case 0x86: return "N_PARAMS"
        case 0x88: return "N_VERSION"
        case 0x8A: return "N_OLEVEL"
        case 0xA0: return "N_PSYM"
        case 0xA2: return "N_EINCL"
        case 0xA4: return "N_ENTRY"
        case 0xC0: return "N_LBRAC"
        case 0xC2: return "N_EXCL"
        case 0xE0: return "N_RBRAC"
        case 0xE2: return "N_BCOMM"
        case 0xE4: return "N_ECOMM"
        case 0xE8: return "N_ECOML"
        case 0xFE: return "N_LENG"
        default: return "N_STAB \(hex(UInt32(type)))"
        }
    }

    static let symbolDescriptionFlags: [(UInt16, String)] = [
        (0x0008, "N_ARM_THUMB_DEF"),
        (0x0010, "REFERENCED_DYNAMICALLY"),
        (0x0020, "N_NO_DEAD_STRIP"),
        (0x0040, "N_WEAK_REF"),
        (0x0080, "N_WEAK_DEF"),
        (0x0100, "N_SYMBOL_RESOLVER"),
        (0x0200, "N_ALT_ENTRY"),
        (0x0400, "N_COLD_FUNC"),
    ]

    static func referenceTypeName(_ desc: UInt16) -> String {
        switch desc & 0x7 {
        case 0: return "REFERENCE_FLAG_UNDEFINED_NON_LAZY"
        case 1: return "REFERENCE_FLAG_UNDEFINED_LAZY"
        case 2: return "REFERENCE_FLAG_DEFINED"
        case 3: return "REFERENCE_FLAG_PRIVATE_DEFINED"
        case 4: return "REFERENCE_FLAG_PRIVATE_UNDEFINED_NON_LAZY"
        default: return "REFERENCE_FLAG_PRIVATE_UNDEFINED_LAZY"
        }
    }

    static func libraryOrdinalName(_ ordinal: Int, dylibs: [String]) -> String {
        switch ordinal {
        case 0: return "SELF_LIBRARY_ORDINAL"
        case 0xFE: return "DYNAMIC_LOOKUP_ORDINAL"
        case 0xFF: return "EXECUTABLE_ORDINAL"
        case -1: return "BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE"
        case -2: return "BIND_SPECIAL_DYLIB_FLAT_LOOKUP"
        case -3: return "BIND_SPECIAL_DYLIB_WEAK_LOOKUP"
        default:
            if ordinal > 0, ordinal <= dylibs.count {
                return "\(ordinal) (\((dylibs[ordinal - 1] as NSString).lastPathComponent))"
            }
            return "\(ordinal) (?)"
        }
    }

    static let INDIRECT_SYMBOL_LOCAL: UInt32 = 0x8000_0000
    static let INDIRECT_SYMBOL_ABS: UInt32 = 0x4000_0000

    // MARK: Platforms / tools

    static func platformName(_ platform: UInt32) -> String {
        switch platform {
        case 1: return "PLATFORM_MACOS"
        case 2: return "PLATFORM_IOS"
        case 3: return "PLATFORM_TVOS"
        case 4: return "PLATFORM_WATCHOS"
        case 5: return "PLATFORM_BRIDGEOS"
        case 6: return "PLATFORM_MACCATALYST"
        case 7: return "PLATFORM_IOSSIMULATOR"
        case 8: return "PLATFORM_TVOSSIMULATOR"
        case 9: return "PLATFORM_WATCHOSSIMULATOR"
        case 10: return "PLATFORM_DRIVERKIT"
        case 11: return "PLATFORM_VISIONOS"
        case 12: return "PLATFORM_VISIONOSSIMULATOR"
        case 13: return "PLATFORM_FIRMWARE"
        case 14: return "PLATFORM_SEPOS"
        case 15: return "PLATFORM_MACOS_EXCLAVECORE"
        case 16: return "PLATFORM_MACOS_EXCLAVEKIT"
        case 17: return "PLATFORM_IOS_EXCLAVECORE"
        case 18: return "PLATFORM_IOS_EXCLAVEKIT"
        case 19: return "PLATFORM_TVOS_EXCLAVECORE"
        case 20: return "PLATFORM_TVOS_EXCLAVEKIT"
        case 21: return "PLATFORM_WATCHOS_EXCLAVECORE"
        case 22: return "PLATFORM_WATCHOS_EXCLAVEKIT"
        case 23: return "PLATFORM_VISIONOS_EXCLAVECORE"
        case 24: return "PLATFORM_VISIONOS_EXCLAVEKIT"
        default: return "PLATFORM_UNKNOWN (\(platform))"
        }
    }

    /// SDK-style platform name used in titles such as `Static Library (iphoneos_ARM64)`.
    static func shortPlatformName(_ platform: UInt32) -> String {
        switch platform {
        case 1: return "macos"
        case 2: return "iphoneos"
        case 3: return "tvos"
        case 4: return "watchos"
        case 5: return "bridgeos"
        case 6: return "maccatalyst"
        case 7: return "iphonesimulator"
        case 8: return "tvossimulator"
        case 9: return "watchsimulator"
        case 10: return "driverkit"
        case 11: return "xros"
        case 12: return "xrsimulator"
        case 13: return "firmware"
        case 14: return "sepos"
        case 15: return "macos_exclavecore"
        case 16: return "macos_exclavekit"
        case 17: return "ios_exclavecore"
        case 18: return "ios_exclavekit"
        case 19: return "tvos_exclavecore"
        case 20: return "tvos_exclavekit"
        case 21: return "watchos_exclavecore"
        case 22: return "watchos_exclavekit"
        case 23: return "xros_exclavecore"
        case 24: return "xros_exclavekit"
        default: return "unknown"
        }
    }

    static func toolName(_ tool: UInt32) -> String {
        switch tool {
        case 1: return "TOOL_CLANG"
        case 2: return "TOOL_SWIFT"
        case 3: return "TOOL_LD"
        case 4: return "TOOL_LLD"
        case 1024: return "TOOL_METAL"
        case 1025: return "TOOL_AIRLLD"
        case 1026: return "TOOL_AIRNT"
        case 1027: return "TOOL_AIRNT_PLUGIN"
        case 1028: return "TOOL_AIRPACK"
        case 1031: return "TOOL_GPUARCHIVER"
        case 1032: return "TOOL_METAL_FRAMEWORK"
        default: return "TOOL_UNKNOWN (\(tool))"
        }
    }

    // MARK: Dyld info

    static func rebaseTypeName(_ type: UInt8) -> String {
        switch type {
        case 1: return "REBASE_TYPE_POINTER"
        case 2: return "REBASE_TYPE_TEXT_ABSOLUTE32"
        case 3: return "REBASE_TYPE_TEXT_PCREL32"
        default: return "REBASE_TYPE_\(type)"
        }
    }

    static func bindTypeName(_ type: UInt8) -> String {
        switch type {
        case 1: return "BIND_TYPE_POINTER"
        case 2: return "BIND_TYPE_TEXT_ABSOLUTE32"
        case 3: return "BIND_TYPE_TEXT_PCREL32"
        default: return "BIND_TYPE_\(type)"
        }
    }

    static func rebaseOpcodeName(_ opcode: UInt8) -> String {
        switch opcode {
        case 0x00: return "REBASE_OPCODE_DONE"
        case 0x10: return "REBASE_OPCODE_SET_TYPE_IMM"
        case 0x20: return "REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB"
        case 0x30: return "REBASE_OPCODE_ADD_ADDR_ULEB"
        case 0x40: return "REBASE_OPCODE_ADD_ADDR_IMM_SCALED"
        case 0x50: return "REBASE_OPCODE_DO_REBASE_IMM_TIMES"
        case 0x60: return "REBASE_OPCODE_DO_REBASE_ULEB_TIMES"
        case 0x70: return "REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB"
        case 0x80: return "REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB"
        default: return "REBASE_OPCODE_UNKNOWN (\(hex(UInt32(opcode))))"
        }
    }

    static func bindOpcodeName(_ opcode: UInt8) -> String {
        switch opcode {
        case 0x00: return "BIND_OPCODE_DONE"
        case 0x10: return "BIND_OPCODE_SET_DYLIB_ORDINAL_IMM"
        case 0x20: return "BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB"
        case 0x30: return "BIND_OPCODE_SET_DYLIB_SPECIAL_IMM"
        case 0x40: return "BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM"
        case 0x50: return "BIND_OPCODE_SET_TYPE_IMM"
        case 0x60: return "BIND_OPCODE_SET_ADDEND_SLEB"
        case 0x70: return "BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB"
        case 0x80: return "BIND_OPCODE_ADD_ADDR_ULEB"
        case 0x90: return "BIND_OPCODE_DO_BIND"
        case 0xA0: return "BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB"
        case 0xB0: return "BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED"
        case 0xC0: return "BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB"
        case 0xD0: return "BIND_OPCODE_THREADED"
        default: return "BIND_OPCODE_UNKNOWN (\(hex(UInt32(opcode))))"
        }
    }

    static let exportSymbolFlags: [(UInt64, String)] = [
        (0x04, "EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION"),
        (0x08, "EXPORT_SYMBOL_FLAGS_REEXPORT"),
        (0x10, "EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER"),
        (0x20, "EXPORT_SYMBOL_FLAGS_STATIC_RESOLVER"),
    ]

    static func exportKindName(_ flags: UInt64) -> String {
        switch flags & 0x3 {
        case 0: return "EXPORT_SYMBOL_FLAGS_KIND_REGULAR"
        case 1: return "EXPORT_SYMBOL_FLAGS_KIND_THREAD_LOCAL"
        case 2: return "EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE"
        default: return "EXPORT_SYMBOL_FLAGS_KIND_UNKNOWN"
        }
    }

    // MARK: Chained fixups

    static func chainedPointerFormatName(_ format: UInt16) -> String {
        switch format {
        case 1: return "DYLD_CHAINED_PTR_ARM64E"
        case 2: return "DYLD_CHAINED_PTR_64"
        case 3: return "DYLD_CHAINED_PTR_32"
        case 4: return "DYLD_CHAINED_PTR_32_CACHE"
        case 5: return "DYLD_CHAINED_PTR_32_FIRMWARE"
        case 6: return "DYLD_CHAINED_PTR_64_OFFSET"
        case 7: return "DYLD_CHAINED_PTR_ARM64E_KERNEL"
        case 8: return "DYLD_CHAINED_PTR_64_KERNEL_CACHE"
        case 9: return "DYLD_CHAINED_PTR_ARM64E_USERLAND"
        case 10: return "DYLD_CHAINED_PTR_ARM64E_FIRMWARE"
        case 11: return "DYLD_CHAINED_PTR_X86_64_KERNEL_CACHE"
        case 12: return "DYLD_CHAINED_PTR_ARM64E_USERLAND24"
        case 13: return "DYLD_CHAINED_PTR_ARM64E_SHARED_CACHE"
        case 14: return "DYLD_CHAINED_PTR_ARM64E_SEGMENTED"
        default: return "DYLD_CHAINED_PTR_UNKNOWN (\(format))"
        }
    }

    static func chainedImportFormatName(_ format: UInt32) -> String {
        switch format {
        case 1: return "DYLD_CHAINED_IMPORT"
        case 2: return "DYLD_CHAINED_IMPORT_ADDEND"
        case 3: return "DYLD_CHAINED_IMPORT_ADDEND64"
        default: return "DYLD_CHAINED_IMPORT_UNKNOWN (\(format))"
        }
    }

    static func chainedSymbolsFormatName(_ format: UInt32) -> String {
        format == 0 ? "UNCOMPRESSED" : (format == 1 ? "ZLIB" : "\(format)")
    }

    /// Stride between chain entries, in bytes.
    static func chainedPointerStride(_ format: UInt16) -> Int {
        switch format {
        case 1, 9, 12, 13: return 8
        case 11: return 1
        default: return 4
        }
    }

    // MARK: Data in code

    static func dataInCodeKindName(_ kind: UInt16) -> String {
        switch kind {
        case 1: return "DICE_KIND_DATA"
        case 2: return "DICE_KIND_JUMP_TABLE8"
        case 3: return "DICE_KIND_JUMP_TABLE16"
        case 4: return "DICE_KIND_JUMP_TABLE32"
        case 5: return "DICE_KIND_ABS_JUMP_TABLE32"
        default: return "DICE_KIND_UNKNOWN (\(kind))"
        }
    }

    // MARK: Code signature

    static func codeSignatureMagicName(_ magic: UInt32) -> String {
        switch magic {
        case 0xFADE_0C02: return "CSMAGIC_CODEDIRECTORY"
        case 0xFADE_0CC0: return "CSMAGIC_EMBEDDED_SIGNATURE"
        case 0xFADE_0B02: return "CSMAGIC_EMBEDDED_SIGNATURE_OLD"
        case 0xFADE_0C00: return "CSMAGIC_REQUIREMENT"
        case 0xFADE_0C01: return "CSMAGIC_REQUIREMENTS"
        case 0xFADE_7171: return "CSMAGIC_EMBEDDED_ENTITLEMENTS"
        case 0xFADE_7172: return "CSMAGIC_EMBEDDED_DER_ENTITLEMENTS"
        case 0xFADE_7173: return "CSMAGIC_EMBEDDED_LAUNCH_CONSTRAINT"
        case 0xFADE_0CC1: return "CSMAGIC_DETACHED_SIGNATURE"
        case 0xFADE_0B01: return "CSMAGIC_BLOBWRAPPER"
        default: return hex(magic)
        }
    }

    static func codeSignatureSlotName(_ slot: UInt32) -> String {
        switch slot {
        case 0: return "CSSLOT_CODEDIRECTORY"
        case 1: return "CSSLOT_INFOSLOT"
        case 2: return "CSSLOT_REQUIREMENTS"
        case 3: return "CSSLOT_RESOURCEDIR"
        case 4: return "CSSLOT_APPLICATION"
        case 5: return "CSSLOT_ENTITLEMENTS"
        case 6: return "CSSLOT_REP_SPECIFIC"
        case 7: return "CSSLOT_DER_ENTITLEMENTS"
        case 8: return "CSSLOT_LAUNCH_CONSTRAINT_SELF"
        case 9: return "CSSLOT_LAUNCH_CONSTRAINT_PARENT"
        case 10: return "CSSLOT_LAUNCH_CONSTRAINT_RESPONSIBLE"
        case 11: return "CSSLOT_LIBRARY_CONSTRAINT"
        case 0x1000...0x1004: return "CSSLOT_ALTERNATE_CODEDIRECTORIES + \(slot - 0x1000)"
        case 0x10000: return "CSSLOT_SIGNATURESLOT"
        case 0x10001: return "CSSLOT_IDENTIFICATIONSLOT"
        case 0x10002: return "CSSLOT_TICKETSLOT"
        default: return hex(slot)
        }
    }

    static func specialSlotName(_ index: Int) -> String {
        switch index {
        case 1: return "Info.plist"
        case 2: return "Requirements"
        case 3: return "Resource Directory"
        case 4: return "Application Specific"
        case 5: return "Entitlements"
        case 6: return "Rep Specific"
        case 7: return "DER Entitlements"
        case 8: return "Launch Constraint (self)"
        case 9: return "Launch Constraint (parent)"
        case 10: return "Launch Constraint (responsible)"
        case 11: return "Library Constraint"
        default: return "Special Slot \(index)"
        }
    }

    static func hashTypeName(_ type: UInt8) -> String {
        switch type {
        case 0: return "CS_HASHTYPE_NOHASH"
        case 1: return "CS_HASHTYPE_SHA1"
        case 2: return "CS_HASHTYPE_SHA256"
        case 3: return "CS_HASHTYPE_SHA256_TRUNCATED"
        case 4: return "CS_HASHTYPE_SHA384"
        case 5: return "CS_HASHTYPE_SHA512"
        default: return "CS_HASHTYPE_\(type)"
        }
    }

    static let codeDirectoryFlags: [(UInt32, String)] = [
        (0x0000_0001, "CS_VALID"),
        (0x0000_0002, "CS_ADHOC"),
        (0x0000_0004, "CS_GET_TASK_ALLOW"),
        (0x0000_0008, "CS_INSTALLER"),
        (0x0000_0010, "CS_FORCED_LV"),
        (0x0000_0020, "CS_INVALID_ALLOWED"),
        (0x0000_0100, "CS_HARD"),
        (0x0000_0200, "CS_KILL"),
        (0x0000_0400, "CS_CHECK_EXPIRATION"),
        (0x0000_0800, "CS_RESTRICT"),
        (0x0000_1000, "CS_ENFORCEMENT"),
        (0x0000_2000, "CS_REQUIRE_LV"),
        (0x0000_4000, "CS_ENTITLEMENTS_VALIDATED"),
        (0x0000_8000, "CS_NVRAM_UNRESTRICTED"),
        (0x0001_0000, "CS_RUNTIME"),
        (0x0002_0000, "CS_LINKER_SIGNED"),
    ]

    static let execSegmentFlags: [(UInt64, String)] = [
        (0x1, "CS_EXECSEG_MAIN_BINARY"),
        (0x10, "CS_EXECSEG_ALLOW_UNSIGNED"),
        (0x20, "CS_EXECSEG_DEBUGGER"),
        (0x40, "CS_EXECSEG_JIT"),
        (0x80, "CS_EXECSEG_SKIP_LV"),
        (0x100, "CS_EXECSEG_CAN_LOAD_CDHASH"),
        (0x200, "CS_EXECSEG_CAN_EXEC_CDHASH"),
    ]

    // MARK: Relocations

    static func relocationTypeName(cpuType: Int32, type: UInt8) -> String {
        switch cpuType {
        case CPU_TYPE_X86_64:
            let names = [
                "X86_64_RELOC_UNSIGNED", "X86_64_RELOC_SIGNED", "X86_64_RELOC_BRANCH", "X86_64_RELOC_GOT_LOAD",
                "X86_64_RELOC_GOT", "X86_64_RELOC_SUBTRACTOR", "X86_64_RELOC_SIGNED_1", "X86_64_RELOC_SIGNED_2",
                "X86_64_RELOC_SIGNED_4", "X86_64_RELOC_TLV",
            ]
            return Int(type) < names.count ? names[Int(type)] : "X86_64_RELOC_\(type)"
        case CPU_TYPE_ARM64, CPU_TYPE_ARM64_32:
            let names = [
                "ARM64_RELOC_UNSIGNED", "ARM64_RELOC_SUBTRACTOR", "ARM64_RELOC_BRANCH26", "ARM64_RELOC_PAGE21",
                "ARM64_RELOC_PAGEOFF12", "ARM64_RELOC_GOT_LOAD_PAGE21", "ARM64_RELOC_GOT_LOAD_PAGEOFF12",
                "ARM64_RELOC_POINTER_TO_GOT", "ARM64_RELOC_TLVP_LOAD_PAGE21", "ARM64_RELOC_TLVP_LOAD_PAGEOFF12",
                "ARM64_RELOC_ADDEND", "ARM64_RELOC_AUTHENTICATED_POINTER",
            ]
            return Int(type) < names.count ? names[Int(type)] : "ARM64_RELOC_\(type)"
        case CPU_TYPE_ARM:
            let names = [
                "ARM_RELOC_VANILLA", "ARM_RELOC_PAIR", "ARM_RELOC_SECTDIFF", "ARM_RELOC_LOCAL_SECTDIFF",
                "ARM_RELOC_PB_LA_PTR", "ARM_RELOC_BR24", "ARM_THUMB_RELOC_BR22", "ARM_THUMB_32BIT_BRANCH",
                "ARM_RELOC_HALF", "ARM_RELOC_HALF_SECTDIFF",
            ]
            return Int(type) < names.count ? names[Int(type)] : "ARM_RELOC_\(type)"
        default:
            let names = [
                "GENERIC_RELOC_VANILLA", "GENERIC_RELOC_PAIR", "GENERIC_RELOC_SECTDIFF", "GENERIC_RELOC_PB_LA_PTR",
                "GENERIC_RELOC_LOCAL_SECTDIFF", "GENERIC_RELOC_TLV",
            ]
            return Int(type) < names.count ? names[Int(type)] : "GENERIC_RELOC_\(type)"
        }
    }

    // MARK: Formatting

    static func hex(_ value: UInt32) -> String { String(format: "0x%X", value) }
    static func hex(_ value: UInt64) -> String { String(format: "0x%llX", value) }

    static func version(_ packed: UInt32) -> String {
        let major = packed >> 16
        let minor = (packed >> 8) & 0xFF
        let patch = packed & 0xFF
        return "\(major).\(minor).\(patch)"
    }

    static func sourceVersion(_ packed: UInt64) -> String {
        let a = packed >> 40
        let b = (packed >> 30) & 0x3FF
        let c = (packed >> 20) & 0x3FF
        let d = (packed >> 10) & 0x3FF
        let e = packed & 0x3FF
        return "\(a).\(b).\(c).\(d).\(e)"
    }
}
