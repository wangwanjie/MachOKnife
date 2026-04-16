## ADDED Requirements

### Requirement: Finder recognizes MachOKnife as a viewer for supported Mach-O document types
MachOKnife SHALL declare document associations that allow Finder to present the app as an `Open With` candidate for supported Mach-O family files and static library archives.

#### Scenario: Opening a thin or fat Mach-O family file from Finder
- **WHEN** Finder resolves a selected file as a supported Mach-O family content type registered by MachOKnife
- **THEN** MachOKnife appears as an available `Open With` application for that file

#### Scenario: Opening a static library archive from Finder
- **WHEN** Finder resolves a selected `.a` archive as a supported static library content type registered by MachOKnife
- **THEN** MachOKnife appears as an available `Open With` application for that file

### Requirement: Document association remains scoped to analyzable binaries and archives
MachOKnife SHALL limit its document associations to analyzable Mach-O binaries and archives, and SHALL NOT register bundle containers as supported document types for Finder `Open With`.

#### Scenario: Bundle containers stay out of scope
- **WHEN** the user inspects an `.app`, `.framework`, or `.appex` bundle container in Finder
- **THEN** this change does not require MachOKnife to appear as an `Open With` application for that bundle container

### Requirement: Finder-opened documents reuse the existing application open-files path
When Finder launches MachOKnife for a supported associated file, the app SHALL route the file through the existing application document open flow instead of a separate Finder-only code path.

#### Scenario: Finder opens a supported file in MachOKnife
- **WHEN** the user chooses MachOKnife from Finder `Open With` or sets it as the default app for a supported file
- **THEN** MachOKnife receives the file path through the standard application open-files flow
- **AND** the file opens in the main workspace using the existing document loading path

### Requirement: Extensionless Mach-O support is best-effort and gated by system classification
MachOKnife SHALL support extensionless Mach-O files in Finder only when macOS classifies those files as one of the MachOKnife-registered content types.

#### Scenario: System recognizes an extensionless Mach-O file
- **WHEN** macOS classifies an extensionless executable as a supported Mach-O content type registered by MachOKnife
- **THEN** MachOKnife appears as an available `Open With` application for that file

#### Scenario: System does not recognize an extensionless Mach-O file
- **WHEN** macOS does not classify an extensionless executable as a supported content type
- **THEN** this change does not require MachOKnife to appear in Finder `Open With` for that file
