## 1. Launch Services document type modeling

- [x] 1.1 Audit the current `MachOKnife/Info.plist` bundle metadata and choose the minimal Mach-O / archive content-type set needed for Finder association.
- [x] 1.2 Add `CFBundleDocumentTypes` and any required imported content-type declarations so MachOKnife is registered as a viewer for supported Mach-O family files and static library archives.
- [x] 1.3 Confirm the generated app bundle metadata contains the expected document roles, content types, and bundle-container exclusions.

## 2. Open-path verification

- [x] 2.1 Review the existing `application(_:openFiles:)` to workspace open flow and make any minimal adjustments needed so Finder-launched files reuse the current document path unchanged.
- [x] 2.2 Add or update focused tests covering Finder/system-opened file routing through the existing application open-files flow.

## 3. Finder behavior verification

- [x] 3.1 Create manual verification steps for Finder `Open With`, default-app switching, supported `.a` / `.dylib` / Mach-O samples, and extensionless best-effort cases.
- [x] 3.2 Run the verification checklist against a built app and record any Launch Services or Finder caveats needed for repeatable validation.
