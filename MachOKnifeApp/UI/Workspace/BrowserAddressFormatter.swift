import Foundation

/// Formats browser addresses the way MachOView does: 8 hex digits for values that fit in
/// 32 bits (file offsets, 32-bit images) and 16 digits for 64-bit virtual addresses.
enum BrowserAddressFormatter {
    static func string(_ value: UInt64) -> String {
        value > UInt64(UInt32.max) ? String(format: "%016llX", value) : String(format: "%08llX", value)
    }
}
