#!/bin/sh
set -eu

# Create and push an annotated git tag from within a CI job.
#
# Usage: create-tag.sh <tag-name> <tag-message>
#
# Inputs (env):
#   CI_SERVER_HOST, CI_PROJECT_PATH, CI_COMMIT_SHA
#   CI_JOB_TOKEN  — provided automatically by GitLab for every job

TAG_NAME="${1:-}"
TAG_MESSAGE="${2:-Automated tag ${TAG_NAME}}"

[ -n "$TAG_NAME" ]             || { echo "[ERROR] tag name is required" >&2; exit 1; }
[ -n "${CI_JOB_TOKEN:-}" ]     || { echo "[ERROR] CI_JOB_TOKEN is not set" >&2; exit 1; }
[ -n "${CI_SERVER_HOST:-}" ]   || { echo "[ERROR] CI_SERVER_HOST is not set" >&2; exit 1; }
[ -n "${CI_PROJECT_PATH:-}" ]  || { echo "[ERROR] CI_PROJECT_PATH is not set" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "[ERROR] git is required" >&2; exit 1; }

git config user.email "ci@pimeleon.build"
git config user.name "Pimeleon CI"

git remote set-url origin \
    "https://gitlab-ci-token:${CI_JOB_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git"

# Fetch existing tags to detect duplicates before creating
git fetch --tags --quiet 2>/dev/null || true

if git tag -l "${TAG_NAME}" | grep -q .; then
    echo "[INFO] Tag ${TAG_NAME} already exists — skipping."
    exit 0
fi

git tag -a "${TAG_NAME}" -m "${TAG_MESSAGE}" "${CI_COMMIT_SHA}"
git push origin "${TAG_NAME}"
echo "[INFO] Created annotated tag: ${TAG_NAME}"
