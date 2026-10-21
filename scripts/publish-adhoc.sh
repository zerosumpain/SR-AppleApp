#!/bin/bash
# Publish the ad-hoc copy as a draft release and keep the newest few, where
# SR-Main fetches them with its own token (SR-Main `$lib/github/adhoc-builds`).
#
# A draft, never a published release: this repository is public, and the IPA's
# embedded profile lists the UDIDs it installs on. A draft is visible only to
# accounts that can push. The new draft is made before any old one goes, so the
# install page always has one to offer.
#
# Several are kept (ADHOC_KEEP, default 5) because SR-Main's /admin/access/app
# releases a chosen build to the family and sends a chosen build to one phone:
# with a single draft there was never an older build to roll back to, and the
# picker only ever showed the latest. Drafts are ranked by run number, read
# from the tag (adhoc-<run>), so a re-run of an old workflow never evicts a
# newer copy.
set -euo pipefail
ipa="$1"
meta="$2"
repo="$GITHUB_REPOSITORY"
name='Ad-hoc build'
tag="adhoc-$GITHUB_RUN_NUMBER"
keep="${ADHOC_KEEP:-5}"
case "$keep" in '' | *[!0-9]*) echo "ADHOC_KEEP must be a whole number, got '$keep'" >&2; exit 2 ;; esac
test "$keep" -ge 1

gh release create "$tag" --repo "$repo" --draft --title "$name" --target "$GITHUB_SHA" \
  --notes "The iPhone app signed ad hoc, for phones that cannot use TestFlight. Installed from strangeramblings.com/app, never from here. The newest $keep copies are kept." \
  "$ipa" "$meta"
new_id=$(gh api "repos/$repo/releases?per_page=100" --jq ".[] | select(.draft and .tag_name == \"$tag\") | .id")
test -n "$new_id"

# Every "Ad-hoc build" draft with an adhoc-<run> tag, newest run first; the new
# one is always kept, whatever its run number, and the rest beyond $keep go.
stale=$(gh api "repos/$repo/releases?per_page=100" --jq "
  [ .[] | select(.draft and .name == \"$name\" and (.tag_name | test(\"^adhoc-[0-9]+\$\")))
    | {id, run: (.tag_name | ltrimstr(\"adhoc-\") | tonumber)} ]
  | sort_by(-.run)
  | map(select(.id != $new_id))
  | .[($keep - 1):]
  | .[].id")
for id in $stale; do
  gh api -X DELETE "repos/$repo/releases/$id" >/dev/null
done
echo "Published the ad-hoc copy as draft release $tag; keeping the newest $keep."
