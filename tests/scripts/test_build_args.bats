#!/usr/bin/env bats
# Unit tests for scripts/build-local.sh argument parsing
#
# We only test the early-exit paths (--help, unknown option) because main()
# calls check_root which exits if not root.  Env-var export tests for
# --profile / --model / --version / --with-cache are exercised via a
# wrapper that intercepts main() so it never actually runs.

PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
BUILD_LOCAL="${PROJECT_ROOT}/scripts/build-local.sh"

# ---------------------------------------------------------------------------
# --help
# ---------------------------------------------------------------------------

@test "--help exits with status 0" {
    run bash "$BUILD_LOCAL" --help
    [ "$status" -eq 0 ]
}

@test "-h exits with status 0" {
    run bash "$BUILD_LOCAL" -h
    [ "$status" -eq 0 ]
}

@test "--help output contains Usage:" {
    run bash "$BUILD_LOCAL" --help
    [[ "$output" == *"Usage:"* ]]
}

@test "--help output lists --profile option" {
    run bash "$BUILD_LOCAL" --help
    [[ "$output" == *"--profile"* ]]
}

@test "--help output lists --model option" {
    run bash "$BUILD_LOCAL" --help
    [[ "$output" == *"--model"* ]]
}

@test "--help output lists --version option" {
    run bash "$BUILD_LOCAL" --help
    [[ "$output" == *"--version"* ]]
}

@test "--help output lists --with-cache option" {
    run bash "$BUILD_LOCAL" --help
    [[ "$output" == *"--with-cache"* ]]
}

@test "--help output mentions available profiles" {
    run bash "$BUILD_LOCAL" --help
    [[ "$output" == *"development"* ]] || [[ "$output" == *"production"* ]]
}

# ---------------------------------------------------------------------------
# Unknown / invalid option
# ---------------------------------------------------------------------------

@test "unknown option exits with status 1" {
    run bash "$BUILD_LOCAL" --bogus-flag
    [ "$status" -eq 1 ]
}

@test "unknown option output mentions 'Unknown option'" {
    run bash "$BUILD_LOCAL" --bogus-flag
    [[ "$output" == *"Unknown option"* ]]
}

@test "unknown option output includes the show_help text" {
    run bash "$BUILD_LOCAL" --totally-unknown
    # show_help is called after log_error for unknown options
    [[ "$output" == *"Usage:"* ]]
}

@test "single dash unknown option exits with status 1" {
    run bash "$BUILD_LOCAL" -z
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Env-var export validation via intercepted main()
# We override main() to a no-op so the script parses args and exports vars
# without actually running the build.
# ---------------------------------------------------------------------------

_run_with_noop_main() {
    # Source build-local.sh up to (but not including) the final `main "$@"` line.
    # This runs the arg-parsing while loop and exports variables without
    # triggering the actual build or check_root.
    local args=("$@")
    local stop_line
    stop_line=$(grep -n '^main "\$@"' "$BUILD_LOCAL" | tail -1 | cut -d: -f1)
    run bash -c '
        set -- "$@"
        export PROJECT_ROOT="'"${PROJECT_ROOT}"'"
        source <(head -n '"$((stop_line - 1))"' "'"$BUILD_LOCAL"'")
        echo "PROFILE=${PIMELEON_PROFILE}"
        echo "MODEL=${PIMELEON_RPI_MODEL}"
        echo "VERSION=${RASPBIAN_VERSION}"
        echo "PROXY=${APT_PROXY}"
    ' bash "${args[@]}"
}

@test "--profile sets PIMELEON_PROFILE" {
    _run_with_noop_main --profile production
    [ "$status" -eq 0 ]
    [[ "$output" == *"PROFILE=production"* ]]
}

@test "-p sets PIMELEON_PROFILE (short flag)" {
    _run_with_noop_main -p production
    [ "$status" -eq 0 ]
    [[ "$output" == *"PROFILE=production"* ]]
}

@test "--model sets PIMELEON_RPI_MODEL" {
    _run_with_noop_main --model 4B
    [ "$status" -eq 0 ]
    [[ "$output" == *"MODEL=4B"* ]]
}

@test "-m sets PIMELEON_RPI_MODEL (short flag)" {
    _run_with_noop_main -m 4B
    [ "$status" -eq 0 ]
    [[ "$output" == *"MODEL=4B"* ]]
}

@test "--version sets RASPBIAN_VERSION" {
    _run_with_noop_main --version bookworm
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERSION=bookworm"* ]]
}

@test "-v sets RASPBIAN_VERSION (short flag)" {
    _run_with_noop_main -v bookworm
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERSION=bookworm"* ]]
}

@test "--with-cache sets APT_PROXY with :3142 suffix" {
    _run_with_noop_main --with-cache 192.168.1.5
    [ "$status" -eq 0 ]
    [[ "$output" == *"PROXY=192.168.1.5:3142"* ]]
}

@test "multiple flags are all applied" {
    _run_with_noop_main --profile production --model 4B --version bookworm
    [ "$status" -eq 0 ]
    [[ "$output" == *"PROFILE=production"* ]]
    [[ "$output" == *"MODEL=4B"* ]]
    [[ "$output" == *"VERSION=bookworm"* ]]
}
