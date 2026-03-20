#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/Resources/Fixtures/generated"
CLI_FIXTURE_DIR="$REPO_ROOT/Resources/Fixtures/cli"
SOURCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/machoknife-fixtures.XXXXXX")"

cleanup() {
  rm -rf "$SOURCE_DIR"
}
trap cleanup EXIT

mkdir -p "$FIXTURE_DIR"
mkdir -p "$CLI_FIXTURE_DIR"

cat >"$SOURCE_DIR/dependency.c" <<'EOF'
int fixture_dependency_value(void) {
  return 7;
}
EOF

cat >"$SOURCE_DIR/fixture.c" <<'EOF'
extern int fixture_dependency_value(void);

int fixture_entrypoint(void) {
  return fixture_dependency_value();
}
EOF

cat >"$SOURCE_DIR/cli_dependency.c" <<'EOF'
int cli_dependency_value(void) {
  return 3;
}
EOF

cat >"$SOURCE_DIR/cli_fixture.c" <<'EOF'
extern int cli_dependency_value(void);

int cli_fixture_entrypoint(void) {
  return cli_dependency_value();
}
EOF

cat >"$SOURCE_DIR/cache_dependency.c" <<'EOF'
int cache_dependency_value(void) {
  return 4;
}
EOF

cat >"$SOURCE_DIR/cache_fixture.c" <<'EOF'
extern int cache_dependency_value(void);

int cache_fixture_entrypoint(void) {
  return cache_dependency_value();
}
EOF

clang \
  -arch x86_64 \
  -dynamiclib \
  "$SOURCE_DIR/dependency.c" \
  -install_name @rpath/libFixtureDependency.dylib \
  -current_version 1.0 \
  -compatibility_version 1.0 \
  -o "$FIXTURE_DIR/libFixtureDependency.dylib"

clang \
  -arch x86_64 \
  -dynamiclib \
  "$SOURCE_DIR/fixture.c" \
  -L"$FIXTURE_DIR" \
  -lFixtureDependency \
  -Wl,-rpath,@loader_path \
  -install_name @rpath/libFixture.dylib \
  -current_version 1.0 \
  -compatibility_version 1.0 \
  -o "$FIXTURE_DIR/libFixture.dylib"

clang \
  -target x86_64-apple-macos13.0 \
  -dynamiclib \
  "$SOURCE_DIR/cli_dependency.c" \
  -install_name @rpath/libCLIDependency.dylib \
  -current_version 1.0 \
  -compatibility_version 1.0 \
  -o "$CLI_FIXTURE_DIR/libCLIDependency.dylib"

clang \
  -target x86_64-apple-macos13.0 \
  -dynamiclib \
  "$SOURCE_DIR/cli_fixture.c" \
  -L"$CLI_FIXTURE_DIR" \
  -lCLIDependency \
  -Wl,-headerpad,0x4000 \
  -Wl,-rpath,@loader_path/Frameworks \
  -install_name @rpath/libCLIEditable.dylib \
  -current_version 1.0 \
  -compatibility_version 1.0 \
  -o "$CLI_FIXTURE_DIR/libCLIEditable.dylib"

codesign -s - "$CLI_FIXTURE_DIR/libCLIEditable.dylib"

clang \
  -target x86_64-apple-macos13.0 \
  -dynamiclib \
  "$SOURCE_DIR/cache_dependency.c" \
  -install_name /usr/lib/libCacheDependency.dylib \
  -current_version 1.0 \
  -compatibility_version 1.0 \
  -o "$CLI_FIXTURE_DIR/libCacheDependency.dylib"

clang \
  -target x86_64-apple-macos13.0 \
  -dynamiclib \
  "$SOURCE_DIR/cache_fixture.c" \
  -L"$CLI_FIXTURE_DIR" \
  -lCacheDependency \
  -Wl,-headerpad,0x4000 \
  -install_name /usr/lib/libCacheStyle.dylib \
  -current_version 1.0 \
  -compatibility_version 1.0 \
  -o "$CLI_FIXTURE_DIR/libCacheStyle.dylib"

echo "Built fixture dylibs in $FIXTURE_DIR and $CLI_FIXTURE_DIR"
