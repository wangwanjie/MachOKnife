<p align="center">
  <img src="assets/icon-256.png" width="128" height="128" alt="MachOKnife icon">
</p>

<h1 align="center">MachOKnife</h1>

<p align="center">
  A native macOS app for inspecting and editing Mach-O binaries — executables, dylibs, frameworks, object files, universal (fat) binaries, and static libraries (<code>.a</code>).
</p>

<p align="center">
  <a href="https://wangwanjie.github.io/MachOKnife/">Homepage</a> ·
  <a href="https://github.com/wangwanjie/MachOKnife/releases/latest">Download</a> ·
  <a href="https://github.com/wangwanjie/MachOKnife/issues">Feedback</a>
</p>

MachOKnife pairs a MachOView-style structure browser with a set of everyday binary tools (retag, XCFramework packaging, merge / split / remove architectures, contamination checks) and ships the same tooling as a command-line utility, `machoe-cli`.

![MachOKnife main window: structure tree on the left, load commands of Sparkle.framework on the right](assets/screenshots/main-window.png)

<p align="center"><em>The main workspace: browse the structure tree on the left and inspect every field with its raw offset and bytes on the right.</em></p>

## Download

Grab the latest DMG from [GitHub Releases](https://github.com/wangwanjie/MachOKnife/releases/latest). Each release ships one DMG per architecture:

| Your Mac | Download |
| --- | --- |
| Apple Silicon (M1 and later) | `MachOKnife_V_<version>_arm64.dmg` |
| Intel | `MachOKnife_V_<version>_x86_64.dmg` |

Not sure? Open  > About This Mac: "Chip: Apple M…" means Apple Silicon, "Processor: Intel…" means Intel. Older versions are listed on the [Releases](https://github.com/wangwanjie/MachOKnife/releases) page.

Open the DMG, drag MachOKnife into Applications, then launch it from Applications. Builds are signed with Developer ID and notarized by Apple, and the app keeps itself up to date through Sparkle — the update feed automatically serves the build that matches your Mac.

## Features

### Structure browser

- Mach header, load commands, segments and sections, dyld info / chained fixups, export trie, symbol / indirect symbol / string tables, code signature, Objective-C metadata, and relocations, laid out like MachOView
- thin and universal binaries, static libraries, and dyld shared caches
- `RAW` / `RVA` address modes, a field-level `Detail` table and a hex `Data` view
- structure search, ⌘C copy for the selected rows, and copy / export from the context menu
- large binaries stay responsive: symbols, strings, and other heavy groups are decoded on demand
- open files by drag and drop, `File > Open…`, Finder "Open With", or `File > Open Recent` (recent files survive relaunches)

### Tools menu

Every tool opens pre-filled with the file currently open in the workspace.

- **Retag…** — rewrite platform, minimum OS, and SDK metadata (e.g. turn an iOS slice into a Mac Catalyst slice)
- **Build XCFramework…** — package iOS device / simulator static libraries and headers into an XCFramework, optionally generating Mac Catalyst slices automatically
- **Mach-O Summary…** — a one-page report for a binary or archive
- **Check Binary Contamination…** — find slices whose platform or architecture doesn't match what you expect
- **Merge / Split Mach-O…** — merge slices into a universal file, split a fat file per architecture, or strip unwanted architectures (for example simulator slices before an App Store upload)

| Retag | Build XCFramework |
| --- | --- |
| ![Retag tool](assets/screenshots/retag.png) | ![Build XCFramework tool](assets/screenshots/xcframework.png) |

| Check Binary Contamination | Preferences › CLI |
| --- | --- |
| ![Binary contamination check](assets/screenshots/contamination.png) | ![Install the bundled CLI from Preferences](assets/screenshots/cli.png) |

### Preferences

- **General** — language (English, 简体中文, 繁體中文; switches instantly)
- **CLI** — install or uninstall the bundled `machoe-cli` into a directory of your choice
- **Appearance** — follow system, light, or dark
- **Updates** — manual, daily, or at-launch update checks

## Command-line tool

`machoe-cli` ships inside the app. Install it from **Preferences › CLI** (choose a directory on your `PATH`, such as `/usr/local/bin`), then:

```bash
machoe-cli info /path/to/binary                # per-slice overview (add --json for machine-readable output)
machoe-cli summary /path/to/binary --json
machoe-cli list-dylibs /path/to/binary --json
machoe-cli check-contamination /path/to/libSDK.a --mode architecture --target arm64
machoe-cli merge arm64/libSDK.a x86_64/libSDK.a --output /tmp/libSDK.a
machoe-cli split /path/to/FatBinary --output-dir /tmp/slices --arch arm64
machoe-cli remove-arch MyLib.framework/MyLib --arch x86_64 --arch i386 --in-place
machoe-cli set-id libExample.dylib --install-name @rpath/libExample.dylib --output /tmp/libExample.dylib
machoe-cli rewrite-rpath libExample.dylib --from /old/path --to @loader_path/Frameworks --output /tmp/libExample.dylib
machoe-cli retag-platform libExample.dylib --platform macos --min 13.0 --sdk 14.0 --output /tmp/libExample.dylib
machoe-cli build-xcframework --source-library libSDK.a --ios-simulator-source-library libSDK-sim.a --headers-dir Headers --output /tmp/SDK.xcframework
machoe-cli fix-dyld-cache-dylib libCacheStyle.dylib --output /tmp/libCacheStyle.fixed.dylib
machoe-cli strip-signature /path/to/binary --output /tmp/binary
machoe-cli validate /path/to/binary
```

Run `machoe-cli help <command>` for every option. Conventions:

- reports go to stdout and errors to stderr; usage errors exit with `64`, and failed checks (`validate`, `check-contamination` mismatches) exit with `1`
- editing commands never overwrite their input implicitly: `--output` must differ from the input, and `remove-arch` needs an explicit `--in-place` to rewrite a file
- a single-value option given twice is rejected instead of silently picking one

## System requirements

- macOS 13.0 or later
- Apple Silicon or Intel Mac (pick the matching DMG)

## Feedback

Found a bug or have a feature request? Please open an [issue](https://github.com/wangwanjie/MachOKnife/issues).
