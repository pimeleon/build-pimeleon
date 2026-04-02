#!/bin/sh
set -eu

apt-get -qy update && apt-get -q install -y --no-install-recommends git
pip install "mkdocs>=1.5.3,<2.0" mkdocs-material mkdocs-git-revision-date-localized-plugin mkdocs-minify-plugin
mkdocs build -d public
