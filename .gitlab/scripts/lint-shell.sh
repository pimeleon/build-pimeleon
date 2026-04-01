#!/bin/sh
set -eu

apt-get update -qq && apt-get install -y -qq --no-install-recommends shellcheck jq
pip install --quiet semgrep bashate
bash scripts/quality-benchmark.sh
