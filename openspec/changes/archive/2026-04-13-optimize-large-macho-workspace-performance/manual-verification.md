# Manual Verification

## 2026-04-12

- Sample binary: `/Users/VanJay/Documents/Career/ReverseAndJailBreak/脱壳应用/11ProMax-16.5/酷狗音乐_12.3.2/kugou`
- Sample size: `313645312` bytes
- User-reported verification on the pre-fix build in this change:
  - Opening `kugou` no longer froze the entire app.
  - Expanding/selecting the `__TEXT` segment still froze the workspace, and the app had to be force-quit.

## Follow-up Fix In This Session

- Changed `WorkspaceViewModel` so selected browser nodes with large `dataRange` values render hex output in bounded pages instead of decoding the entire range at once.
- Added an app-side regression test that forces the budgeted path and verifies a `__TEXT` segment selection exposes paged hex output with next/previous navigation.

## Re-Verification Completed

- Verification date: `2026-04-12`
- Build used for manual verification:
  - `xcodebuild build -workspace MachOKnife.xcworkspace -scheme MachOKnife -configuration Debug -destination 'platform=macOS'`
  - Output app: `/Users/VanJay/Library/Developer/Xcode/DerivedData/MachOKnife-alxoeyktybgvesemqmgubrnbfgrn/Build/Products/Debug/MachOKnife.app`
- Automated regression evidence re-run before manual verification:
  - `swift test --package-path Packages/MachOKnifeKit --filter BrowserDocumentServiceTests`
  - Result: `15` tests passed

### Workspace responsiveness

- Opened `/Users/VanJay/Documents/Career/ReverseAndJailBreak/脱壳应用/11ProMax-16.5/酷狗音乐_12.3.2/kugou` in the freshly built app.
- The workspace stayed responsive after initial open and exposed the budgeted browser shell.
- The left outline remained navigable and listed the expected large-file nodes, including:
  - `Header`
  - `Load Commands (155)`
  - `Segments`
  - `Sections`
  - `Symbols`
  - `String Tables`
  - `Bindings`
  - `Exports`
  - `Fixups`
- User manual verification in the same change confirmed selecting `__TEXT` no longer freezes the workspace.

### `__objc_classlist` detail verification

- Selected `Sections` -> `__DATA.__objc_classlist (32409)` with the right pane on `Detail`.
- The detail table was populated with `32419` rows instead of staying empty.
- The first 10 rows remained section metadata, and the decoded class list started immediately after that.
- Sample decoded rows captured from the running app:
  - `102808F8 | Objective-C Class | PodsDummy_DoubleConversion`
  - `10280948 | Objective-C Class | PodsDummy_RCT_Folly`
  - `10280998 | Objective-C Class | PodsDummy_fmt`
  - `102809E8 | Objective-C Class | PodsDummy_glog`
  - `10280A38 | Objective-C Class | HippySimpleWebViewManager`
- The app remained responsive while reading these detail rows through Accessibility APIs, which confirms the budgeted section detail path now exposes decoded Objective-C class entries for the real `kugou` sample.
