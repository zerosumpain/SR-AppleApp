#!/bin/bash
# Keep the newest ad-hoc copies as draft releases (tag adhoc-<run>), where
# SR-Main's /install page fetches the RELEASED one with its own token (SR-Main
# `$lib/github/adhoc-builds`, `$lib/github/app-release`). The owner chooses on
# /admin/access/app which build the family's phones are offered, so a new copy
# waits there until he releases it — and an older one must still be here to
# roll back to. Hence the newest KEEP drafts, not one.
#
# A draft, never a published release: this repository is public, and the IPA's
# embedded profile lists the UDIDs it installs on. A draft is visible only to
# accounts that can push. The new draft is made before old ones go, so the
# install page always has one to offer.
set -euo pipefail
ipa="$1"
meta="$2"
repo="$GITHUB_REPOSITORY"
name='Ad-hoc build'
tag="adhoc-$GITHUB_RUN_NUMBER"

gh release create "$tag" --repo "$repo" --draft --title "$name" --target "$GITHUB_SHA" \
  --notes "The iPhone app signed ad hoc, for phones that cannot use TestFlight. Installed from strangeramblings.com/install, never from here. Replaced on every build." \
  "$ipa" "$meta"
new_id=$(gh api "repos/$repo/releases?per_page=100" --jq ".[] | select(.draft and .tag_name == \"$tag\") | .id")
test -n "$new_id"
keep=10
# Newest first by build number (the tag), the new draft among them; everything
# past the newest $keep goes.
for id in $(gh api "repos/$repo/releases?per_page=100" --jq "[.[] | select(.draft and .name == \"$name\" and (.tag_name | test(\"^adhoc-[0-9]+$\")))] | sort_by(.tag_name | ltrimstr(\"adhoc-\") | tonumber) | reverse | .[$keep:] | .[].id"); do
  gh api -X DELETE "repos/$repo/releases/$id" >/dev/null
done
echo "Published the ad-hoc copy as draft release $tag."
