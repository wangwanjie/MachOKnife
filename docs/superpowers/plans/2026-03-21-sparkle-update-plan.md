# MachOKnife Sparkle Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Sparkle-backed runtime update support, a working Updates preferences tab, and a manual update entry point for MachOKnife.

**Architecture:** Keep Sparkle integration isolated inside an app-local `UpdateManager` and expose simple UI-facing state to the app and preferences controllers. Persist update policy in `AppSettings`, wire menu and preferences actions through the manager, and make the runtime safe when feed metadata is not configured yet.

**Tech Stack:** AppKit, Foundation, Sparkle 2 via Swift Package Manager, XCTest / Swift Testing

---

## Planned File Structure

- Modify: `MachOKnife.xcodeproj/project.pbxproj`
- Modify: `MachOKnifeApp/AppDelegate.swift`
- Modify: `MachOKnifeApp/Localization/L10n.swift`
- Modify: `MachOKnifeApp/Services/AppSettings.swift`
- Create: `MachOKnifeApp/Services/UpdateManager.swift`
- Modify: `MachOKnifeApp/UI/Preferences/PreferencesWindowController.swift`
- Create: `MachOKnifeApp/UI/Preferences/UpdatesPreferencesViewController.swift`
- Modify: `Resources/Localization/en.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hant.lproj/Localizable.strings`
- Create: `MachOKnifeTests/UpdateManagerTests.swift`

### Task 1: Add Update Settings And Manager Coverage

**Files:**
- Modify: `MachOKnifeApp/Services/AppSettings.swift`
- Create: `MachOKnifeApp/Services/UpdateManager.swift`
- Create: `MachOKnifeTests/UpdateManagerTests.swift`

- [ ] **Step 1: Write failing tests for update policy persistence and update-manager state mapping**
- [ ] **Step 2: Run the targeted tests to verify they fail**
- [ ] **Step 3: Extend `AppSettings` with update preferences**
- [ ] **Step 4: Implement `UpdateManager` with Sparkle-aware state, no-op safety when feed data is missing, and manual-check hooks**
- [ ] **Step 5: Run the targeted tests to verify they pass**
- [ ] **Step 6: Commit**

### Task 2: Wire Sparkle Into The App Target

**Files:**
- Modify: `MachOKnife.xcodeproj/project.pbxproj`
- Modify: `MachOKnifeApp/AppDelegate.swift`

- [ ] **Step 1: Add a failing build expectation or compile dependency for Sparkle references**
- [ ] **Step 2: Run verification to confirm Sparkle is not yet linked**
- [ ] **Step 3: Add the Sparkle package dependency, sandbox entitlements, and app configuration keys**
- [ ] **Step 4: Wire `AppDelegate` to initialize the update manager and expose a Check for Updates menu action**
- [ ] **Step 5: Run an app build to verify Sparkle links and the app still signs**
- [ ] **Step 6: Commit**

### Task 3: Replace The Updates Placeholder With A Working Preferences Tab

**Files:**
- Modify: `MachOKnifeApp/Localization/L10n.swift`
- Modify: `MachOKnifeApp/UI/Preferences/PreferencesWindowController.swift`
- Create: `MachOKnifeApp/UI/Preferences/UpdatesPreferencesViewController.swift`
- Modify: `Resources/Localization/en.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/Localization/zh-Hant.lproj/Localizable.strings`
- Test: `MachOKnifeTests/UpdateManagerTests.swift`

- [ ] **Step 1: Extend tests to cover the preferences-facing update state**
- [ ] **Step 2: Run the targeted tests to verify they fail**
- [ ] **Step 3: Implement the Updates preferences tab with status, policy controls, automatic download toggle, and manual check action**
- [ ] **Step 4: Replace the Updates placeholder tab and bind it to `UpdateManager`**
- [ ] **Step 5: Run targeted tests plus an app build to verify it passes**
- [ ] **Step 6: Commit**
