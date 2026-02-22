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
