# CI/CD Infrastructure

The Pimeleon project uses a dual-platform CI/CD strategy, leveraging both GitLab CI/CD and
GitHub Actions to ensure robust builds, automated testing, and reliable artifact delivery.

## Strategy Overview

- **GitLab CI/CD**: Primary pipeline for complex, modular builds and production releases.
  Utilizes local runners with privileged access for image creation.
- **GitHub Actions**: Secondary pipeline for broad community visibility, public repository
  mirroring, and automated security scanning (Trivy).

## GitLab CI/CD Pipeline

The GitLab pipeline is defined in `.gitlab-ci.yml` and is modularized into several components
located in `.gitlab/ci/`.

### Pipeline Stages

1. **scan**: Security scanning of the codebase.
2. **lint**: YAML, Ansible, and Shell script validation.
3. **build**:
    - Build builder and tester Docker containers.
    - Generate bootable Pimeleon images for supported platforms (RPi 3B+, RPi 4B).
4. **test**: Run smoke and integration tests using QEMU system emulation.
5. **publish**: Push images to the container registry.
6. **release**: Create official releases and generate metadata.
7. **docs**: Trigger external documentation site builds.

### Caching Strategy

To optimize build performance, GitLab CI/CD uses a sophisticated caching mechanism for
base system root filesystems:

- **rpi3-bookworm**: Cached as `pimeleon-rpi3-bookworm-base.tar.gz`.
- **rpi4-bookworm**: Cached as `pimeleon-rpi4-bookworm-base.tar.gz`.

A dedicated `warm-cache` stage in `.pre` ensures that build jobs start with a populated
cache when possible, reducing build times by up to 10 minutes.

### Branch-Local Overrides

To allow for platform-specific divergence while maintaining a clean monorepo, the CI/CD pipeline
prioritizes branch-local configuration files over shared ones. If these files exist in the branch
root, they will be used instead of the defaults in `shared/`:

- **Dockerfiles**: `./containers/{builder,tester}/Dockerfile` (falls back to `shared/containers/`)
- **Ansible Playbooks**: `./ansible/playbooks/main.yml` (trigger for using the root `./ansible` directory)
- **Service Configs**: `./configs/network/` (trigger for using the root `./configs` directory)
- **Build Scripts**: `./scripts/build.sh` (trigger for using the root `./scripts` directory)

This mechanism ensures that `develop` and other standard branches use the verified `shared/` logic,
while release branches (e.g., `release/rpi4-bookworm`) can customize their build process as needed.

### Environment Handling

All builds in the Pimeleon CI/CD pipeline are executed in **Production Mode**. This ensures that
all images, regardless of the branch, follow strict security hardening and service optimization
standards.

### Custom Builds

For specialized requirements or testing different platform/OS combinations without modifying
the pipeline code, a `build:custom` job is available.

- **Trigger**: Manual via the GitLab Web UI ("Run pipeline") or the API.
- **Variables**:
  - `TARGET_PLATFORM`: Any valid combination (e.g., `rpi3-bullseye`).
  - `PIMELEON_IMAGE_SIZE`: Customize the output image size.
  - `PIMELEON_PROFILE`: Defaults to `production`.
  - `DEBUG`: Set to `1` for verbose build logs.

## GitHub Actions

The GitHub pipeline is defined in `.github/workflows/` and provides a streamlined
path for community contributions.

### Main Workflow: Build Pimeleon Image

- **Trigger**: Pushes to `main`/`develop`, Pull Requests, and a weekly schedule (Sundays at 2 AM).
- **Jobs**:
  - `lint`: Code quality checks.
  - `build`: Builds the builder container and the RPi 3B+ image.
  - `test`: Executes smoke tests.
  - `security-scan`: Runs Trivy for vulnerability detection.
  - `release`: Automatically creates GitHub Releases for pushes to `main`.

## Versioning Scheme

Version numbers follow **SemVer** (`MAJOR.MINOR.PATCH`) and are computed automatically by
`shared/scripts/get-next-version.sh` from conventional commit history since the last release.

### Source of Truth (priority order)

| Context | Primary source | Fallback |
|---------|---------------|---------|
| GitLab CI | GitLab package registry | local git tags → `0.3.0` |
| GitHub Actions / local | GitHub Releases API | local git tags → `0.3.0` |

GitHub Releases auth is provided via the `GITHUB_REGISTRY_PUSH_TOKEN` CI variable.

### Bump Rules

Commits are analysed on these paths since the last release tag:
`apps/{platform}/`, `containers/`, `shared/containers/`, `shared/ansible/`,
`shared/configs/`, `shared/scripts/`, `docker-compose.yml`, `requirements.txt`

| Commit prefix | Bump |
|---------------|------|
| `feat!:` / `fix!:` | **major** (breaking change) |
| `feat:` / `refactor:` | **minor** |
| `fix:` / `build:` / `perf:` / untagged | **patch** |
| `docs:` / `chore:` / `ci:` / `style:` / `test:` | none (service commits) |

### Output Naming

| Build type | Filename pattern |
|------------|-----------------|
| Release | `pimeleon-{device}-{version}-{os}.img` |
| Development | `pimeleon-{device}-{version}-{os}-{short-hash}.img` |
| CI package tag | `{platform}-v{version}` (e.g. `rpi3-bookworm-v0.3.1`) |

### Local Build Version Resolution

The `Makefile` resolves the version on the **host** before starting the builder container
(mirroring the GitHub Actions approach in `.github/scripts/resolve-meta.sh`):

```bash
GITHUB_REGISTRY_PUSH_TOKEN=<token> make build TARGET_PLATFORM=rpi3-bookworm
```

The resolved version is passed into the container as `PIMELEON_VERSION`. If resolution
fails (no token, no network), the container falls back to its own git-tag/default detection.

## Build Artifacts

Both pipelines produce the following artifacts:

| Artifact | Purpose | Retention |
|----------|---------|-----------|
| `pimeleon-*.img` | Raw bootable image | 1 week (CI) |
| `pimeleon-*.img.xz` | Compressed image for distribution | 1 week (CI) |
| `build-*.log` | Detailed build execution log | 1 week (CI) |
| `pi-initial-password.txt` | Generated password for the 'pi' user | 1 week (CI) |

## Triggering Documentation

Documentation is managed through a trigger mechanism:

- **Preview**: Triggered on pushes to the `develop` branch.
- **Production**: Triggered on stable release tags (`v*`).

This triggers the `pirouter/pimeleon-site` project to rebuild and publish the latest
documentation to [pimeleon.org](https://pimeleon.org).
