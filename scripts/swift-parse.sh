#!/usr/bin/env bash
# Parse every Swift source on porkserv, because this box has no Swift and the
# only other compiler is a macOS runner that costs 20 minutes at a 10x billing
# multiplier. `swiftc -parse` resolves no imports and checks no types, so it
# proves nothing about SwiftUI usage — it catches the unbalanced brace, the
# stray comma and the malformed string interpolation, which is the whole class
# of mistake you make writing a thousand lines of Swift blind.
#
#   ./scripts/swift-parse.sh
#
# A clean run is NOT a green build. It is the cheap half of one.
set -uo pipefail
REMOTE="${SWIFT_REMOTE_HOST:-porkserv}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN='$HOME/swift-toolchain/swift-6.1.2-RELEASE-debian12/usr/bin/swiftc'
SHIM='$HOME/swift-toolchain/shim'
WORK='$HOME/swift-parse'

rsync -a --delete --quiet -e ssh "$ROOT/ios/" "$REMOTE:swift-parse/" || exit 2

ssh "$REMOTE" "bash -s" <<REMOTESH
set -uo pipefail
cd "$WORK" || exit 2
fail=0
while IFS= read -r f; do
  out=\$(LD_LIBRARY_PATH="$SHIM" "$TOOLCHAIN" -parse "\$f" 2>&1 \
        | grep -v 'warning: libc not found' | grep -v '^<unknown>:0: warning')
  if [ -n "\$out" ]; then
    echo "--- \$f"
    echo "\$out"
    fail=1
  fi
done < <(find . -name '*.swift' | sort)
if [ "\$fail" = 0 ]; then echo "swift -parse: clean"; fi
exit \$fail
REMOTESH
