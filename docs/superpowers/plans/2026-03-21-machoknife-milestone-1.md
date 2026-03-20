# MachOKnife Milestone 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working MachOKnife milestone with a clean project skeleton, read-only Mach-O parsing, a functional CLI for inspection, and a GUI shell that can open binaries, analyze them, and display core metadata.

**Architecture:** Keep parsing logic inside local Swift packages and keep the app and CLI thin. Milestone 1 intentionally avoids risky write support so the parser, view models, persistence, localization, and UI shell can be verified independently before metadata editing is introduced.

**Tech Stack:** AppKit, Combine, Swift Package Manager, C/Objective-C bridges for Mach-O parsing, GRDB, Sparkle, SnapKit, swift-argument-parser, XCTest

---

## Planned File Structure

- Create: `Packages/CoreMachO/Package.swift`
- Create: `Packages/CoreMachO/Sources/CoreMachO/`
- Create: `Packages/CoreMachO/Sources/CoreMachOC/`
- Create: `Packages/CoreMachO/Tests/CoreMachOTests/`
- Create: `Packages/RetagEngine/Package.swift`
- Create: `Packages/RetagEngine/Sources/RetagEngine/`
- Create: `Packages/RetagEngine/Tests/RetagEngineTests/`
- Create: `Packages/MachOKnifeKit/Package.swift`
- Create: `Packages/MachOKnifeKit/Sources/MachOKnifeKit/`
- Create: `Packages/MachOKnifeKit/Tests/MachOKnifeKitTests/`
- Create: `Packages/MachOKnifeDB/Package.swift`
- Create: `Packages/MachOKnifeDB/Sources/MachOKnifeDB/`
- Create: `Packages/MachOKnifeDB/Tests/MachOKnifeDBTests/`
- Create: `MachOKnifeApp/`
- Create: `MachOKnifeCLI/`
- Create: `Resources/Fixtures/`
- Create: `Resources/Localization/en.lproj/Localizable.strings`
- Create: `Resources/Localization/zh-Hans.lproj/Localizable.strings`
- Create: `Resources/Localization/zh-Hant.lproj/Localizable.strings`
- Create: `Scripts/`
- Modify: `MachOKnife.xcodeproj/project.pbxproj`
- Modify: `README.md`

### Task 1: Reshape The Repository

**Files:**
- Create: `MachOKnifeApp/`
- Create: `MachOKnifeCLI/`
- Create: `Packages/`
- Create: `Resources/`
- Create: `Scripts/`
- Modify: `MachOKnife.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing structure smoke test**

Create `MachOKnifeTests/RepositoryLayoutTests.swift` with assertions that expected directories and key package manifests exist.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/RepositoryLayoutTests`
Expected: FAIL because the directories and manifests do not exist yet.

- [ ] **Step 3: Create the repository folders**

Create the app, CLI, package, resource, and script folders so the structure test can pass.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/RepositoryLayoutTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MachOKnifeTests/RepositoryLayoutTests.swift MachOKnife.xcodeproj/project.pbxproj MachOKnifeApp MachOKnifeCLI Packages Resources Scripts
git commit -m "chore: reshape repository for milestone 1"
```

### Task 2: Bootstrap `CoreMachO` Package

**Files:**
- Create: `Packages/CoreMachO/Package.swift`
- Create: `Packages/CoreMachO/Sources/CoreMachO/CoreMachO.swift`
- Create: `Packages/CoreMachO/Sources/CoreMachO/Models/`
- Create: `Packages/CoreMachO/Sources/CoreMachOC/include/`
- Create: `Packages/CoreMachO/Sources/CoreMachOC/`
- Test: `Packages/CoreMachO/Tests/CoreMachOTests/CoreMachOParserSmokeTests.swift`

- [ ] **Step 1: Write the failing parser smoke tests**

Create tests that load a known Mach-O fixture and assert detection of:

- thin Mach-O
- fat Mach-O
- at least one parsed load command

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CoreMachO`
Expected: FAIL because the package and parser do not exist yet.

- [ ] **Step 3: Add package manifest and target skeleton**

Create the Swift target, C target, public module entry points, and initial error types.

- [ ] **Step 4: Implement fixture loading and magic detection**

Implement enough code to detect Mach-O and fat binaries using system Mach-O headers.

- [ ] **Step 5: Run tests to verify partial progress**

Run: `swift test --package-path Packages/CoreMachO --filter CoreMachOParserSmokeTests`
Expected: thin and fat detection assertions pass, load command assertions still fail.

