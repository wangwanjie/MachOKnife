# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

MachOKnife is a native macOS (13.0+) Mach-O browser and utility suite: an AppKit GUI app (`MachOKnife`), a companion CLI (`machoe-cli`), Sparkle updates, and release tooling for DMG/appcast publishing.

## Commands

Always build through the workspace (CocoaPods brings in `ViewScopeServer`, Debug-only). Run `pod install` if `Pods/` is missing.

```bash
# App
xcodebuild build -workspace MachOKnife.xcworkspace -scheme MachOKnife -destination 'platform=macOS,arch=x86_64'

# CLI
xcodebuild build -workspace MachOKnife.xcworkspace -scheme machoe-cli -destination 'platform=macOS,arch=x86_64'

# App unit + UI tests (MachOKnifeTests / MachOKnifeUITests)
xcodebuild test -workspace MachOKnife.xcworkspace -scheme MachOKnife -destination 'platform=macOS,arch=x86_64'

# Single test suite (or Suite/testMethod)
xcodebuild test -workspace MachOKnife.xcworkspace -scheme MachOKnife -destination 'platform=macOS,arch=x86_64' \
  -only-testing:MachOKnifeTests/WorkspaceViewModelTests

# Package tests (CoreMachO, MachOKnifeKit, MachOKnifeDB, RetagEngine)
swift test --package-path Packages/CoreMachO
swift test --package-path Packages/MachOKnifeKit --filter BrowserDocumentServiceTests

# Generate fixtures used by smoke tests (Resources/Fixtures/generated)
bash Scripts/build_fixtures.sh

# End-to-end verification (package tests + selected xcodebuild tests + CLI against fixtures)
bash Scripts/test_milestone_1.sh
```

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.

## Architecture

### Layering

```
CoreMachO (Swift + CoreMachOC C target)   low-level parsing, metadata scan, archive (.a) inspection, edit plan/writer
  ├── RetagEngine                         platform/build-version retagging
  └── MachOKnifeKit (+ p-x9/MachOKit)     browser tree models, document analysis, editing, tool services (summary,
                                          contamination, merge/split, XCFramework build)
MachOKnifeDB (GRDB)                       recent-files persistence
MachOKnifeApp / MachOKnifeCLI             thin front-ends over the packages
```

The four packages under `Packages/` are local SwiftPM packages referenced from `MachOKnife.xcodeproj`. Shared logic belongs in a package so both the app and CLI can use it; `MachOKnifeApp` and `MachOKnifeCLI` should stay UI/argument-handling shells.

### Xcode project

`MachOKnifeApp/`, `MachOKnifeCLI/`, `Resources/Localization/`, and the test folders are file-system-synchronized groups: adding a file to those directories adds it to the target without editing `project.pbxproj`. The app target uses an explicit `MachOKnife/Info.plist` (`GENERATE_INFOPLIST_FILE = NO`) holding Sparkle keys and `CFBundleDocumentTypes`/`UTImportedTypeDeclarations` for Finder "Open With".

### Workspace document loading

Opening a file is two-staged to stay responsive on large binaries (specs in `openspec/specs/workspace-*`):

1. `WorkspaceDocumentLoadService` runs `MachOContainer.scan` (bounded metadata only) and `AnalysisBudget.classify` off the main thread.
2. If the scan exceeds `AnalysisBudget.workspaceDefault` (file size, symbol count, string-table size, estimated node count), `BudgetedBrowserDocumentService` builds the tree with heavy groups (symbols, strings, special sections) as deferred/paged nodes; otherwise `BrowserDocumentService` builds the full tree.

`WorkspaceViewModel` drives this and feeds `UI/Workspace` (source list → detail/data inspector). Do not add code paths that decode full symbol/string collections during initial open.

### App structure

- `AppDelegate` builds menus (including the Tools menu) and handles Finder/cold-start document opens; `MainWindowController` owns the workspace window.
- `UI/Tools/*WindowController` are standalone tool windows backed by MachOKnifeKit tool services.
- `Services/`: `AppSettings` (UserDefaults-backed, injectable `defaults:`), `UpdateManager` (Sparkle, injectable configuration/client providers), `CLIInstallService` (installs the bundled CLI), `RecentFilesController` (GRDB + security-scoped bookmarks).
- Localization: all UI strings go through `L10n` (`MachOKnifeApp/Localization/L10n.swift`) with a key and English fallback; translations live in `Resources/Localization/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings`. Language changes refresh UI immediately, so new strings must be added to all three `.strings` files. `L10n.settingsProvider`/`bundleProvider` are swappable for tests.

### CLI

`MachOKnifeCLIApplication.run(arguments:)` dispatches on the first argument to a `*Command` type in `MachOKnifeCLI/Commands/` (each exposes `name` and `run(arguments:) -> String`). Adding a command means adding the type, a `case` in the switch, and a `CommandDescriptor` in `CLIHelp`. `CLISmokeTests` runs the built CLI binary and asserts on its output text.

### Repository-shape tests

Some tests in `MachOKnifeTests` assert on repository files, so moving/renaming them breaks tests: `RepositoryLayoutTests` (required paths), `ProjectConfigurationTests` (Info.plist Sparkle keys, feed URL, document types, pbxproj settings), `ReadmeAssetsTests` (renders README screenshots).

## Release

- Version lives in `project.pbxproj` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, set across all targets); scripts read it via `Scripts/common.sh`.
- Release notes go in `release-notes/vX.Y.Z.md`.
- `Scripts/build_dmg.sh` → `Scripts/generate_appcast.sh --archive build/dmg/MachOKnife_V_X.Y.Z.dmg` → `Scripts/publish_github_release.sh --dmg ...`. The feed is `Resources/Updates/appcast.xml`, served from the `main` branch.

## Workflow conventions

- Commit messages are written in Chinese (e.g. `修复冷启动时 Finder 右键打开 Mach-O 失效`).
- Feature changes use OpenSpec (`openspec/`, schema `spec-driven`): proposals in `openspec/changes/`, archived to `openspec/changes/archive/`, with accepted specs in `openspec/specs/`. Codex skills for this flow live in `.codex/skills/`. Older design docs/plans are in `docs/superpowers/`.
