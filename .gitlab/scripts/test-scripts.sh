#!/bin/sh
set -eu

apt-get update -qq && apt-get install -y -qq --no-install-recommends bats git
pip install --quiet pyyaml

mkdir -p test-results
bash scripts/run-script-tests.sh
