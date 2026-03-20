# MachOKnife

MachOKnife is a native macOS Mach-O inspection tool with an AppKit GUI and a companion CLI.

Milestone 1 focuses on:

- read-only Mach-O parsing in local Swift packages
- a three-pane workspace for opening and inspecting binaries
- CLI inspection commands for slice summaries and dylib/rpath listing
- localized preferences for language and appearance

## Repository Layout

- `Packages/CoreMachO`: low-level Mach-O parsing
- `Packages/MachOKnifeKit`: shared analysis models and services
- `Packages/MachOKnifeDB`: GRDB-backed persistence primitives
- `MachOKnifeApp`: AppKit application shell
- `MachOKnifeCLI`: `machoe-cli` sources
- `Resources/Localization`: app localizations
- `Resources/Fixtures`: generated milestone fixtures
- `Scripts`: repeatable verification helpers

## Build And Run

Open `MachOKnife.xcodeproj` in Xcode and run the `MachOKnife` scheme, or build from Terminal:

```bash
xcodebuild build \
  -project MachOKnife.xcodeproj \
  -scheme MachOKnife \
  -destination 'platform=macOS,arch=x86_64'
```

## GUI Usage

Milestone 1 supports:

- dragging a Mach-O, `.dylib`, framework binary, or app binary into the workspace
- `Open...` from the File menu
- `Analyze` to re-run parsing on the current file
- localized Preferences tabs for General, CLI, Appearance, Updates, and Advanced

## CLI Usage

Build the `machoe-cli` target from Xcode or through the `MachOKnife` scheme, then run:

```bash
machoe-cli info /path/to/binary
machoe-cli list-dylibs /path/to/binary
```

To build a local verification fixture:

```bash
bash Scripts/build_fixtures.sh
machoe-cli info Resources/Fixtures/generated/libFixture.dylib
machoe-cli list-dylibs Resources/Fixtures/generated/libFixture.dylib
```

## Verification

Run the milestone 1 verification pipeline:

```bash
bash Scripts/test_milestone_1.sh
```

The script runs package tests, targeted app tests, builds deterministic fixture dylibs, and executes the CLI against them.
