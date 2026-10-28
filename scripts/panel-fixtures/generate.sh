#!/usr/bin/env bash
# Regenerate ios/SRAppleAppTests/Fixtures/PanelOps/panel-ops.json from the WEB
# code, so the phone's PanelReducer is tested against the reducer it copies.
#
#   scripts/panel-fixtures/generate.sh [SR-Jkai-Core checkout] [SR-Main checkout]
#
# Defaults to sibling clones (../SR-Jkai-Core, ../SR-Main), which need their
# node_modules (Core's provides esbuild and zod). The fixture names the commit
# of each it came from. Run it after a change to Core's panel/apply.ts,
# schema.ts or turn-desk.ts, or Main's nativePanel — never edit the JSON.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE="$(cd "${1:-$ROOT/../SR-Jkai-Core}" && pwd)"
MAIN="$(cd "${2:-$ROOT/../SR-Main}" && pwd)"
OUT="$ROOT/ios/SRAppleAppTests/Fixtures/PanelOps/panel-ops.json"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

core_sha="$(git -C "$CORE" rev-parse --short HEAD)"
main_sha="$(git -C "$MAIN" rev-parse --short HEAD)"
node "$ROOT/scripts/panel-fixtures/build.mjs" "$CORE" "$MAIN" "$WORK/gen.mjs"
mkdir -p "$(dirname "$OUT")"
node "$WORK/gen.mjs" "$OUT" "SR-Jkai-Core $core_sha (src/lib/jkai/panel/apply.ts, schema.ts, turn-desk.ts) + SR-Main $main_sha (src/lib/jkai/native-rich.ts nativePanel), generated $(date -u +%Y-%m-%d)"
