# MachOKit Browser Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current summary-style workspace with a MachOKit-backed tree/details/hex browser, add confirmed close-file reset flow, and prepare deferred retag/modify entry points without implementing binary rewriting in this pass.

**Architecture:** Keep the existing AppKit shell, recent-files flow, localization, and updater behavior, but replace the document browsing state with a generic `MachOKit` node browser. The main window becomes a two-pane workspace: left outline tree, right details/hex tabs backed by a new browser document model that can load Mach-O files, fat binaries, `dyld_shared_cache`, and future memory-image inputs through one service layer.

**Tech Stack:** AppKit, Combine, Swift Package Manager, MachOKit, XCTest/Testing, existing MachOKnife localization and menu infrastructure

---

## Planned File Structure

- Modify: `MachOKnife.xcodeproj/project.pbxproj`
- Modify: `Packages/MachOKnifeKit/Package.swift`
- Modify: `Packages/MachOKnifeKit/Sources/MachOKnifeKit/MachOKnifeKit.swift`
- Create: `Packages/MachOKnifeKit/Sources/MachOKnifeKit/Browser/`
- Create: `Packages/MachOKnifeKit/Tests/MachOKnifeKitTests/BrowserDocumentServiceTests.swift`
- Modify: `MachOKnifeApp/ViewModels/WorkspaceViewModel.swift`
- Modify: `MachOKnifeTests/WorkspaceViewModelTests.swift`
- Modify: `MachOKnifeApp/AppDelegate.swift`
- Modify: `MachOKnifeApp/UI/MainWindowController.swift`
- Modify: `MachOKnifeApp/UI/Workspace/WorkspaceSplitViewController.swift`
- Modify: `MachOKnifeApp/UI/Workspace/SourceListViewController.swift`
- Modify: `MachOKnifeApp/UI/Workspace/DetailViewController.swift`
- Modify: `MachOKnifeApp/UI/Workspace/InspectorViewController.swift`
- Create: `MachOKnifeApp/UI/Workspace/BrowserTabViewController.swift`
- Create: `MachOKnifeApp/UI/Workspace/BrowserDetailsViewController.swift`
- Create: `MachOKnifeApp/UI/Workspace/BrowserHexViewController.swift`
- Modify: `MachOKnifeApp/Localization/L10n.swift`
- Modify: `Resources/Localization/en.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hant.lproj/Localizable.strings`

### Task 1: Lock Down Close-File Reset Behavior

**Files:**
- Modify: `MachOKnifeTests/WorkspaceViewModelTests.swift`
- Modify: `MachOKnifeApp/ViewModels/WorkspaceViewModel.swift`

- [ ] **Step 1: Write the failing test**

Add tests that open a fixture, invoke a new close/reset entry point, and assert:

- `hasLoadedDocument` becomes `false`
- selection, detail text, hex text, outline items, and error state are cleared
- the workspace returns to empty state data

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MachOKnife.xcodeproj -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/WorkspaceViewModelTests -skip-testing:MachOKnifeUITests`
Expected: FAIL because the close/reset API and browser reset outputs do not exist yet.

- [ ] **Step 3: Implement the minimal reset API**

Add a clear document path in `WorkspaceViewModel` that resets all published browser state without touching recent-files history.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MachOKnife.xcodeproj -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/WorkspaceViewModelTests -skip-testing:MachOKnifeUITests`
Expected: PASS.

### Task 2: Add MachOKit As The Browser Backend

**Files:**
- Modify: `MachOKnife.xcodeproj/project.pbxproj`
- Modify: `Packages/MachOKnifeKit/Package.swift`
- Create: `Packages/MachOKnifeKit/Sources/MachOKnifeKit/Browser/BrowserDocumentService.swift`
- Create: `Packages/MachOKnifeKit/Sources/MachOKnifeKit/Browser/BrowserModels.swift`
- Create: `Packages/MachOKnifeKit/Tests/MachOKnifeKitTests/BrowserDocumentServiceTests.swift`

- [ ] **Step 1: Write the failing service tests**

Add tests for a browser loader that:

- loads a standard Mach-O fixture
- reports a root node with children
- produces detail rows and hex bytes for a selected node
- exposes a second entry point for memory-image loading

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/MachOKnifeKit --filter BrowserDocumentServiceTests`
Expected: FAIL because the MachOKit-backed browser layer does not exist yet.

- [ ] **Step 3: Add the MachOKit dependency**

Wire the remote Swift package into the Xcode project and `Packages/MachOKnifeKit`.

- [ ] **Step 4: Implement the browser models and service**

Create app-friendly wrappers for:

- browser document kind
- outline node identity/title/children
- detail rows
- hex dump lines
- supported loader entry points for file URLs and memory images

The service should prefer `dyld_shared_cache`, then universal/fat, then plain Mach-O, mirroring `MachO-Explorer`.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path Packages/MachOKnifeKit --filter BrowserDocumentServiceTests`
Expected: PASS.

