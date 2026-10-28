#!/usr/bin/env bash
# Build and test jkai chat's pure Swift on Linux, in Docker.
#
#   scripts/chat-check.sh
#
# Like `home-check.sh`, for the chat thread: the desk's models and its live
# reducer (`Chat/DeskModels.swift`, `Chat/PanelReducer.swift`), the send and
# stream rules and `/chat/active`'s answer (`Chat/TurnStream.swift`), the
# phone channel's frames and routing (`Chat/JkaiEvents.swift`), a turn's map
# (`Chat/ChatMap.swift`), thread links (`Chat/ChatLink.swift`) and
# read-aloud's text (`Chat/SpokenText.swift`) are Foundation-only by
# design, so they are compiled here as a throwaway SwiftPM module NAMED
# `SRAppleApp` (the tests' `@testable import SRAppleApp` is untouched) with
# `PanelReducerTests`, `TurnStreamTests`, `ChatLinkTests`, `JkaiEventsTests`
# and `ChatMapTests` as its test
# target, in the swift:6.0-jammy image in Swift 5 language mode, as the app
# is. The reducer's fixtures (`SRAppleAppTests/Fixtures/PanelOps`) go beside
# the tests, where their `#filePath` fallback finds them. Every other file
# under Chat/ is put through `swiftc -parse`: no imports resolved, no types
# checked, but the unbalanced brace is caught before CI.
#
# Exits non-zero on any failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${CHAT_CHECK_IMAGE:-swift:6.0-jammy}"
BASE="${CHAT_CHECK_TMP:-${TMPDIR:-/tmp}}"
APP="$ROOT/ios/SRAppleApp"
CHAT="$APP/Chat"
PURE=(Chat/DeskModels.swift Chat/PanelReducer.swift Chat/TurnStream.swift Chat/ChatLink.swift Chat/SpokenText.swift Chat/JkaiEvents.swift Chat/ChatMap.swift)
TESTS=(PanelReducerTests.swift TurnStreamTests.swift ChatLinkTests.swift JkaiEventsTests.swift ChatMapTests.swift)

command -v docker >/dev/null || { echo "chat-check: docker is not installed" >&2; exit 2; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE" >/dev/null

mkdir -p "$BASE"
WORK="$(mktemp -d "$BASE/chat-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/SRAppleApp" "$WORK/Tests/SRAppleAppTests/Fixtures" "$WORK/parse"

for name in "${PURE[@]}"; do
  file="$APP/$name"
  imports="$({ grep -E '^[[:space:]]*import[[:space:]]' "$file" || true; } | awk '{print $NF}' | sort -u | tr '\n' ' ' | sed 's/ $//')"
  if [ "$imports" != "Foundation" ]; then
    echo "chat-check: $name must import only Foundation (it imports: ${imports:-nothing})" >&2
    exit 1
  fi
  cp "$file" "$WORK/Sources/SRAppleApp/"
done
for file in "$CHAT"/*.swift; do
  case " ${PURE[*]} " in *" Chat/$(basename "$file") "*) continue ;; esac
  cp "$file" "$WORK/parse/"
done
for name in "${TESTS[@]}"; do cp "$ROOT/ios/SRAppleAppTests/$name" "$WORK/Tests/SRAppleAppTests/"; done
cp -R "$ROOT/ios/SRAppleAppTests/Fixtures/PanelOps" "$WORK/Tests/SRAppleAppTests/Fixtures/"

cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChatCheck",
    products: [.library(name: "SRAppleApp", targets: ["SRAppleApp"])],
    targets: [
        .target(name: "SRAppleApp", path: "Sources/SRAppleApp"),
        .testTarget(name: "SRAppleAppTests", dependencies: ["SRAppleApp"], path: "Tests/SRAppleAppTests", exclude: ["Fixtures"]),
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
    [ "$status" = 0 ] && echo "chat-check: parse clean" || echo "chat-check: PARSE FAILED"
    swift build --build-tests 2>&1 | grep -v "^\[" ; build=${PIPESTATUS[0]}
    if [ "$build" != 0 ]; then echo "chat-check: BUILD FAILED"; exit 1; fi
    swift test --skip-build 2>&1; test=$?
    if [ "$test" != 0 ]; then echo "chat-check: TESTS FAILED"; exit 1; fi
    [ "$status" = 0 ] || exit 1
    echo "chat-check: OK"
  '
