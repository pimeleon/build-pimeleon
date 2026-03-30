#!/usr/bin/env bash
# Shared bats test fixtures for build script tests

# Create a temporary git repository with initial structure for versioning tests.
# Sets TEST_TMPDIR to the path of the created repo.
create_temp_git_repo() {
    TEST_TMPDIR="$(mktemp -d)"

    # Set up git identity for the temp repo (avoid global config dependency)
    export GIT_AUTHOR_NAME="Test User"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test User"
    export GIT_COMMITTER_EMAIL="test@example.com"

    (
        cd "$TEST_TMPDIR" || return 1
        git init -q
        git config user.email "test@example.com"
        git config user.name "Test User"

        # Create required directory structure
        mkdir -p apps/rpi3-bookworm/vars

        # Seed VERSION file
        echo "0.1.0" > apps/rpi3-bookworm/VERSION

        # Seed a dummy build path file so subsequent commits have something to touch
        echo "# placeholder" > apps/rpi3-bookworm/vars/main.yml

        git add .
        git commit -q -m "chore: initial repo setup"
    )
}

# Remove the temporary git repository created by create_temp_git_repo.
cleanup_temp_git_repo() {
    if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}
