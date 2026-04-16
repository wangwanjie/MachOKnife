# Manual Verification

## 2026-04-16

- Build/test command used:
  - `xcodebuild test -workspace MachOKnife.xcworkspace -scheme MachOKnifeTests -destination 'platform=macOS' -only-testing:MachOKnifeTests/ProjectConfigurationTests -only-testing:MachOKnifeTests/AppDelegateDocumentOpenTests`
- Result: passed
- Built app:
  - `/Users/VanJay/Library/Developer/Xcode/DerivedData/MachOKnife-alxoeyktybgvesemqmgubrnbfgrn/Build/Products/Debug/MachOKnife.app`

## Metadata Audit Result

- `MachOKnife/Info.plist` previously had no `CFBundleDocumentTypes` or `UTImportedTypeDeclarations`.
- The implemented minimal Finder association set is:
  - `com.apple.mach-o-binary`
  - `com.apple.mach-o-executable`
  - `public.unix-executable` for extensionless executables that Launch Services classifies generically
  - `com.apple.mach-o-object`
  - `com.apple.mach-o-dylib`
  - `cn.vanjay.machoknife.static-library-archive` for `.a`
- Bundle containers remain out of scope:
  - no `.app`
  - no `.framework`
  - no `.appex`

## Generated Bundle Metadata Check

- Inspected:
  - `/Users/VanJay/Library/Developer/Xcode/DerivedData/MachOKnife-alxoeyktybgvesemqmgubrnbfgrn/Build/Products/Debug/MachOKnife.app/Contents/Info.plist`
- Confirmed:
  - `CFBundleDocumentTypes` exists
  - every declared type uses `CFBundleTypeRole = Viewer`
  - Mach-O executable/binary/object/dylib content types are present
  - the executable document type also declares `public.unix-executable` for extensionless Finder classification
  - custom static archive UTI is present and maps extension `.a`
  - bundle-container extensions are not declared

## Open-Path Verification

- Focused automated test:
  - `finder-opened files route through the existing main window document open flow`
- Confirmed:
  - `AppDelegate.application(_:openFiles:)` routes files to `MainWindowControlling.openDocument(at:)`
  - no Finder-only alternate open path was introduced

## CLI-Executable Finder Simulation

- Commands run successfully:
  - `open -a /Users/VanJay/Library/Developer/Xcode/DerivedData/MachOKnife-alxoeyktybgvesemqmgubrnbfgrn/Build/Products/Debug/MachOKnife.app /Users/VanJay/Documents/Work/Private/MachOKnife/Resources/Fixtures/cli/libCLIEditable.dylib`
  - `open -a /Users/VanJay/Library/Developer/Xcode/DerivedData/MachOKnife-alxoeyktybgvesemqmgubrnbfgrn/Build/Products/Debug/MachOKnife.app /Users/VanJay/Documents/Work/Private/MachOKnife/build/SparkleTools/Build/Products/Release/libbsdiff.a`
  - `open -a /Users/VanJay/Library/Developer/Xcode/DerivedData/MachOKnife-alxoeyktybgvesemqmgubrnbfgrn/Build/Products/Debug/MachOKnife.app /bin/ls`

## Finder Checklist For Interactive Re-Verification

- Right-click a `.dylib` sample and confirm `Open With` includes `MachOKnife`
- Right-click a `.a` sample and confirm `Open With` includes `MachOKnife`
- Inspect an `.o` sample and confirm `Open With` includes `MachOKnife`
- Use Finder `Get Info` to switch a supported file’s default app to `MachOKnife`, then reopen it
- Try an extensionless Mach-O sample such as `/bin/ls` and confirm whether Finder classifies it strongly enough to expose `MachOKnife`
- Confirm `.app`, `.framework`, and `.appex` bundle containers do not become supported targets for this change

## Caveats

- This terminal session can verify bundle metadata, Launch Services registration during build, and `open -a` dispatch, but it cannot directly assert Finder context-menu presentation without interactive GUI inspection.
- `NSWorkspace.typeOfFile` classified both `/bin/ls` and the archived `PinballMachine` executable sample as `public.unix-executable`, so declaring only `com.apple.mach-o-executable` is insufficient for Finder `Open With` on those paths.
- Extensionless Mach-O support remains best-effort and depends on macOS classification of the selected file.
