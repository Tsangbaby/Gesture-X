#!/bin/bash
# Observation-only child of the failed handset candidate, cloud RootHide only.
set -euo pipefail
: "${THEOS:?Pinned RootHide Theos required}"
: "${OUT_DIR:?Artifact directory required}"
: "${RUNNER_TEMP:?Cloud Mac runner required}"
: "${GITHUB_SHA:?Exact CI SHA required}"
test "$(uname -s)" = Darwin
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
test "$GITHUB_REPOSITORY" = Tsangbaby/Gesture-X
test "$(git -C "$THEOS" rev-parse HEAD)" = "$THEOS_REF"
ROOT=$(git rev-parse --show-toplevel)
STAGE="$RUNNER_TEMP/bottom-diag-stage"
mkdir -p "$OUT_DIR"
python3 -B ci/bottom_diagnostic.py prepare --output "$STAGE" --source-sha "$GITHUB_SHA" > "$OUT_DIR/DIAGNOSTIC_SCOPE.json"
cp "$STAGE/ci/BottomDiagnosticBuild.swift" "$OUT_DIR/BottomDiagnosticBuild.swift"
{
    xcodebuild -version
    xcrun swift --version
    printf 'Source: %s\nTheos: %s\nSDK source: %s\n' "$GITHUB_SHA" "$THEOS_REF" "$SDK_REF"
    git -C "$THEOS" submodule status --recursive
} > "$OUT_DIR/TOOLCHAIN.txt"
cd "$STAGE"
FILES=$(python3 -B -c 'import re;from pathlib import Path;m=re.search(r"^TapLock_FILES = (.+)$",Path("Makefile").read_text(),re.M);assert m;print(m[1]+" ci/BottomDiagnosticBuild.swift")')
args=(THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1 INSTALL=0
      'TARGET=iphone:clang:16.5:15.0' 'ARCHS=arm64 arm64e'
      "TapLock_FILES=$FILES"
      'TapLock_SWIFTFLAGS=-IInterfaces -enable-experimental-feature SymbolLinkageMarkers -D BOTTOM_GESTURE_DIAGNOSTIC')
make all "${args[@]}" 2>&1 | tee "$OUT_DIR/compile.log"
make package "${args[@]}" 2>&1 | tee "$OUT_DIR/package.log"
python3 -B ci/verify_package.py packages --report "$OUT_DIR/VERIFICATION.json"
python3 -B -c 'import hashlib,os,shutil;from pathlib import Path;p=list(Path("packages").glob("*.deb"));assert len(p)==1;out=Path(os.environ["OUT_DIR"]);d=out/p[0].name;shutil.copy2(p[0],d);(out/"SHA256SUMS.txt").write_text(hashlib.sha256(d.read_bytes()).hexdigest()+"  "+d.name+"\n")'
printf '%s\n' "$GITHUB_SHA" > "$OUT_DIR/SOURCE_COMMIT.txt"
printf '%s\n' "$GITHUB_REPOSITORY" > "$OUT_DIR/SOURCE_REPOSITORY.txt"
# Prove staging left the tracked source/metadata untouched.
cd "$ROOT"
test -z "$(git status --porcelain)"
