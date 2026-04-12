## Context

The current workspace open path is synchronous and main-actor bound. `MainWindowController.openDocument(at:)` calls `WorkspaceViewModel.openDocument(at:)`, and that `@MainActor` method immediately executes both `BrowserDocumentService.load(url:)` and `DocumentAnalysisService.analyze(url:)`.

That is problematic for large binaries because the current services are eager by design:

- `DocumentAnalysisService` calls `MachOContainer.parse(at:)`, which eagerly parses load commands, segments, sections, and the full symbol table into summary models.
- `BrowserDocumentService` builds the browser root from `MachOKit` objects and touches many heavy collections up front, including symbols, string tables, bindings, exports, and section-derived content.
- The workspace then publishes full browser roots and analysis objects only after all of that work completes.

For the provided 301MB sample binary (`.../kugou`), this architecture combines three costs at once: main-thread blocking, whole-file analysis, and large collection materialization. The proposal targets the desktop workspace only; CLI and other tool windows are not the primary scope.

## Goals / Non-Goals

**Goals:**

- Keep the workspace interactive while a large Mach-O is opened or reanalyzed.
- Make initial document open depend on a bounded metadata scan, not full symbol/string/binding expansion.
- Preserve the existing editing-critical metadata on first load: slices, load commands, segments, dylibs, rpaths, platform/version metadata, and hex access.
- Defer heavy collections until the user navigates into them, and bound their memory/CPU cost with paging or explicit deferred loading.
- Add regression coverage that proves the workspace chooses the budgeted path for large or high-cardinality binaries.

**Non-Goals:**

- Re-architect the CLI, archive tools, dyld cache tools, or retag windows in this change.
- Implement a global symbol index or full-text search across every deferred collection in the first iteration.
- Change the default semantics of existing CoreMachO parsing APIs for all callers on day one.

## Decisions

### 1. Introduce a metadata-first workspace loader

Add a new background `WorkspaceDocumentLoadService` that performs document opening in stages:

1. File access verification and lightweight document classification.
2. A bounded CoreMachO metadata scan that extracts only the data required for first paint.
3. Main-actor publication of a workspace shell and initial summary state.
4. Deferred collection loading when the user navigates into heavy nodes.

The initial scan must be sendable and cheap enough to run off the main actor. It should include slice headers, load commands, dylibs, rpaths, segments, section metadata, symbol-table metadata/counts, and the information required for editing workflows. It must not decode the full symbol table or string tables during first open.

Why this over "just move the current code to a background task":

- Backgrounding the current services would remove some UI blocking but still retain the largest CPU and memory spikes.
- `BrowserDocument` and `BrowserNode` are class-based UI models with closure-backed providers; they are poor boundaries for cross-actor transfer.
- The current eager MachOKit access would still create large collections before the UI sees anything.

### 2. Add a budgeted large-file mode instead of a single loading strategy

Introduce a centralized `AnalysisBudget` with thresholds driven by:

- file size
- symbol table count
- string table size
- estimated browser node count
- optionally, special-section counts for known high-cardinality content

Documents under budget continue to use the convenient "fully ready" path. Documents over budget enter `budgetedLargeFile` mode. In that mode, the workspace publishes cheap metadata immediately and converts heavy content into deferred nodes.

This is preferred over "always lazy-load everything" because small files should remain frictionless and easy to inspect, while large files need guardrails.

### 3. Replace eager heavy collections with deferred, bounded readers

Heavy collections are split into two implementation tiers:

- **Paged readers backed by CoreMachO metadata**
  - symbols
  - symbol strings / large string tables
- **Deferred group loaders**
  - bindings
  - exports
  - fixups
  - section-derived string-heavy or relocation-heavy content

The first tier should gain dedicated readers such as a symbol page reader and string-table page reader that decode only the requested range from the mapped file. The second tier may still rely on existing MachOKit-backed decoding, but only after the user explicitly navigates into that group.

This is preferred over "paginate the UI only" because UI-only pagination does not help if the backing arrays are already fully materialized during document open.

### 4. Build browser roots from scan snapshots, not from full MachOKit state

For budgeted documents, `BrowserDocumentService` should stop calling into `MachOKit` properties that eagerly expose full collections during root construction. Instead, it should accept the metadata scan output and build a lightweight browser shell:

- file node
- slices
- header
- load commands
- dylibs
- rpaths
- segments / sections
- deferred heavy groups with count metadata

Heavy groups should present summary information immediately and create children lazily from bounded readers. A practical first iteration is page-group nodes such as `Symbols 0-199`, `Symbols 200-399`, and equivalent buckets for other pageable data. That preserves the current outline-driven UX without emitting tens of thousands of child nodes up front.

### 5. Keep `WorkspaceViewModel` on the main actor and publish explicit load state

`WorkspaceViewModel` should remain `@MainActor` because AppKit bindings and window coordination already assume that model. Instead of moving the view model off the main actor, introduce explicit published state:

- `loadingState`: idle / loading / ready / degraded / error
- `analysisMode`: normal / budgetedLargeFile
- optional loading detail text for the active phase

The UI should use that state to:

- show a loading shell immediately after the user opens a document
- keep the window interactive while background work runs
- show a degraded-but-usable workspace when heavy collections are still deferred
- isolate deferred-node failures without clearing the whole document

### 6. Add regression coverage using generated fixtures plus the provided sample path

Do not check the 301MB `kugou` binary into the repository. Instead:

- add automated tests that generate high-cardinality binaries/object files and assert that the budgeted path is chosen
- add loader/view-model tests for deferred node behavior, paging, and failure isolation
- document a manual benchmark command or QA checklist that uses the provided local sample path before merge

This gives repeatable coverage without bloating the repository.

## Risks / Trade-offs

- [More states in the workspace model] -> Mitigation: introduce a small explicit state machine and test state transitions directly.
- [Budget thresholds may be tuned too low or too high] -> Mitigation: keep thresholds centralized and calibrate them against generated fixtures plus the provided `kugou` sample during implementation.
- [Some advanced browser data will no longer be instantly visible on first open for huge files] -> Mitigation: keep counts and lightweight summaries visible immediately, and load detailed pages only when the user drills into them.
- [CoreMachO partial readers add new parsing surface area] -> Mitigation: add them as new APIs alongside current parse behavior, with focused tests for symbol and string paging.
- [Deferred MachOKit-backed groups may still be expensive when explicitly loaded] -> Mitigation: keep those groups opt-in, isolate failures to the node, and expand paging support further if real-world testing shows they remain too costly.

## Migration Plan

1. Add the new scan/budget APIs and background workspace loader without removing the current parsing APIs.
2. Teach the workspace to publish the new loading states and use the staged loader for document open/reanalyze.
3. Convert browser root construction for large files to the scan-backed shell.
4. Add deferred readers/group loaders for heavy collections and update the browser/detail UI to surface them.
5. Run automated coverage plus manual verification against the provided `kugou` sample.
6. Keep a temporary fallback to the legacy loader during development; remove or hide it once the new path is stable.

Rollback is straightforward because no persistent data or file format changes are involved. The app can switch back to the legacy synchronous open path if the staged loader proves unstable.

## Open Questions

- What exact `AnalysisBudget` thresholds produce the best balance for common binaries versus pathological ones?
- In the first iteration, should "load all symbols" exist at all for budgeted documents, or should symbol access remain strictly page-based?
