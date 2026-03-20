# MachOKnife Design

Date: 2026-03-21

## Goal

Build a macOS native Mach-O analysis and editing tool named `MachOKnife` with:

- a GUI app for inspection, editing, retag workflows, preferences, and updates
- a CLI tool named `machoe-cli`
- a reusable core that parses and safely rewrites Mach-O metadata related to dynamic libraries

The product targets common iOS, iOS Simulator, Mac Catalyst, and macOS binary repair workflows.

## Why This Is Split Into Sub-Projects

The requested scope spans multiple independent subsystems:

1. Mach-O parsing and safe rewriting
2. Scenario-oriented retag and rewrite workflows
3. GUI shell, workspace navigation, drag and drop, and editing views
4. CLI command surface and installation flow
5. Preferences, localization, themes, recent file persistence, updates, packaging, and release automation

Trying to implement all of that in one pass would create weak boundaries and make verification unreliable. The project will therefore be delivered in milestones, each producing working software and preserving a stable architecture for the next milestone.

## Recommended Architecture

Use an Xcode project as the product shell and move reusable logic into local Swift packages.

### Top-Level Layout

```text
MachOKnife.xcodeproj
MachOKnifeApp/
MachOKnifeCLI/
Packages/
  CoreMachO/
  RetagEngine/
  MachOKnifeKit/
  MachOKnifeDB/
Resources/
Scripts/
Vendor/
docs/
```

### Module Responsibilities

#### `Packages/CoreMachO`

The binary parsing and writing layer. It is fully UI-agnostic and exposes Swift-friendly models.

Responsibilities:

- detect regular Mach-O, fat Mach-O, and static archive containers
- parse fat headers and architecture slices
- parse Mach headers and targeted load commands
- parse segment and section metadata needed by the editor
- parse signature, encryption, UUID, versioning, and dependency-related load commands
- validate bounds before every read
- rewrite supported commands without changing file layout outside the load command area
- surface explicit errors for unsupported layout, invalid ranges, and insufficient padding

Implementation shape:

- Swift entry points and models
- C helpers based on system headers from `<mach-o/loader.h>`, `<mach-o/fat.h>`, and related headers
- Objective-C or C shim where Swift interop is awkward

#### `Packages/RetagEngine`

A higher-level operation layer built on `CoreMachO`.

Responsibilities:

- infer likely platform from architecture and existing commands
- rewrite `LC_BUILD_VERSION` or `LC_VERSION_MIN_*`
- normalize hard-coded dylib paths into `@rpath`, `@loader_path`, or `@executable_path`
- repair dylibs extracted from `dyld_shared_cache`
- provide dry-run diff results before writing

#### `Packages/MachOKnifeKit`

Shared application logic for the app and CLI.

Responsibilities:

- document import and analysis orchestration
- file coordination, backups, and save policies
- presentation-neutral domain view models
- command output adapters for CLI rendering

#### `Packages/MachOKnifeDB`

Persistence services built on GRDB.

Responsibilities:

- recent files list, default max 50
- preference storage that benefits from SQL-backed history or migration
- future storage for saved retag recipes

## Data Model

`CoreMachO` will expose immutable analysis models and mutable edit descriptors.

Core read models:

- `MachOContainer`
- `MachOSlice`
- `MachOHeaderInfo`
- `MachOLoadCommandInfo`
- `DylibCommandInfo`
- `RPathCommandInfo`
- `BuildVersionInfo`
- `VersionMinInfo`
- `SegmentInfo`
- `SectionInfo`
- `CodeSignatureInfo`
- `EncryptionInfo`

Edit request models:

- `MachOEditPlan`
- `DylibEdit`
- `RPathEdit`
- `PlatformEdit`
- `SegmentProtectionEdit`

Write results:

- `MachOWriteResult`
- `SliceWriteResult`
- `MachODiff`
- `DiffEntry`

## Safety Model For Editing

`MachOKnife` is a metadata editor, not a linker. The write strategy is intentionally narrow.

Supported:

- modify `LC_ID_DYLIB` install name
- modify, add, and remove `LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`, and `LC_REEXPORT_DYLIB`
- modify, add, and remove `LC_RPATH`
- modify `LC_BUILD_VERSION` or `LC_VERSION_MIN_*`
- modify segment VM protection flags
- update `ncmds` and `sizeofcmds`

Not supported in 1.0:

- moving section or segment file ranges
- rebuilding symbol tables
- updating relocations
- resigning binaries automatically

Write algorithm:

1. Parse the slice and compute the writable load-command window.
2. Build a new in-memory command list from edit descriptors.
3. Compute resulting `sizeofcmds`.
4. Verify the new command area still fits before the first mapped file payload.
5. Rewrite the header and load command area.
6. If code signature data becomes invalid, remove `LC_CODE_SIGNATURE` by default and report that the output requires re-signing.

