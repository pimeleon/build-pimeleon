#!/usr/bin/env bats
# Unit tests for shared/scripts/get-next-version.sh

load "helpers/fixtures"

SCRIPT="${BATS_TEST_DIRNAME}/../../shared/scripts/get-next-version.sh"
PLATFORM="rpi3-bookworm"
BUILD_FILE="apps/${PLATFORM}/vars/main.yml"

setup() {
    create_temp_git_repo
}

teardown() {
    cleanup_temp_git_repo
}

# ---------------------------------------------------------------------------
# Helper: run the versioning script from TEST_TMPDIR
# ---------------------------------------------------------------------------
run_version_script() {
    run sh "$SCRIPT" "$PLATFORM"
}

# ---------------------------------------------------------------------------
# No-bump (service) commit types
# ---------------------------------------------------------------------------

@test "docs: commit touching build path does not bump version" {
    cd "$TEST_TMPDIR"
    echo "# docs change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "docs: update docs"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]
}

@test "chore: commit touching build path does not bump version" {
    cd "$TEST_TMPDIR"
    echo "# chore change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "chore: cleanup"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]
}

@test "ci: commit touching build path does not bump version" {
    cd "$TEST_TMPDIR"
    echo "# ci change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "ci: update pipeline"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]
}

@test "style: commit touching build path does not bump version" {
    cd "$TEST_TMPDIR"
    echo "# style change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "style: fix indentation"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]
}

@test "test: commit touching build path does not bump version" {
    cd "$TEST_TMPDIR"
    echo "# test change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "test: add unit test"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]
}

# ---------------------------------------------------------------------------
# Patch bumps
# ---------------------------------------------------------------------------

@test "fix: commit touching build path bumps patch (0.1.0 -> 0.1.1)" {
    cd "$TEST_TMPDIR"
    echo "# fix change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "fix(build): correct wrong default"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.1" ]
}

@test "build: commit touching build path bumps patch" {
    cd "$TEST_TMPDIR"
    echo "# build change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "build: update dependency versions"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.1" ]
}

@test "perf: commit touching build path bumps patch" {
    cd "$TEST_TMPDIR"
    echo "# perf change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "perf: reduce image size"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.1" ]
}

@test "untagged commit touching build path bumps patch" {
    cd "$TEST_TMPDIR"
    echo "# untagged change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "adjust some defaults"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.1" ]
}

# ---------------------------------------------------------------------------
# Minor bumps
# ---------------------------------------------------------------------------

@test "feat: commit touching build path bumps minor (0.1.0 -> 0.2.0)" {
    cd "$TEST_TMPDIR"
    echo "# feat change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "feat: add dnscrypt-proxy support"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.2.0" ]
}

@test "refactor: commit touching build path bumps minor" {
    cd "$TEST_TMPDIR"
    echo "# refactor change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "refactor: restructure ansible roles"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.2.0" ]
}

@test "feat with scope touching build path bumps minor" {
    cd "$TEST_TMPDIR"
    echo "# scoped feat" >> "$BUILD_FILE"
    git add .
    git commit -q -m "feat(network): add vlan support"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.2.0" ]
}

# ---------------------------------------------------------------------------
# Priority: minor beats patch
# ---------------------------------------------------------------------------

@test "feat: beats fix: — minor bump wins when both are present" {
    cd "$TEST_TMPDIR"
    # First add a fix: commit
    echo "# fix first" >> "$BUILD_FILE"
    git add .
    git commit -q -m "fix: minor correction"
    # Then add a feat: commit
    echo "# feat second" >> "$BUILD_FILE"
    git add .
    git commit -q -m "feat: new capability"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.2.0" ]
}

@test "refactor: beats fix: — minor bump wins when both are present" {
    cd "$TEST_TMPDIR"
    echo "# fix" >> "$BUILD_FILE"
    git add .
    git commit -q -m "fix: small fix"
    echo "# refactor" >> "$BUILD_FILE"
    git add .
    git commit -q -m "refactor: big restructure"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.2.0" ]
}

# ---------------------------------------------------------------------------
# Commits not touching build paths
# ---------------------------------------------------------------------------

@test "fix: commit not touching build paths does not bump version" {
    cd "$TEST_TMPDIR"
    git commit -q --allow-empty -m "fix: unrelated commit"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]
}

@test "feat: commit not touching build paths does not bump version" {
    cd "$TEST_TMPDIR"
    git commit -q --allow-empty -m "feat: ui change unrelated to build"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]
}

# ---------------------------------------------------------------------------
# Missing VERSION file fallback
# ---------------------------------------------------------------------------

@test "missing VERSION file falls back to 0.1.0 base and patch bump gives 0.1.1" {
    cd "$TEST_TMPDIR"
    # Remove the VERSION file and commit the removal
    git rm -q apps/rpi3-bookworm/VERSION
    git commit -q -m "chore: remove VERSION file"
    # Add a fix: commit touching a build path
    echo "# fix after removal" >> "$BUILD_FILE"
    git add .
    git commit -q -m "fix: patch bump from fallback base"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.1" ]
}

@test "missing VERSION file with no-bump commit returns 0.1.0" {
    cd "$TEST_TMPDIR"
    git rm -q apps/rpi3-bookworm/VERSION
    git commit -q -m "chore: remove VERSION file"
    echo "# docs only" >> "$BUILD_FILE"
    git add .
    git commit -q -m "docs: update after removal"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]
}

# ---------------------------------------------------------------------------
# shared/ansible path is also a build path
# ---------------------------------------------------------------------------

@test "fix: commit touching shared/ansible/ bumps patch" {
    cd "$TEST_TMPDIR"
    mkdir -p shared/ansible/playbooks
    echo "# ansible task" > shared/ansible/playbooks/site.yml
    git add .
    git commit -q -m "fix(ansible): correct task order"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.1" ]
}

@test "feat: commit touching shared/scripts/ bumps minor" {
    cd "$TEST_TMPDIR"
    mkdir -p shared/scripts
    echo "#!/bin/sh" > shared/scripts/helper.sh
    git add .
    git commit -q -m "feat: add helper script"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.2.0" ]
}
