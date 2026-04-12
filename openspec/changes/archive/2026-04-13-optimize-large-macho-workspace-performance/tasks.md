## 1. CoreMachO scan and budget primitives

- [x] 1.1 Add lightweight CoreMachO scan models and APIs that collect first-paint metadata plus heavy-collection estimates without fully decoding symbols or string tables.
- [x] 1.2 Add a centralized large-file `AnalysisBudget` evaluator that classifies documents from scan results and is reusable by workspace loading code.
- [x] 1.3 Add bounded readers for symbol-table pages and string-heavy pages/batches, with focused unit tests for range decoding and out-of-bounds handling.

## 2. Staged workspace loading

- [x] 2.1 Introduce a background `WorkspaceDocumentLoadService` that performs document classification, bounded scan, and staged result publication off the main actor.
- [x] 2.2 Update `WorkspaceViewModel` to publish explicit loading and analysis-mode state while preserving existing editing-critical metadata and reanalyze behavior.
- [x] 2.3 Update the main window open/reload flow to use the staged loader and keep the workspace interactive during large-file open.

## 3. Budgeted browser and deferred collections

- [x] 3.1 Refactor `BrowserDocumentService` so budgeted large files build a scan-backed browser shell without touching eager MachOKit heavy collections during initial load.
- [x] 3.2 Add deferred/page-group browser nodes for symbols and string-heavy collections so large files expose bounded child ranges instead of one child per record.
- [x] 3.3 Add deferred loading behavior for bindings, exports, fixups, and other heavy groups, including node-level error and retry states.
- [x] 3.4 Update workspace source/detail presentation to show loading, degraded, and deferred-node states while keeping metadata and hex inspection available.

## 4. Regression coverage and manual verification

- [x] 4.1 Add automated tests for budget classification, staged loader state transitions, deferred paging, and deferred-load failure isolation.
- [x] 4.2 Add generated high-cardinality fixtures or fixture builders that exercise the budgeted path without checking large binaries into the repo.
- [x] 4.3 Document and run manual verification against `/Users/VanJay/Documents/Career/ReverseAndJailBreak/脱壳应用/11ProMax-16.5/酷狗音乐_12.3.2/kugou`, confirming the workspace no longer freezes on open.
