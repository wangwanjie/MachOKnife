# MachOKnife Sparkle Update Design

**Context:** The `Updates` preferences tab is still a placeholder, while the product spec requires Sparkle-based automatic updates for the sandboxed macOS app. The repository also needs a runtime update layer that is compatible with later release automation work.

## Goals

1. Integrate Sparkle 2 via Swift Package Manager into `MachOKnife.app`.
2. Support sandbox-safe update checks for a hardened runtime app.
3. Provide a maintainable app-local `UpdateManager` abstraction instead of wiring Sparkle directly into every controller.
4. Replace the placeholder `Updates` tab with a working AppKit preferences view.
5. Add a menu action for manual update checks.

## Non-Goals

1. Full release automation, DMG notarization, and GitHub publishing in this tranche.
2. Shipping a production `SUPublicEDKey` or final hosted `appcast.xml` feed in this tranche.
3. Custom Sparkle user-driver UI. The standard Sparkle UI is sufficient.

## External Constraints

- Sparkle’s official documentation recommends Sparkle 2 via Swift Package Manager and `SPUStandardUpdaterController` for Cocoa apps.
- Sparkle’s sandboxing guide requires `SUEnableInstallerLauncherService = YES` and the temporary mach-lookup exceptions:
  - `$(PRODUCT_BUNDLE_IDENTIFIER)-spks`
  - `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`
- Because MachOKnife already has `com.apple.security.network.client` behavior through app networking needs, we do not need Sparkle’s downloader XPC service in this tranche.
- `ViewScope` already demonstrates a maintainable repository-local pattern: a dedicated `UpdateManager`, settings-backed update policy, and repository scripts for later `appcast.xml` work.

## Proposed Architecture

### 1. App-local update service layer

Create `MachOKnifeApp/Services/UpdateManager.swift` as the single integration point with Sparkle.

Responsibilities:

- create and own `SPUStandardUpdaterController`
- expose update availability / configuration state to the app
- bridge manual update checks from menu and preferences UI
- read and write update-related preferences through `AppSettings`
- degrade gracefully when Sparkle feed data is not configured yet

This keeps Sparkle-specific APIs out of `AppDelegate` and out of view controllers.

### 2. Settings-backed update policy

Extend `AppSettings` with a small enum for update policy:

- `manual`
- `daily`

This intentionally avoids adding unnecessary granularity before release automation exists. Sparkle already persists its own updater flags in user defaults, but `AppSettings` remains the app’s canonical source for UI policy and localization.

### 3. UI surface

Replace the `Updates` placeholder with `UpdatesPreferencesViewController`.

The tab should show:

- updater status
- feed/configuration status
- automatic check mode toggle / popup
- automatic download toggle when Sparkle is available
- manual “Check for Updates…” button

This mirrors the existing preferences structure and keeps AppKit code thin.

### 4. App menu integration

Add a dedicated “Check for Updates…” menu item under the app menu, routed through `UpdateManager`.

This aligns with Sparkle’s standard Cocoa integration guidance and gives users a predictable manual entry point outside of preferences.

### 5. Release-prep placeholders

Add repository placeholders that unblock later release work:

- `Resources/Updates/appcast.xml` placeholder or documented feed location
- Info.plist-backed keys for:
  - `SUFeedURL`
  - `SUPublicEDKey`
  - `SUEnableInstallerLauncherService`

The runtime manager must tolerate missing or placeholder feed/public-key values without crashing.

## File Plan

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
- Create: `MachOKnifeTests/UpdatesPreferencesViewModelTests.swift` or similar model-level coverage

## Validation Strategy

1. TDD the settings and update manager state mapping first.
2. Add a preferences-focused model layer test before building the AppKit tab.
3. Verify with:
   - targeted tests for update manager + settings
   - `xcodebuild build` for the app target
4. Inspect generated entitlements to confirm Sparkle sandbox requirements are present.

## Follow-up Tranche

After runtime integration is stable, the next release tranche can add:

- real Sparkle keys
- hosted `appcast.xml`
- appcast generation script
- DMG / notarization / GitHub release automation
