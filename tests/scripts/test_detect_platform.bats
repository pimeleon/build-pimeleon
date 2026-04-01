#!/usr/bin/env bats
# Unit tests for .gitlab/scripts/detect-platform.sh

PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
DETECT_PLATFORM="${PROJECT_ROOT}/.gitlab/scripts/detect-platform.sh"

setup() {
    TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
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
    [ "$(cat "${TEST_TMPDIR}/platform.env")" = "$(printf "TARGET_PLATFORM=rpi4-bookworm\nPIMELEON_PROFILE=production")" ]
}

@test "merge request to a release branch uses the release platform and production profile" {
    run_detect_platform CI_PIPELINE_SOURCE=merge_request_event CI_MERGE_REQUEST_TARGET_BRANCH_NAME=release/rpi5-bookworm
    [ "$status" -eq 0 ]
    [ "$(cat "${TEST_TMPDIR}/platform.env")" = "$(printf "TARGET_PLATFORM=rpi5-bookworm\nPIMELEON_PROFILE=production")" ]
}

@test "manual web pipeline keeps the selected platform and ignores profile overrides" {
    run_detect_platform CI_PIPELINE_SOURCE=web TARGET_PLATFORM=rpi4-bookworm PIMELEON_PROFILE=development
    [ "$status" -eq 0 ]
    [ "$(cat "${TEST_TMPDIR}/platform.env")" = "$(printf "TARGET_PLATFORM=rpi4-bookworm\nPIMELEON_PROFILE=production")" ]
}

@test "non-release branch push falls back to the default platform and production profile" {
    run_detect_platform CI_COMMIT_BRANCH=develop
    [ "$status" -eq 0 ]
    [ "$(cat "${TEST_TMPDIR}/platform.env")" = "$(printf "TARGET_PLATFORM=rpi3-bookworm\nPIMELEON_PROFILE=production")" ]
}