- [ ] **Step 6: Implement header and load command enumeration**

Add bounded parsing for the Mach header and targeted load commands required by Milestone 1.

- [ ] **Step 7: Run tests to verify it passes**

Run: `swift test --package-path Packages/CoreMachO`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Packages/CoreMachO
git commit -m "feat: add read-only CoreMachO parser skeleton"
```

### Task 3: Define Shared Domain Models In `MachOKnifeKit`

**Files:**
- Create: `Packages/MachOKnifeKit/Package.swift`
- Create: `Packages/MachOKnifeKit/Sources/MachOKnifeKit/Models/`
- Create: `Packages/MachOKnifeKit/Sources/MachOKnifeKit/Services/`
- Test: `Packages/MachOKnifeKit/Tests/MachOKnifeKitTests/DocumentAnalysisServiceTests.swift`

- [ ] **Step 1: Write the failing analysis service tests**

Create tests for a document analysis service that transforms `CoreMachO` results into UI and CLI friendly summary models.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/MachOKnifeKit`
Expected: FAIL because the package does not exist yet.

- [ ] **Step 3: Add package manifest and summary model skeleton**

Create the package, dependency on `CoreMachO`, and shared summary types for slices, dependencies, and platform version info.

- [ ] **Step 4: Implement the analysis service**

Implement a service that accepts a file URL and produces a normalized document analysis object.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path Packages/MachOKnifeKit`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/MachOKnifeKit
git commit -m "feat: add shared document analysis models"
```

### Task 4: Add `MachOKnifeDB` For Recent Files

**Files:**
- Create: `Packages/MachOKnifeDB/Package.swift`
- Create: `Packages/MachOKnifeDB/Sources/MachOKnifeDB/AppDatabase.swift`
- Create: `Packages/MachOKnifeDB/Sources/MachOKnifeDB/RecentFileRecord.swift`
- Create: `Packages/MachOKnifeDB/Sources/MachOKnifeDB/RecentFilesStore.swift`
- Test: `Packages/MachOKnifeDB/Tests/MachOKnifeDBTests/RecentFilesStoreTests.swift`

- [ ] **Step 1: Write the failing recent-files tests**

Create tests that verify:

- insertion order is newest first
- duplicate paths are de-duplicated
- default retention is 50
- custom retention trims older rows

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/MachOKnifeDB`
Expected: FAIL because the package does not exist yet.

- [ ] **Step 3: Add package manifest and schema skeleton**

Create the package and GRDB-backed record definitions.

- [ ] **Step 4: Implement the store and migrations**

Implement database initialization, migration, and recent file upsert logic.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path Packages/MachOKnifeDB`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/MachOKnifeDB
git commit -m "feat: add recent files persistence"
```

### Task 5: Create The CLI Target And Inspection Commands

**Files:**
- Create: `MachOKnifeCLI/main.swift`
- Create: `MachOKnifeCLI/Commands/InfoCommand.swift`
- Create: `MachOKnifeCLI/Commands/ListDylibsCommand.swift`
- Modify: `MachOKnife.xcodeproj/project.pbxproj`
- Test: `MachOKnifeTests/CLISmokeTests.swift`

- [ ] **Step 1: Write the failing CLI smoke tests**

Create tests that run the CLI against a fixture and assert:

- `info` prints slice summaries
- `list-dylibs` prints dylib and rpath entries

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/CLISmokeTests`
Expected: FAIL because the CLI target does not exist yet.

- [ ] **Step 3: Add the CLI target and ArgumentParser dependency**

Update the project and create a `machoe-cli` executable target.

- [ ] **Step 4: Implement the `info` and `list-dylibs` commands**

Wire the CLI to `MachOKnifeKit` analysis services and add stable text rendering.

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/CLISmokeTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add MachOKnifeCLI MachOKnife.xcodeproj/project.pbxproj MachOKnifeTests/CLISmokeTests.swift
git commit -m "feat: add inspection cli commands"
```

### Task 6: Build The App Shell And Analysis Workflow

**Files:**
- Create: `MachOKnifeApp/AppDelegate.swift`
- Create: `MachOKnifeApp/ApplicationMain.swift`
- Create: `MachOKnifeApp/UI/MainWindowController.swift`
- Create: `MachOKnifeApp/UI/Workspace/WorkspaceSplitViewController.swift`
- Create: `MachOKnifeApp/UI/Workspace/SourceListViewController.swift`
- Create: `MachOKnifeApp/UI/Workspace/DetailViewController.swift`
- Create: `MachOKnifeApp/UI/Workspace/InspectorViewController.swift`
- Create: `MachOKnifeApp/ViewModels/WorkspaceViewModel.swift`
- Modify: `MachOKnife.xcodeproj/project.pbxproj`
- Test: `MachOKnifeUITests/WorkspaceLaunchUITests.swift`

- [ ] **Step 1: Write the failing UI smoke test**

Create a UI test that launches the app and asserts the main window shows an empty-state prompt.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeUITests/WorkspaceLaunchUITests`
Expected: FAIL because the shell UI does not exist yet.

