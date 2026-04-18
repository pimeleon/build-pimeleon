#!/bin/sh
set -x

curl -skf -H "JOB-TOKEN: ${GITLAB_FETCH_TOKEN}" -H "PRIVATE-TOKEN: ${GITLAB_FETCH_TOKEN}" "${GITLAB_API_V4_URL}/projects/${GITLAB_PROJECT_ID}/packages?package_name=pimeleon&order_by=created_at&sort=desc&per_page=50"
