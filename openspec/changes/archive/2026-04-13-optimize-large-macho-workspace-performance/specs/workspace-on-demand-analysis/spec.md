## ADDED Requirements

### Requirement: Workspace chooses budgeted analysis before decoding heavy collections
The workspace SHALL decide whether a document uses normal analysis or budgeted large-file analysis from bounded metadata, without first decoding the full symbol table or other high-cardinality collections.

#### Scenario: Document remains on the normal path
- **WHEN** a Mach-O document stays within the configured analysis budget
- **THEN** the workspace may continue to use the normal fully ready loading path

#### Scenario: Document enters budgeted mode
- **WHEN** a Mach-O document exceeds the configured analysis budget
- **THEN** the workspace marks the document as budgeted large-file analysis
- **AND** heavy collections are represented as deferred content instead of being fully materialized during initial open

### Requirement: Symbol and string-heavy data are exposed through bounded deferred access
For budgeted large-file documents, the workspace SHALL expose symbol and string-heavy content through bounded pages or equivalent bounded batches rather than a single full collection load.

#### Scenario: Symbols are deferred on first open
- **WHEN** the workspace opens a budgeted large-file document
- **THEN** the Symbols group shows total availability metadata without creating one browser child per symbol during initial load

#### Scenario: User drills into a symbol page
- **WHEN** the user navigates into a deferred symbol range for a budgeted large-file document
- **THEN** the workspace loads only the requested bounded page of symbol records
- **AND** it preserves the remaining symbol ranges as deferred content

#### Scenario: User drills into string-heavy data
- **WHEN** the user navigates into a deferred string-heavy collection for a budgeted large-file document
- **THEN** the workspace loads only the requested bounded page or bounded batch
- **AND** it does not decode the full collection as part of that initial document open

### Requirement: Budgeted mode preserves non-heavy inspection workflows
The workspace SHALL keep non-heavy inspection workflows available even while heavy collections remain deferred.

#### Scenario: Inspecting metadata in budgeted mode
- **WHEN** a budgeted large-file document is open
- **THEN** the user can still inspect header, load command, segment, dylib, rpath, and hex content without first loading symbols or string tables