- [ ] **Step 3: Replace the storyboard app with a code-driven AppKit shell**

Create the window controller, split view container, and empty-state UI.

- [ ] **Step 4: Wire file open, drag and drop, and analyze**

Connect the workspace view model to `MachOKnifeKit` and display parsed summaries in the three-pane shell.

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeUITests/WorkspaceLaunchUITests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add MachOKnifeApp MachOKnife.xcodeproj/project.pbxproj MachOKnifeUITests/WorkspaceLaunchUITests.swift
git commit -m "feat: add app shell and analysis workspace"
```

### Task 7: Add Localization, Appearance Settings, And Preferences Shell

**Files:**
- Create: `MachOKnifeApp/Localization/AppLanguage.swift`
- Create: `MachOKnifeApp/Localization/AppLocalization.swift`
- Create: `MachOKnifeApp/Localization/L10n.swift`
- Create: `MachOKnifeApp/Services/AppSettings.swift`
- Create: `MachOKnifeApp/UI/Preferences/PreferencesWindowController.swift`
- Create: `Resources/Localization/en.lproj/Localizable.strings`
- Create: `Resources/Localization/zh-Hans.lproj/Localizable.strings`
- Create: `Resources/Localization/zh-Hant.lproj/Localizable.strings`
- Test: `MachOKnifeTests/AppSettingsTests.swift`

- [ ] **Step 1: Write the failing settings tests**

Create tests for:

- language resolution
- recent file limit defaulting to 50
- theme persistence

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/AppSettingsTests`
Expected: FAIL because the settings layer does not exist yet.

- [ ] **Step 3: Implement localization and settings**

Create typed localization helpers and user-default backed settings for Milestone 1.

- [ ] **Step 4: Implement the preferences shell**

Add tabs for `General`, `CLI`, `Appearance`, `Updates`, and `Advanced`, with the CLI and updates tabs allowed to show "coming in Milestone 3" placeholders.

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme MachOKnife -destination 'platform=macOS' -only-testing:MachOKnifeTests/AppSettingsTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add MachOKnifeApp Resources/Localization MachOKnifeTests/AppSettingsTests.swift
git commit -m "feat: add preferences localization and appearance settings"
```

### Task 8: Integrate Fixtures And Verification Tooling

**Files:**
- Create: `Resources/Fixtures/README.md`
- Create: `Scripts/build_fixtures.sh`
- Create: `Scripts/test_milestone_1.sh`
- Modify: `README.md`

- [ ] **Step 1: Write the failing verification script**

Create `Scripts/test_milestone_1.sh` to build packages, run unit tests, run UI smoke tests, and run the CLI against at least one fixture.

- [ ] **Step 2: Run script to verify it fails**

Run: `bash Scripts/test_milestone_1.sh`
Expected: FAIL because the fixtures and targets are not fully wired yet.

- [ ] **Step 3: Add fixture documentation and helper script**

Document fixture sources and create a helper to compile or copy representative Mach-O samples.

- [ ] **Step 4: Update README with Milestone 1 usage**

Document how to open a file in the app and run the two CLI commands.

- [ ] **Step 5: Run script to verify it passes**

Run: `bash Scripts/test_milestone_1.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Resources/Fixtures Scripts README.md
git commit -m "test: add milestone 1 verification tooling"
```

## Verification Checklist For Milestone 1 Completion

- `swift test --package-path Packages/CoreMachO`
- `swift test --package-path Packages/MachOKnifeKit`
- `swift test --package-path Packages/MachOKnifeDB`
- `xcodebuild test -scheme MachOKnife -destination 'platform=macOS'`
- `bash Scripts/test_milestone_1.sh`

## Deferred To Milestone 2 Or 3

- write support in `CoreMachO`
- retag execution
- save and backup flows
- CLI installation and uninstall
- Sparkle app updates
- release packaging and screenshots
