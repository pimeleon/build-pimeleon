# Containers

Docker container architecture for the Pimeleon build system.

## Container Images

All images are stored in the GitLab Container Registry under `${CI_REGISTRY_IMAGE}`.

| Image | Tag | Purpose |
|-------|-----|---------|
| `builder` | `latest` | ARM chroot build container — runs all four build stages |
| `tester` | `latest` | Test runner — executes smoke and integration test suites |
| `adblock2privoxy` | `latest` | Pre-built Haskell binary; built once and reused across pipelines |

### Tag Convention

All images use the `:latest` tag. Per-commit or per-branch tags (e.g., `${CI_COMMIT_REF_SLUG}`) are **not** used.

### When Images Are Rebuilt

The `build:containers` CI job (`.gitlab/ci/build.yml`) rebuilds and pushes `builder:latest` and
`tester:latest` only when the following paths change:

- `shared/containers/**`
- `containers/**`
- `apps/**`
- `docker-compose.yml`

The `adblock2privoxy:latest` image is rebuilt only if it is absent from the registry entirely.

### Dependency in Test Jobs

`test:smoke` and `test:integration` declare `build:containers` as an `optional: true` need.
When container files have not changed, `build:containers` is skipped and the test jobs pull the
existing `tester:latest` from the registry directly.

## Builder Container

- **Dockerfile**: `shared/containers/builder/Dockerfile` (branch-local override: `containers/builder/Dockerfile`)
- **Base**: Debian 12 (Bookworm)
- **Capabilities**: `SYS_ADMIN`, `MKNOD`; requires privileged mode and `/dev` access for loop devices and chroot
- **Entry point**: `/scripts/build.sh`

### Build Stage Volumes (Docker Compose)

| Mount | Purpose |
|-------|---------|
| `./shared/scripts:/scripts` | Build stage scripts |
| `./shared/configs:/configs` | Network and service configs |
| `./shared/ansible:/ansible` | Ansible playbooks |
| `./output:/output` | Build artifacts |
| `./cache:/cache` | APT, pip, debootstrap caches |

## Tester Container

- **Dockerfile**: `shared/containers/tester/Dockerfile` (branch-local override: `containers/tester/Dockerfile`)
- **Base**: Ubuntu 22.04
- **Capabilities**: `NET_ADMIN`, `SYS_ADMIN`, `SYS_NICE`; KVM and TUN device access
- **Test suites**: `smoke` (quick sanity) and `integration` (full end-to-end via QEMU)

## Dev Container

- **Dockerfile**: `shared/containers/builder/Dockerfile` (target: `development`)
- Interactive shell environment with all build tools installed
- Start with `make dev`, enter with `make shell`
