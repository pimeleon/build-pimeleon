#!/bin/sh
set -eu

pip install --quiet yamllint
yamllint -c .yamllint .
