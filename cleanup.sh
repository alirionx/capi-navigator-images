#!/bin/bash
# Deletes released images the rule no longer keeps (IMG-F-70): of every image that matrix.sh lists,
# the newest build stays; older builds and images outside the rule are deleted. SHA256SUMS and the
# notes of a release follow; a release without images left is deleted together with its tag.
#
#   ./cleanup.sh                  # dry run: only prints what it would delete
#   DRY_RUN=false ./cleanup.sh    # deletes
#
# Needs gh with write access to the repository (GH_TOKEN in CI).
set -euo pipefail
cd "$(dirname "$0")"
REPO="${GITHUB_REPOSITORY:-alirionx/capi-navigator-images}"
DRY_RUN="${DRY_RUN:-true}"

keep="$(./matrix.sh images)"
[ -n "$keep" ] || { echo "the rule lists no images, nothing deleted" >&2; exit 1; }

# Releases of the build workflow, newest first.
tags="$(gh release list -R "$REPO" -L 1000 --json tagName,createdAt \
  --jq 'map(select(.tagName | startswith("images-"))) | sort_by(.createdAt) | reverse | .[].tagName')"

declare -A newest=()
for tag in $tags; do
  images="$(gh release view "$tag" -R "$REPO" --json assets --jq '.assets[].name | select(endswith(".qcow2"))')"
  drop=()
  for f in $images; do
    name="${f%.qcow2}"
    if ! grep -qxF "$name" <<<"$keep"; then
      drop+=("$f"); echo "$tag: $f (not in the rule)"
    elif [ -n "${newest[$name]:-}" ]; then
      drop+=("$f"); echo "$tag: $f (newer build in ${newest[$name]})"
    else
      newest[$name]="$tag"; echo "$tag: $f kept"
    fi
  done
  [ "${#drop[@]}" -gt 0 ] || continue
  [ "$DRY_RUN" = false ] || { echo "$tag: dry run, nothing deleted"; continue; }

  if [ "${#drop[@]}" = "$(wc -w <<<"$images")" ]; then
    gh release delete "$tag" -R "$REPO" --cleanup-tag -y
    echo "$tag: release and tag deleted"
    continue
  fi
  for f in "${drop[@]}"; do gh release delete-asset "$tag" "$f" -R "$REPO" -y; done
  # SHA256SUMS and the image table of the notes list only what is left.
  work="$(mktemp -d)"
  gh release download "$tag" -R "$REPO" -p SHA256SUMS -D "$work"
  gh release view "$tag" -R "$REPO" --json body --jq .body > "$work/notes.md"
  for f in "${drop[@]}"; do
    grep -vF "  $f" "$work/SHA256SUMS" > "$work/sums" || true; mv "$work/sums" "$work/SHA256SUMS"
    grep -vF "| \`$f\` |" "$work/notes.md" > "$work/notes" || true; mv "$work/notes" "$work/notes.md"
  done
  printf '\nRemoved by the cleanup on %s: %s\n' "$(date -u +%F)" "${drop[*]}" >> "$work/notes.md"
  gh release upload "$tag" "$work/SHA256SUMS" -R "$REPO" --clobber
  gh release edit "$tag" -R "$REPO" --notes-file "$work/notes.md"
  rm -rf "$work"
  echo "$tag: ${#drop[@]} image(s) deleted"
done