If step 4 fails, the operation aborts with a deterministic error instead of producing a risky partial rewrite.

## GUI Product Design

The app is AppKit-first. This is deliberate because the product needs a split workspace, inspector panels, editable tables, drag and drop, and a preferences window with multiple panes.

### Main Window

Three-pane layout:

- left: source tree and binary structure
- center: details for the selected node
- right: editable inspector

Primary sections:

- file summary
- slices
- segments and sections
- load commands
- dependencies
- rpaths
- symbols

Inspector tabs:

- `Overview`
- `Dylibs`
- `RPaths`
- `Platform`
- `Segments`
- `Retag Preview`

Toolbar actions:

- `Open`
- `Analyze`
- `Save`
- `Save As`
- `Retag Wizard`
- `Quick Fix @rpath`

Input methods:

- drag and drop into the window
- `Cmd+O`
- file menu
- recent files list

### Preferences Window

Tabs:

- `General`
- `CLI`
- `Appearance`
- `Updates`
- `Advanced`

Settings planned for 1.0:

- language
- theme mode and accent choice
- recent file limit, default 50
- backup behavior
- CLI install and uninstall
- update policy
- diagnostic logging

## CLI Product Design

The CLI is a thin shell over the same core packages.

Planned 1.0 commands:

- `machoe-cli info <path>`
- `machoe-cli list-dylibs <path>`
- `machoe-cli retag-platform <path> --platform ... --min ... --sdk ... --output ...`
- `machoe-cli rewrite-rpath <path> --from ... --to ... --output ...`
- `machoe-cli fix-dyld-cache-dylib <path> --output ...`
- `machoe-cli validate <path>`
- `machoe-cli set-id <path> --install-name ... --output ...`
- `machoe-cli strip-signature <path> --output ...`

The app installs the CLI from its bundled helper into a user-selected destination. The first supported destinations are:

- `~/.local/bin`
- `/usr/local/bin`

The preferences UI will detect whether the chosen destination is on `PATH`.

## Dependencies

Recommended third-party packages:

- `Sparkle` for app updates
- `GRDB` for recent file and preference-backed persistence
- `SnapKit` for AppKit layout ergonomics
- `swift-argument-parser` for CLI commands

Possible optional later dependency:

- `mach-swift` or similar helpers are not required because the project should stay close to system Mach-O headers

## Localization, Appearance, and Update Strategy

Localization:

- initial languages: English, Simplified Chinese, Traditional Chinese
- string access through a typed localization layer

Appearance:

- support system, light, and dark appearance selection
- support accent color or editor tint presets in preferences

Updates:

- Sparkle feed via `appcast.xml`
- release notes embedded into appcast entries
- manual and automatic check modes

## Release And Packaging

Release assets:

- notarized `.dmg`
- GitHub Release
- `appcast.xml`
- inline release notes
- README with real screenshots

Release automation will be modeled after the existing `ViewScope` scripts and adapted to this repository.

## Additional Features Worth Including

These features strengthen the "surgical tool" identity and are still aligned with the product scope:

- dry-run preview before every write
- slice-level diff report
- backup creation with configurable retention
- code-signature status banner
- exporting a GUI edit session as an equivalent CLI command
- read-only support for `.a` members in early milestones

## Milestone Breakdown

### Milestone 1: Foundation And Read-Only Analysis

Deliver:

- repository structure cleanup
- local package layout
- `CoreMachO` read-only parsing for fat container, slices, headers, and targeted load commands
- `machoe-cli info` and `machoe-cli list-dylibs`
- GUI shell with drag and drop, file open, analyze action, recent files, and read-only inspectors
- preferences shell with localization, appearance, CLI tab placeholder, and recent file limit

### Milestone 2: Safe Metadata Editing

Deliver:

- edit plan models
- safe load-command-area rewrite pipeline
- install name, dependency, rpath, platform, and segment protection editing
- save, save as, backup, and diff preview
- CLI edit commands

### Milestone 3: Retag Workflows And Polish

Deliver:

- retag engine
- dyld cache dylib repair workflows
- retag wizard UI
- CLI install and uninstall
- Sparkle integration
- release scripts
- screenshots, README, and 1.0 packaging

## First Implementation Slice

The first implementation slice should be `Milestone 1`.

Reason:

- it validates the architecture without committing to risky rewrite logic yet
- it gives an inspectable app and usable CLI immediately
- it creates the persistence, localization, and preferences skeleton needed by later milestones

After Milestone 1 is stable and tested, the project can move to the write pipeline with much lower integration risk.
