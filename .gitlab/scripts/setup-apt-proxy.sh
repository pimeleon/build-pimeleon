#!/bin/sh
# Configure APT retries and optional proxy for CI jobs.
# Safe to call when APT_PROXY is unset — proxy block is skipped.
echo 'Acquire::Retries "3";' > /etc/apt/apt.conf.d/80-retries
echo 'Acquire::http::Pipeline-Depth "0";' >> /etc/apt/apt.conf.d/80-retries
echo 'Acquire::http::Timeout "60";' >> /etc/apt/apt.conf.d/80-retries
if [ -n "${APT_PROXY:-}" ]; then
  echo "Acquire::http::Proxy \"http://${APT_PROXY}\";" > /etc/apt/apt.conf.d/01proxy
  echo 'Acquire::https::Proxy "DIRECT";' >> /etc/apt/apt.conf.d/01proxy
fi