### Task 3: Migrate Workspace State To The New Browser Model

**Files:**
- Modify: `MachOKnifeApp/ViewModels/WorkspaceViewModel.swift`
- Modify: `MachOKnifeTests/WorkspaceViewModelTests.swift`

- [ ] **Step 1: Write the failing view-model tests**

Add tests that assert:

- opening a document creates tree nodes from the browser service
- selecting a node updates detail rows and hex output
- close/reset clears all browser-specific state

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MachOKnife.xcodeproj -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/WorkspaceViewModelTests -skip-testing:MachOKnifeUITests`
Expected: FAIL because `WorkspaceViewModel` still exposes summary-text state.

- [ ] **Step 3: Implement browser-state publishing**

Refactor `WorkspaceViewModel` to publish browser-oriented state. Keep deferred edit/retag entry points behind explicit `TODO` comments and avoid using the old editing flow in the main window.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MachOKnife.xcodeproj -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/WorkspaceViewModelTests -skip-testing:MachOKnifeUITests`
Expected: PASS.

### Task 4: Replace The Main Workspace UI With Tree + Details/Hex

**Files:**
- Modify: `MachOKnifeApp/UI/MainWindowController.swift`
- Modify: `MachOKnifeApp/UI/Workspace/WorkspaceSplitViewController.swift`
- Modify: `MachOKnifeApp/UI/Workspace/SourceListViewController.swift`
- Modify: `MachOKnifeApp/UI/Workspace/DetailViewController.swift`
- Modify: `MachOKnifeApp/UI/Workspace/InspectorViewController.swift`
- Create: `MachOKnifeApp/UI/Workspace/BrowserTabViewController.swift`
- Create: `MachOKnifeApp/UI/Workspace/BrowserDetailsViewController.swift`
- Create: `MachOKnifeApp/UI/Workspace/BrowserHexViewController.swift`

- [ ] **Step 1: Write the failing UI-facing tests or seams**

Add or adjust unit-test seams so the controllers can be driven by browser state:

- empty state when no document is open
- tree selection forwards to the view model
- details and hex views refresh when selection changes

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MachOKnife.xcodeproj -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/WorkspaceViewModelTests -skip-testing:MachOKnifeUITests`
Expected: FAIL because the controllers still bind to summary text and editor tabs.

- [ ] **Step 3: Implement the workspace UI rewrite**

Replace the three-pane editor with:

- left outline tree
- right tab view: Details / Hex
- empty-state placeholder when no document is loaded

Keep clear `TODO` markers for future retag and modification workflows instead of partial UI.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MachOKnife.xcodeproj -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/WorkspaceViewModelTests -skip-testing:MachOKnifeUITests`
Expected: PASS.

### Task 5: Add File Menu Close-File Confirmation And Localization

**Files:**
- Modify: `MachOKnifeApp/AppDelegate.swift`
- Modify: `MachOKnifeApp/UI/MainWindowController.swift`
- Modify: `MachOKnifeApp/Localization/L10n.swift`
- Modify: `Resources/Localization/en.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hant.lproj/Localizable.strings`

- [ ] **Step 1: Write the failing behavior test**

Add a unit-test seam that verifies `closeCurrentDocument` only clears the workspace after confirmation.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MachOKnife.xcodeproj -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/WorkspaceViewModelTests -skip-testing:MachOKnifeUITests`
Expected: FAIL because there is no close-file action or confirmation path.

- [ ] **Step 3: Implement the menu item and confirmation path**

Add `File -> Close File`, wire it to a confirmation alert, and clear the workspace back to the initial state on acceptance.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MachOKnife.xcodeproj -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/WorkspaceViewModelTests -skip-testing:MachOKnifeUITests`
Expected: PASS.

### Task 6: Run Focused Verification

**Files:**
- Modify: `MachOKnifeTests/WorkspaceViewModelTests.swift`
- Modify: `Packages/MachOKnifeKit/Tests/MachOKnifeKitTests/BrowserDocumentServiceTests.swift`

- [ ] **Step 1: Run package tests**

Run: `swift test --package-path Packages/MachOKnifeKit`
Expected: PASS.

- [ ] **Step 2: Run focused app tests**

Run: `xcodebuild test -project MachOKnife.xcodeproj -scheme MachOKnife -destination 'platform=macOS' -derivedDataPath /tmp/MachOKnife-browser-rewrite -only-testing:MachOKnifeTests/WorkspaceViewModelTests -only-testing:MachOKnifeTests/LocalizationRefreshTests -skip-testing:MachOKnifeUITests`
Expected: PASS.

- [ ] **Step 3: Run a build smoke check**

Run: `xcodebuild build -project MachOKnife.xcodeproj -scheme MachOKnife -destination 'platform=macOS' -derivedDataPath /tmp/MachOKnife-browser-rewrite-build`
Expected: BUILD SUCCEEDED.
