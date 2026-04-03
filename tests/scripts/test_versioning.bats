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
# Minor bumps (no patch commits — patch segment resets to 0)
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
# Minor + patch: minor wins, patch segment set to 1
# ---------------------------------------------------------------------------

@test "feat: + fix: — minor bump with patch indicator (0.1.0 -> 0.2.1)" {
    cd "$TEST_TMPDIR"
    echo "# fix first" >> "$BUILD_FILE"
    git add .
    git commit -q -m "fix: minor correction"
    echo "# feat second" >> "$BUILD_FILE"
    git add .
    git commit -q -m "feat: new capability"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.2.1" ]
}

@test "refactor: + fix: — minor bump with patch indicator (0.1.0 -> 0.2.1)" {
    cd "$TEST_TMPDIR"
    echo "# fix" >> "$BUILD_FILE"
    git add .
    git commit -q -m "fix: small fix"
    echo "# refactor" >> "$BUILD_FILE"
    git add .
    git commit -q -m "refactor: big restructure"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.2.1" ]
}

# ---------------------------------------------------------------------------
# Major bumps (breaking changes: feat!: / fix!:)
# ---------------------------------------------------------------------------

@test "feat!: commit touching build path bumps major (0.1.0 -> 1.0.0)" {
    cd "$TEST_TMPDIR"
    echo "# breaking feat" >> "$BUILD_FILE"
    git add .
    git commit -q -m "feat!: drop legacy build system"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "1.0.0" ]
}

@test "fix!: commit touching build path bumps major (0.1.0 -> 1.0.0)" {
    cd "$TEST_TMPDIR"
    echo "# breaking fix" >> "$BUILD_FILE"
    git add .
    git commit -q -m "fix!: remove deprecated config option"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "1.0.0" ]
}

@test "feat!: + feat: — major with minor indicator (0.1.0 -> 1.1.0)" {
    cd "$TEST_TMPDIR"
    echo "# breaking" >> "$BUILD_FILE"
    git add .
    git commit -q -m "feat!: breaking change"
    echo "# non-breaking feature" >> "$BUILD_FILE"
    git add .
    git commit -q -m "feat: new feature"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "1.1.0" ]
}

@test "feat!: + fix: — major with patch indicator (0.1.0 -> 1.0.1)" {
    cd "$TEST_TMPDIR"
    echo "# breaking" >> "$BUILD_FILE"
    git add .
    git commit -q -m "feat!: breaking change"
    echo "# patch" >> "$BUILD_FILE"
    git add .
    git commit -q -m "fix: small correction"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "1.0.1" ]
}

@test "feat!: + feat: + fix: — major with minor and patch indicators (0.1.0 -> 1.1.1)" {
    cd "$TEST_TMPDIR"
    echo "# breaking" >> "$BUILD_FILE"
    git add .
    git commit -q -m "feat!: breaking change"
    echo "# feature" >> "$BUILD_FILE"
    git add .
    git commit -q -m "feat: new feature"
    echo "# fix" >> "$BUILD_FILE"
    git add .
    git commit -q -m "fix: small correction"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "1.1.1" ]
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
# No local tag: falls back to hardcoded default (0.3.0)
# ---------------------------------------------------------------------------

@test "no release tag falls back to default base 0.3.0 and patch bump gives 0.3.1" {
    cd "$TEST_TMPDIR"
    # Remove the baseline tag to simulate first-ever run with no prior releases
    git tag -d "rpi3-bookworm-v0.1.0"
    echo "# fix change" >> "$BUILD_FILE"
    git add .
    git commit -q -m "fix: patch from default base"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.3.1" ]
}

@test "no release tag falls back to default base 0.3.0 and service commit returns 0.3.0" {
    cd "$TEST_TMPDIR"
    git tag -d "rpi3-bookworm-v0.1.0"
    echo "# docs only" >> "$BUILD_FILE"
    git add .
    git commit -q -m "docs: update readme"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.3.0" ]
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

@test "build: commit touching shared/containers/ bumps patch" {
    cd "$TEST_TMPDIR"
    mkdir -p shared/containers/builder
    echo "FROM alpine:latest" > shared/containers/builder/Dockerfile
    git add .
    git commit -q -m "build: refresh builder image"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.1" ]
}

@test "feat: commit touching containers/ bumps minor" {
    cd "$TEST_TMPDIR"
    mkdir -p containers/tester
    echo "FROM alpine:latest" > containers/tester/Dockerfile
    git add .
    git commit -q -m "feat: add tester tooling"
    run_version_script
    [ "$status" -eq 0 ]
    [ "$output" = "0.2.0" ]
}
