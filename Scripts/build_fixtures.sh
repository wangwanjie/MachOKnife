#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/Resources/Fixtures/generated"
SOURCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/machoknife-fixtures.XXXXXX")"

cleanup() {
  rm -rf "$SOURCE_DIR"
}
trap cleanup EXIT

mkdir -p "$FIXTURE_DIR"

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

echo "Built fixture dylibs in $FIXTURE_DIR"
