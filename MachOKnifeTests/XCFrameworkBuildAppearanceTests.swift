import Foundation
import Testing
@testable import MachOKnife

struct XCFrameworkBuildAppearanceTests {
    @Test("XCFramework 拖放框保留稳定的文本内边距")
    func dropFieldUsesReadableContentInsets() {
        let insets = DropReceivingPathLabelLayoutMetrics.contentInsets

        // The compact single-line drop field (since 4705a35) uses 4pt vertical insets and a 34pt minimum height.
        #expect(insets.top >= 4)
        #expect(insets.left >= 8)
        #expect(insets.bottom >= 4)
        #expect(insets.right >= 8)
        #expect(DropReceivingPathLabelLayoutMetrics.minimumHeight >= 34)
    }

    @Test("XCFramework 拖放框在浅色空态使用有对比度的强调底色")
    func lightModePlaceholderUsesTintedSurface() {
        let style = DropReceivingPathLabelStyleResolver.resolve(
            isDark: false,
            highlighted: false,
            showsPlaceholderText: true
        )

        #expect(style.border == .subtleAccentBorder)
        #expect(style.background == .subtleAccentFill)
        #expect(style.text == .secondaryText)
    }

    @Test("XCFramework 拖放框在深色和高亮态保持可读性")
    func darkModeHighlightedUsesAccentAndPrimaryTextForContent() {
        let style = DropReceivingPathLabelStyleResolver.resolve(
            isDark: true,
            highlighted: true,
            showsPlaceholderText: false
        )

        #expect(style.border == .accentBorder)
        #expect(style.background == .accentFillDark)
        #expect(style.text == .primaryText)
    }
}
