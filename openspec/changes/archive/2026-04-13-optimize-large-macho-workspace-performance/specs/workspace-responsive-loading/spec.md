## ADDED Requirements

### Requirement: Workspace opens large Mach-O files without blocking the interactive shell
The workspace SHALL begin document loading asynchronously and publish a visible loading state before any high-cost analysis required for large-file handling completes.

#### Scenario: Opening a budgeted large file
- **WHEN** the user opens a Mach-O document whose metadata exceeds the large-file analysis budget
- **THEN** the workspace enters a loading state immediately
- **AND** the document window remains usable while background loading continues
- **AND** the workspace does not wait for full symbol or string decoding before showing that loading state

#### Scenario: Reanalyzing a budgeted large file
- **WHEN** the user requests reanalysis for the current large Mach-O document
- **THEN** the workspace re-enters a loading state without blocking the document window
- **AND** the reload work is performed through the staged loader path instead of the legacy synchronous path

### Requirement: Workspace publishes useful metadata before deferred collections are ready
The workspace SHALL publish the document shell and first-paint metadata as soon as the bounded scan succeeds, even if heavy collections remain deferred.

#### Scenario: Initial metadata becomes available
- **WHEN** the bounded metadata scan succeeds for a large Mach-O document
- **THEN** the workspace shows file, slice, load command, segment, dylib, and rpath summary information
- **AND** the user can navigate those summary nodes without waiting for heavy collection decoding

#### Scenario: Deferred collection loading fails
- **WHEN** a deferred collection load fails after the document shell has already opened
- **THEN** the workspace keeps the current document open
- **AND** only the failing collection enters an error state with retry information

