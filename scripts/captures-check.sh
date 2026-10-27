#!/usr/bin/env bash
# Build and test the Captures feature's pure Swift on Linux, in Docker.
#
#   scripts/captures-check.sh            # every test in CapturesTests.swift
#   scripts/captures-check.sh Owner      # only tests whose name matches
#
# There is no Xcode on this box: SwiftUI, AVFoundation, Speech, Vision,
# ActivityKit and FluidAudio only compile on the macOS CI job. The rules of a
# capture — the wire shapes, the offline queue, putting words on speakers,
# matching the owner's voice and the screenshot deny list — are
# Foundation-only by design, so this builds a throwaway SwiftPM package whose
# library module is NAMED `SRAppleApp` (the tests' `@testable import
# SRAppleApp` is untouched) from every Foundation-only file in
# ios/SRAppleApp/Captures, tests it with ios/SRAppleAppTests/CapturesTests.swift
# in the swift:6.0-jammy image (Swift 5 language mode, as the app is), and puts
# the rest of Captures/ through `swiftc -parse`.
#
# A clean run is NOT a green build. It is the cheap half of one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="${1:-}"
IMAGE="${CAPTURES_CHECK_IMAGE:-swift:6.0-jammy}"
BASE="${CAPTURES_CHECK_TMP:-${TMPDIR:-/tmp}}"
SRC="$ROOT/ios/SRAppleApp/Captures"
TESTS="$ROOT/ios/SRAppleAppTests/CapturesTests.swift"

command -v docker >/dev/null || { echo "captures-check: docker is not installed" >&2; exit 2; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE" >/dev/null

mkdir -p "$BASE"
WORK="$(mktemp -d "$BASE/captures-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/SRAppleApp" "$WORK/Tests/SRAppleAppTests" "$WORK/parse"

imports_of() {
  { grep -E '^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]' "$1" || true; } \
    | awk '{print $NF}' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

compiled=0
for file in "$SRC"/*.swift; do
  [ -e "$file" ] || continue
  # The demo fixtures extend the app's `SRDemoFixtures`, which is not here.
  case "$(basename "$file")" in
    *DemoFixtures.swift) cp "$file" "$WORK/parse/"; continue ;;
  esac
  if [ "$(imports_of "$file")" = "Foundation" ]; then
    cp "$file" "$WORK/Sources/SRAppleApp/"
    compiled=$((compiled + 1))
  else
    cp "$file" "$WORK/parse/"
  fi
done
[ "$compiled" -gt 0 ] || { echo "captures-check: nothing Foundation-only under $SRC" >&2; exit 1; }
cp "$TESTS" "$WORK/Tests/SRAppleAppTests/"

cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CapturesCheck",
    products: [.library(name: "SRAppleApp", targets: ["SRAppleApp"])],
    targets: [
        .target(name: "SRAppleApp", path: "Sources/SRAppleApp"),
        .testTarget(name: "SRAppleAppTests", dependencies: ["SRAppleApp"], path: "Tests/SRAppleAppTests"),
    ],
    swiftLanguageVersions: [.v5]
)
SWIFT

echo "captures-check: $compiled source files${FILTER:+, filter '$FILTER'}"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp/home \
  -e FILTER="$FILTER" \
  -v "$WORK:/pkg" -w /pkg \
  "$IMAGE" bash -c '
    set -uo pipefail
    mkdir -p "$HOME"
    status=0
    while IFS= read -r f; do
      out=$(swiftc -parse "$f" 2>&1 | grep -v "warning: libc not found")
      if [ -n "$out" ]; then echo "--- parse: ${f#./parse/}"; echo "$out"; status=1; fi
    done < <(find ./parse -name "*.swift" | sort)
    [ "$status" = 0 ] && echo "captures-check: parse clean" || echo "captures-check: PARSE FAILED"
    swift build --build-tests 2>&1 | grep -v "^\[" ; build=${PIPESTATUS[0]}
    if [ "$build" != 0 ]; then echo "captures-check: BUILD FAILED"; exit 1; fi
    if [ -n "$FILTER" ]; then
      swift test --skip-build --filter "$FILTER" 2>&1; test=$?
    else
      swift test --skip-build 2>&1; test=$?
    fi
    if [ "$test" != 0 ]; then echo "captures-check: TESTS FAILED"; exit 1; fi
    [ "$status" = 0 ] || exit 1
    echo "captures-check: OK"
  '
