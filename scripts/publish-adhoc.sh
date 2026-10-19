#!/bin/bash
# Keep the newest ad-hoc copy in ONE draft release, where SR-Main's /install
# page fetches it with its own token (SR-Main `$lib/server/adhoc-builds`).
#
# A draft, never a published release: this repository is public, and the IPA's
# embedded profile lists the UDIDs it installs on. A draft is visible only to
# accounts that can push. The new draft is made before the old ones go, so the
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
for id in $(gh api "repos/$repo/releases?per_page=100" --jq ".[] | select(.draft and .name == \"$name\" and .id != $new_id) | .id"); do
  gh api -X DELETE "repos/$repo/releases/$id" >/dev/null
done
echo "Published the ad-hoc copy as draft release $tag."
