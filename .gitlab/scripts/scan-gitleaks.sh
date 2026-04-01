#!/bin/sh
set -eu

echo "Running secret detection with gitleaks..."
gitleaks git . --verbose --redact --config .gitleaks.toml
echo "Secret detection completed"
