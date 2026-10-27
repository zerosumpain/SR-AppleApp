#!/usr/bin/env bash
# Build and test Home's pure Swift on Linux, in Docker.
#
#   scripts/home-check.sh
#
# Like `offline-check.sh`, for Home and msg family: the briefing's ranking
# (`Home/HomeBriefing.swift`), the morning report's wire shape
# (`Home/MorningReport.swift`) and msg family's tools
# (`Family/FamilyMessageTools.swift`) are Foundation-only by design, so they
# are compiled here as a throwaway SwiftPM module NAMED `SRAppleApp` (the
# tests' `@testable import SRAppleApp` is untouched) with their test files
# (`HomeBriefingTests`, `MorningReportTests`, `FamilyMessageToolsTests`) as its test target, in the
# swift:6.0-jammy image in Swift 5 language mode, as the app is. Every other
# file under Home/ is put through `swiftc -parse`: no imports resolved, no
# types checked, but the unbalanced brace is caught before CI.
#
# Exits non-zero on any failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${HOME_CHECK_IMAGE:-swift:6.0-jammy}"
BASE="${HOME_CHECK_TMP:-${TMPDIR:-/tmp}}"
APP="$ROOT/ios/SRAppleApp"
HOMEDIR="$APP/Home"
PURE=(Home/HomeBriefing.swift Home/MorningReport.swift Family/FamilyMessageTools.swift)
TESTS=(HomeBriefingTests.swift MorningReportTests.swift FamilyMessageToolsTests.swift)

command -v docker >/dev/null || { echo "home-check: docker is not installed" >&2; exit 2; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE" >/dev/null

mkdir -p "$BASE"
WORK="$(mktemp -d "$BASE/home-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/SRAppleApp" "$WORK/Tests/SRAppleAppTests" "$WORK/parse"

for name in "${PURE[@]}"; do
  file="$APP/$name"
  imports="$({ grep -E '^[[:space:]]*import[[:space:]]' "$file" || true; } | awk '{print $NF}' | sort -u | tr '\n' ' ' | sed 's/ $//')"
  if [ "$imports" != "Foundation" ]; then
    echo "home-check: $name must import only Foundation (it imports: ${imports:-nothing})" >&2
    exit 1
  fi
  cp "$file" "$WORK/Sources/SRAppleApp/"
done
for file in "$HOMEDIR"/*.swift; do
  case " ${PURE[*]} " in *" Home/$(basename "$file") "*) continue ;; esac
  cp "$file" "$WORK/parse/"
done
for name in "${TESTS[@]}"; do cp "$ROOT/ios/SRAppleAppTests/$name" "$WORK/Tests/SRAppleAppTests/"; done

cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HomeCheck",
    products: [.library(name: "SRAppleApp", targets: ["SRAppleApp"])],
    targets: [
        .target(name: "SRAppleApp", path: "Sources/SRAppleApp"),
        .testTarget(name: "SRAppleAppTests", dependencies: ["SRAppleApp"], path: "Tests/SRAppleAppTests"),
    ],
    swiftLanguageVersions: [.v5]
)
SWIFT

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp/home \
  -v "$WORK:/pkg" -w /pkg \
  "$IMAGE" bash -c '
    set -uo pipefail
    mkdir -p "$HOME"
    status=0
    for f in ./parse/*.swift; do
      out=$(swiftc -parse "$f" 2>&1 | grep -v "warning: libc not found")
      if [ -n "$out" ]; then echo "--- parse: ${f#./parse/}"; echo "$out"; status=1; fi
    done
    [ "$status" = 0 ] && echo "home-check: parse clean" || echo "home-check: PARSE FAILED"
    swift build --build-tests 2>&1 | grep -v "^\[" ; build=${PIPESTATUS[0]}
    if [ "$build" != 0 ]; then echo "home-check: BUILD FAILED"; exit 1; fi
    swift test --skip-build 2>&1; test=$?
    if [ "$test" != 0 ]; then echo "home-check: TESTS FAILED"; exit 1; fi
    [ "$status" = 0 ] || exit 1
    echo "home-check: OK"
  '
