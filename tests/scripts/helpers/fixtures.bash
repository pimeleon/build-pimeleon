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

    # Point to a nonexistent repo so the GitHub Releases API call fails fast
    # and falls back to local git tags. This keeps tests offline and deterministic.
    export GITHUB_REPO="pimeleon-test/nonexistent-repo-for-tests"
    export GITHUB_REGISTRY_PUSH_TOKEN=""
    export GITHUB_TOKEN=""

    (
        cd "$TEST_TMPDIR" || return 1
        git init -q
        git config user.email "test@example.com"
        git config user.name "Test User"

        # Create required directory structure
        mkdir -p apps/rpi3-bookworm/vars

        # Seed a dummy build path file so subsequent commits have something to touch
        echo "# placeholder" > apps/rpi3-bookworm/vars/main.yml

        git add .
        git commit -q -m "chore: initial repo setup"

        # Tag the initial commit as the baseline release (replaces VERSION file)
        git tag "rpi3-bookworm-v0.1.0"
    )
}

# Remove the temporary git repository created by create_temp_git_repo.
cleanup_temp_git_repo() {
    if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}
