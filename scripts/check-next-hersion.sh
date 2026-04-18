#!/bin/sh
# Simulate the test environment
TEST_TMPDIR=$(mktemp -d)
cd "$TEST_TMPDIR" || exit 1
git init -q
mkdir -p apps/rpi3-bookworm/vars
echo "# placeholder" > apps/rpi3-bookworm/vars/main.yml
git add .
git commit -q -m "chore: initial repo setup"
git tag "rpi3-bookworm-v0.1.0"
echo "# docs change" >> apps/rpi3-bookworm/vars/main.yml
git add .
git commit -q -m "docs: update docs"
./shared/scripts/get-next-version.sh rpi3-bookworm
rm -rf "$TEST_TMPDIR"
