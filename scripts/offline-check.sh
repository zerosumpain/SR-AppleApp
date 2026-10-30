#!/usr/bin/env bash
# Build and test the offline games' pure Swift on Linux, in Docker.
#
#   scripts/offline-check.sh              # every Offline*Tests.swift
#   scripts/offline-check.sh QuickDraw    # only tests whose name matches
#
# There is no Xcode on this box, so SwiftUI, MultipeerConnectivity and
# Network.framework cannot be compiled here — only the macOS CI job can. But
# the rules of every offline game are Foundation-only by design, so this
# script builds a throwaway SwiftPM package whose library module is NAMED
# `SRAppleApp` (so the tests' `@testable import SRAppleApp` is untouched) from:
#
#   ios/SRAppleApp/Offline/Core/*.swift      that import nothing but Foundation
#   ios/SRAppleApp/Offline/Games/**/*Logic.swift   (must be Foundation-only)
#
# with a test target of ios/SRAppleAppTests/Offline*Tests.swift, and runs
# `swift build` + `swift test` in the swift:6.0-jammy image in Swift 5 language
# mode, as the app is. Every other .swift file under Offline/ is put through
# `swiftc -parse` as well: that resolves no imports and checks no types, but
# it catches the unbalanced brace and the broken interpolation before CI does.
#
# Each run builds in its own fresh temp directory, so several can run at once.
# Exits non-zero on any failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="${1:-}"
IMAGE="${OFFLINE_CHECK_IMAGE:-swift:6.0-jammy}"
BASE="${OFFLINE_CHECK_TMP:-${TMPDIR:-/tmp}}"
OFFLINE="$ROOT/ios/SRAppleApp/Offline"
TESTS="$ROOT/ios/SRAppleAppTests"

command -v docker >/dev/null || { echo "offline-check: docker is not installed" >&2; exit 2; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE" >/dev/null

mkdir -p "$BASE"
WORK="$(mktemp -d "$BASE/offline-check.XXXXXX")"
cleanup() {
  # The container writes as this user, so a plain rm works.
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/Sources/SRAppleApp" "$WORK/Tests/SRAppleAppTests" "$WORK/parse"

# The modules a file imports, space-separated and sorted.
imports_of() {
  { grep -E '^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]' "$1" || true; } \
    | awk '{print $NF}' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

fail=0
compiled=0

# Core: Foundation-only files are compiled; the rest are parsed.
for file in "$OFFLINE"/Core/*.swift; do
  [ -e "$file" ] || continue
  rel="${file#"$OFFLINE"/}"
  if [ "$(imports_of "$file")" = "Foundation" ]; then
    mkdir -p "$WORK/Sources/SRAppleApp/$(dirname "$rel")"
    cp "$file" "$WORK/Sources/SRAppleApp/$rel"
    compiled=$((compiled + 1))
  else
    mkdir -p "$WORK/parse/$(dirname "$rel")"
    cp "$file" "$WORK/parse/$rel"
  fi
done

# Every game's rules: Foundation-only, no exceptions.
while IFS= read -r file; do
  rel="${file#"$OFFLINE"/}"
  imports="$(imports_of "$file")"
  if [ "$imports" != "Foundation" ]; then
    echo "offline-check: $rel must import only Foundation (it imports: ${imports:-nothing})" >&2
    fail=1
    continue
  fi
  mkdir -p "$WORK/Sources/SRAppleApp/$(dirname "$rel")"
  cp "$file" "$WORK/Sources/SRAppleApp/$rel"
  compiled=$((compiled + 1))
done < <(find "$OFFLINE/Games" "$OFFLINE/UI" -name '*Logic.swift' 2>/dev/null | sort)

# Everything else under Offline/ (views, links, the session): parse only.
while IFS= read -r file; do
  rel="${file#"$OFFLINE"/}"
  case "$rel" in
    Core/*) continue ;;
    *Logic.swift) continue ;;
  esac
  mkdir -p "$WORK/parse/$(dirname "$rel")"
  cp "$file" "$WORK/parse/$rel"
done < <(find "$OFFLINE" -name '*.swift' | sort)

# Car Race's nearby rules live with the physics games and lean on their
# track and timing logic, both Foundation-only; so does its split screen's.
# Their tests come along below.
for name in CarRaceLogic CarRaceNearbyRules CarRaceSplitLogic; do
  cp "$ROOT/ios/SRAppleApp/Games/Physics/$name.swift" "$WORK/Sources/SRAppleApp/"
  compiled=$((compiled + 1))
done

# The word games' list. Linux has no app bundle, so the tests read it from the
# source tree's layout (OfflineWordsTests.install walks up from the test file
# to SRAppleApp/Offline/Words/): it goes in the package at the same place.
mkdir -p "$WORK/SRAppleApp/Offline/Words"
cp "$OFFLINE/Words/offline-words.txt" "$WORK/SRAppleApp/Offline/Words/"

tests=0
for name in CarRaceNearbyTests CarRaceSplitTests; do
  cp "$TESTS/$name.swift" "$WORK/Tests/SRAppleAppTests/"
  tests=$((tests + 1))
done
for file in "$TESTS"/Offline*Tests.swift; do
  [ -e "$file" ] || continue
  cp "$file" "$WORK/Tests/SRAppleAppTests/"
  tests=$((tests + 1))
done

[ "$fail" = 0 ] || exit 1
if [ "$compiled" = 0 ]; then echo "offline-check: nothing to compile under $OFFLINE" >&2; exit 1; fi
if [ "$tests" = 0 ]; then echo "offline-check: no Offline*Tests.swift in $TESTS" >&2; exit 1; fi

cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OfflineCheck",
    products: [.library(name: "SRAppleApp", targets: ["SRAppleApp"])],
    targets: [
        .target(name: "SRAppleApp", path: "Sources/SRAppleApp"),
        .testTarget(name: "SRAppleAppTests", dependencies: ["SRAppleApp"], path: "Tests/SRAppleAppTests"),
    ],
    swiftLanguageVersions: [.v5]
)
SWIFT

echo "offline-check: $compiled source files, $tests test files${FILTER:+, filter '$FILTER'}"

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
    [ "$status" = 0 ] && echo "offline-check: parse clean" || echo "offline-check: PARSE FAILED"
    swift build --build-tests 2>&1 | grep -v "^\[" ; build=${PIPESTATUS[0]}
    if [ "$build" != 0 ]; then echo "offline-check: BUILD FAILED"; exit 1; fi
    if [ -n "$FILTER" ]; then
      swift test --skip-build --filter "$FILTER" 2>&1 | tee /tmp/test.log; test=${PIPESTATUS[0]}
      if grep -q "No matching test cases were run" /tmp/test.log; then
        echo "offline-check: no test matched filter \"$FILTER\""; test=1
      fi
    else
      swift test --skip-build 2>&1; test=$?
    fi
    if [ "$test" != 0 ]; then echo "offline-check: TESTS FAILED"; exit 1; fi
    [ "$status" = 0 ] || exit 1
    echo "offline-check: OK"
  '
