# MachOKnife CLI Install Design

**Context:** `machoe-cli` already builds as an Xcode target, but the app-side Preferences UI still exposes a placeholder tab. The product needs a user-facing install/uninstall flow that works from the sandboxed macOS app and stays maintainable.

## Recommended Approach

Use an app-bundled CLI payload plus a small install-management layer in the app:

1. Build `machoe-cli` as usual.
2. Copy the built binary into the app bundle during the app target build.
3. Add an app-side `CLIInstallService` that:
   - locates the bundled CLI payload
   - tracks the selected install directory
   - installs by copying the payload to `<installDir>/machoe-cli`
   - uninstalls by removing the installed binary
   - reports current status and version/path metadata
4. Replace the Preferences CLI placeholder with a dedicated tab showing:
   - installed / not installed state
   - current install path
   - directory picker
   - install / reinstall / uninstall actions
   - PATH guidance for shells

## Alternatives Considered

### Option A: Install from DerivedData

Read the built `machoe-cli` from Xcode DerivedData and copy it on demand.

Pros:
- no app bundling changes

Cons:
- brittle across build folders and configurations
- not usable outside local development
- poor release story

### Option B: Build CLI on demand from the app

Invoke `xcodebuild` or `swift build` from the GUI and install the result.

Pros:
- always rebuilds fresh

Cons:
- slow and fragile
- pushes build-system concerns into the GUI
- worse UX and more sandbox friction

### Option C: Bundle the CLI and install from Preferences

Pros:
- deterministic release behavior
- clean separation between build-time packaging and runtime installation
- easiest path to notarized distribution later

Cons:
- needs app bundling and install-state plumbing

This is the recommended approach.

## Sandboxing

The current app uses user-selected read-only file access. CLI installation needs writes to a user-chosen directory such as `~/bin` or `~/.local/bin`, so the app should move to `com.apple.security.files.user-selected.read-write`. The install flow should use an `NSOpenPanel` directory picker and store a security-scoped bookmark for the chosen install directory.

## Persistence Model

Store two CLI settings in `AppSettings`:

- install directory bookmark data
- preferred install directory display path fallback

The effective installed state is not stored directly. It is derived by checking whether the installed binary exists and is executable.

## UI Design

The CLI Preferences tab should contain:

- title and short explanation
- status badge / summary label
- installed path field
- directory picker button
- install button
- uninstall button
- hint text for PATH export examples

The UI should stay AppKit-native and match the existing preferences layout helpers.

## Testing

Add focused unit tests for:

- bookmark/path persistence in `AppSettings`
- install status derivation
- install/uninstall behavior against a temporary directory
- preferences view-model or controller logic that reacts to install state

The build should still pass for the app target after embedding the CLI payload.
