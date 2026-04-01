#!/bin/sh
set -eu

pip install --quiet ansible-lint
ansible-galaxy collection install -r shared/ansible/requirements.yml
cd shared/ansible
ansible-lint playbooks/*.yml
