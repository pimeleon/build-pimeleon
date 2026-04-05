#!/usr/bin/env bats
# Unit tests for .gitlab/scripts/detect-platform.sh

load "helpers/fixtures"

PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
DETECT_PLATFORM="${PROJECT_ROOT}/.gitlab/scripts/detect-platform.sh"

setup() {
    create_temp_git_repo
    # Add baseline tags for every platform used in these tests so
    # get-next-version.sh can find a baseline ref for each platform.
    (
        cd "$TEST_TMPDIR"
        git tag "rpi3-bookworm-v0.3.0"
        git tag "rpi4-bookworm-v0.3.0"
        git tag "rpi5-bookworm-v0.3.0"
    )
}

teardown() {
    cleanup_temp_git_repo
}

run_detect_platform() {
    run bash -c '
        script="$1"
        workdir="$2"
        shift 2
        cd "$workdir"
        env -i PATH="$PATH" "$@" "$script"
    ' bash "$DETECT_PLATFORM" "$TEST_TMPDIR" "$@"
}

@test "tag pipeline extracts the platform and uses production profile" {
    run_detect_platform CI_COMMIT_TAG=rpi4-bookworm-v1.2.3
    [ "$status" -eq 0 ]
    [ "$(cat "${TEST_TMPDIR}/build.env")" = "$(printf "TARGET_PLATFORM=rpi4-bookworm\nPIMELEON_PROFILE=production\nPIMELEON_VERSION=1.2.3")" ]
}

@test "merge request to a release branch uses the release platform and production profile" {
    run_detect_platform CI_PIPELINE_SOURCE=merge_request_event CI_MERGE_REQUEST_TARGET_BRANCH_NAME=release/rpi5-bookworm
    [ "$status" -eq 0 ]
    [ "$(cat "${TEST_TMPDIR}/build.env")" = "$(printf "TARGET_PLATFORM=rpi5-bookworm\nPIMELEON_PROFILE=production\nPIMELEON_VERSION=0.3.0")" ]
}

@test "manual web pipeline keeps the selected platform and ignores profile overrides" {
    run_detect_platform CI_PIPELINE_SOURCE=web TARGET_PLATFORM=rpi4-bookworm PIMELEON_PROFILE=development
    [ "$status" -eq 0 ]
    [ "$(cat "${TEST_TMPDIR}/build.env")" = "$(printf "TARGET_PLATFORM=rpi4-bookworm\nPIMELEON_PROFILE=production\nPIMELEON_VERSION=0.3.0")" ]
}

@test "non-release branch push falls back to the default platform and production profile" {
    run_detect_platform CI_COMMIT_BRANCH=develop
    [ "$status" -eq 0 ]
    [ "$(cat "${TEST_TMPDIR}/build.env")" = "$(printf "TARGET_PLATFORM=rpi3-bookworm\nPIMELEON_PROFILE=production\nPIMELEON_VERSION=0.3.0")" ]
}
