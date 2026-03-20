# MachOKnife CLI Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a usable Preferences-based install/uninstall flow for `machoe-cli` that works from the sandboxed app.

**Architecture:** Package the CLI into the app bundle at build time, then manage installation through a focused app-side service plus a dedicated Preferences tab. Persist the selected install directory in `AppSettings`, use security-scoped bookmarks for access, and derive install state from the filesystem instead of caching it.

**Tech Stack:** AppKit, Foundation, UserDefaults, security-scoped bookmarks, Xcode build phases, Swift Testing / XCTest

---

## Planned File Structure

- Modify: `MachOKnife.xcodeproj/project.pbxproj`
- Modify: `MachOKnifeApp/Services/AppSettings.swift`
- Create: `MachOKnifeApp/Services/CLIInstallService.swift`
- Modify: `MachOKnifeApp/Localization/L10n.swift`
- Modify: `MachOKnifeApp/UI/Preferences/PreferencesWindowController.swift`
- Modify: `Resources/Localization/en.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hant.lproj/Localizable.strings`
- Create: `MachOKnifeTests/CLIInstallServiceTests.swift`
- Modify: `MachOKnifeTests/AppSettingsTests.swift`

### Task 1: Add Install-State Persistence And Service Coverage

**Files:**
- Modify: `MachOKnifeApp/Services/AppSettings.swift`
- Create: `MachOKnifeApp/Services/CLIInstallService.swift`
- Create: `MachOKnifeTests/CLIInstallServiceTests.swift`
- Modify: `MachOKnifeTests/AppSettingsTests.swift`

- [ ] **Step 1: Write the failing settings and install-service tests**
- [ ] **Step 2: Run the targeted tests to verify they fail**
- [ ] **Step 3: Add install-directory persistence to `AppSettings`**
- [ ] **Step 4: Implement `CLIInstallService` with bundle lookup, status, install, and uninstall**
- [ ] **Step 5: Run the targeted tests to verify they pass**
- [ ] **Step 6: Commit**

### Task 2: Embed The CLI Payload In The App Product

**Files:**
- Modify: `MachOKnife.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add a failing smoke test or verification expectation for bundled CLI lookup**
- [ ] **Step 2: Run verification to confirm the bundle payload is currently missing**
- [ ] **Step 3: Update the app target build phases so `machoe-cli` is copied into the app bundle**
- [ ] **Step 4: Run an app build to verify the bundled CLI exists**
- [ ] **Step 5: Commit**

### Task 3: Replace The Preferences CLI Placeholder With A Working Installer

**Files:**
- Modify: `MachOKnifeApp/Localization/L10n.swift`
- Modify: `MachOKnifeApp/UI/Preferences/PreferencesWindowController.swift`
- Modify: `Resources/Localization/en.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hant.lproj/Localizable.strings`

- [ ] **Step 1: Extend tests or add controller coverage for CLI install actions**
- [ ] **Step 2: Run the targeted tests to verify they fail**
- [ ] **Step 3: Implement the CLI tab UI with status, path picker, install, uninstall, and PATH help**
- [ ] **Step 4: Wire the tab to `CLIInstallService` and `AppSettings`**
- [ ] **Step 5: Run targeted tests plus an app build to verify it passes**
- [ ] **Step 6: Commit**
