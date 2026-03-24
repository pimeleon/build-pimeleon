#!/bin/sh
set -eu
# Create a GitHub Release on pimeleon/build-pimeleon with built image artifacts.
# Release notes are auto-generated from conventional commits since the last tag.
#
# Inputs (CI environment):
#   TARGET_PLATFORM, GITHUB_RELEASE_TOKEN, CI_COMMIT_SHORT_SHA, CI_COMMIT_REF_NAME

SCRIPTS_DIR="./shared/scripts"
[ ! -f "./scripts/build.sh" ] || SCRIPTS_DIR="./scripts"

GITHUB_REPO="pimeleon/build-pimeleon"

if [ -z "${GITHUB_RELEASE_TOKEN:-}" ]; then
  echo "Error: GITHUB_RELEASE_TOKEN not set. Cannot create GitHub Release."
  exit 1
fi

chmod +x "${SCRIPTS_DIR}/get-next-version.sh"
VERSION=$("${SCRIPTS_DIR}/get-next-version.sh" "${TARGET_PLATFORM}")
TAG="v${VERSION}"
RELEASE_NAME="Pimeleon ${TARGET_PLATFORM} ${TAG}"

echo "Creating GitHub Release: ${TAG} on ${GITHUB_REPO}"

# Authenticate gh CLI
echo "${GITHUB_RELEASE_TOKEN}" | gh auth login --with-token

# --- Generate release notes from conventional commits ---
PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
if [ -n "$PREV_TAG" ]; then
  GIT_RANGE="${PREV_TAG}..HEAD"
  echo "Changelog range: ${PREV_TAG} → ${TAG}"
else
  GIT_RANGE="HEAD~50..HEAD"
  echo "Changelog: last 50 commits (no previous tag found)"
fi

# Collect commits into category files
TMPDIR=$(mktemp -d)
: > "$TMPDIR/breaking"
: > "$TMPDIR/features"
: > "$TMPDIR/fixes"
: > "$TMPDIR/perf"
: > "$TMPDIR/refactor"
: > "$TMPDIR/ci"
: > "$TMPDIR/docs"
: > "$TMPDIR/other"

# shellcheck disable=SC2086
git log $GIT_RANGE --format="%s" 2>/dev/null | while IFS= read -r msg; do
  [ -z "$msg" ] && continue
  if echo "$msg" | grep -qE '^[a-z]+(\(.+\))?!:'; then
    echo "- ${msg}" >> "$TMPDIR/breaking"
  elif echo "$msg" | grep -qE '^feat(\(.+\))?:'; then
    echo "- ${msg}" >> "$TMPDIR/features"
  elif echo "$msg" | grep -qE '^fix(\(.+\))?:'; then
    echo "- ${msg}" >> "$TMPDIR/fixes"
  elif echo "$msg" | grep -qE '^perf(\(.+\))?:'; then
    echo "- ${msg}" >> "$TMPDIR/perf"
  elif echo "$msg" | grep -qE '^refactor(\(.+\))?:'; then
    echo "- ${msg}" >> "$TMPDIR/refactor"
  elif echo "$msg" | grep -qE '^ci(\(.+\))?:'; then
    echo "- ${msg}" >> "$TMPDIR/ci"
  elif echo "$msg" | grep -qE '^docs(\(.+\))?:'; then
    echo "- ${msg}" >> "$TMPDIR/docs"
  elif echo "$msg" | grep -qE '^(chore|build|style|test)(\(.+\))?:'; then
    echo "- ${msg}" >> "$TMPDIR/other"
  fi
done

# Assemble release notes
NOTES_FILE="$TMPDIR/notes.md"
cat > "$NOTES_FILE" <<HEADER
## Pimeleon ${TARGET_PLATFORM} ${TAG}

**Platform:** \`${TARGET_PLATFORM}\`  |  **Commit:** \`${CI_COMMIT_SHORT_SHA}\`  |  **Branch:** \`${CI_COMMIT_REF_NAME}\`

HEADER

[ ! -s "$TMPDIR/breaking" ]  || { echo "### ⚠️ Breaking Changes"; cat "$TMPDIR/breaking";  echo; } >> "$NOTES_FILE"
[ ! -s "$TMPDIR/features" ]  || { echo "### Features";            cat "$TMPDIR/features";  echo; } >> "$NOTES_FILE"
[ ! -s "$TMPDIR/fixes" ]     || { echo "### Bug Fixes";           cat "$TMPDIR/fixes";     echo; } >> "$NOTES_FILE"
[ ! -s "$TMPDIR/perf" ]      || { echo "### Performance";         cat "$TMPDIR/perf";      echo; } >> "$NOTES_FILE"
[ ! -s "$TMPDIR/refactor" ]  || { echo "### Refactoring";         cat "$TMPDIR/refactor";  echo; } >> "$NOTES_FILE"
[ ! -s "$TMPDIR/ci" ]        || { echo "### CI/CD";               cat "$TMPDIR/ci";        echo; } >> "$NOTES_FILE"
[ ! -s "$TMPDIR/docs" ]      || { echo "### Documentation";       cat "$TMPDIR/docs";      echo; } >> "$NOTES_FILE"
[ ! -s "$TMPDIR/other" ]     || { echo "### Other";               cat "$TMPDIR/other";     echo; } >> "$NOTES_FILE"

cat >> "$NOTES_FILE" <<'FOOTER'
---

### Installation
1. Download the `.img.xz` file
2. Decompress: `xz -d pimeleon-*.img.xz`
3. Write to SD card: `sudo dd if=pimeleon-*.img of=/dev/sdX bs=4M status=progress`
FOOTER

echo ""
echo "=== Release Notes ==="
cat "$NOTES_FILE"
echo "====================="

# --- Collect artifact files ---
FILES=""
cd output
for file in pimeleon-*.img.xz pimeleon-*.img.metadata.json; do
  [ -f "$file" ] || continue
  FILES="${FILES} ${file}"
  echo "  Asset: $file ($(ls -lh "$file" | awk '{print $5}'))"
done
cd ..

if [ -z "$FILES" ]; then
  echo "Error: No artifacts found in output/"
  exit 1
fi

# --- Create or update GitHub Release ---
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "Release ${TAG} already exists. Uploading assets to existing release..."
  cd output
  # shellcheck disable=SC2086
  gh release upload "$TAG" $FILES --repo "$GITHUB_REPO" --clobber
  cd ..
else
  echo "Creating new release ${TAG}..."
  cd output
  # shellcheck disable=SC2086
  gh release create "$TAG" $FILES \
    --repo "$GITHUB_REPO" \
    --title "$RELEASE_NAME" \
    --notes-file "$NOTES_FILE"
  cd ..
fi

rm -rf "$TMPDIR"

echo "GitHub Release ${TAG} created successfully."
echo "URL: https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
