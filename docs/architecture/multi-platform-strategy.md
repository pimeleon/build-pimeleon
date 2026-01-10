# Multi-Platform Repository Organization Strategy

## Overview

This document describes the strategic approach for evolving `pimeleon-build` from a Raspberry Pi-specific build system into a multi-platform ARM router build system while maintaining backward compatibility and the "Pimeleon" brand identity.

**Strategy**: Enhanced Monorepo with Platform Profiles
**Timeline**: 3-6 months (5 phases)
**Complexity**: Moderate (YAML-based profiles with conditional logic)
**Community Model**: Hybrid (core platforms + community contributions)
**Branding**: Keep "Pimeleon" primary, add platforms quietly

## Strategic Goals

### Technical Goals
- Support multiple ARM SBCs (Raspberry Pi, Orange Pi, Rock Pi, etc.)
- Maintain single repository for all platforms
- Achieve 100% backward compatibility with existing Pi builds
- Build time <15 minutes with caching across all platforms
- Enable community contributions with minimal friction

### Community Goals
- Core team maintains primary platforms (Raspberry Pi, Orange Pi)
- Community members can become platform maintainers
- Accept contributions for new platforms via standard PR process
- Platform-specific support handled by platform maintainers

### Marketing Goals
- Maintain "Pimeleon" as primary brand identity
- Raspberry Pi remains the flagship, primary platform
- Multi-platform support as value-add, not main selling point
- Attract broader ARM SBC community without diluting Pi focus

## Repository Structure

```
pimeleon-build/
├── platforms/
│   ├── core/                          # Shared base implementations
│   │   ├── profiles/
│   │   │   └── debian-arm-base.yaml  # Common Debian ARM settings
│   │   ├── scripts/
│   │   │   └── common.sh             # Platform-agnostic utilities
│   │   └── docs/
│   │       └── adding-platforms.md   # Contributor guide
│   │
│   ├── raspberrypi/                   # Core team maintained
│   │   ├── profiles/
│   │   │   ├── 3b-plus.yaml
│   │   │   ├── 4b.yaml
│   │   │   └── zero-w.yaml
│   │   ├── hooks/                     # Platform-specific overrides
│   │   │   ├── pre-customize.sh
│   │   │   └── post-customize.sh
│   │   ├── tests/
│   │   │   └── test_pi_boot.py
│   │   └── README.md
│   │
│   ├── orangepi/                      # Core team maintained (proof-of-concept)
│   │   ├── profiles/
│   │   │   └── 5-plus.yaml
│   │   ├── hooks/
│   │   │   └── post-customize.sh
│   │   └── README.md
│   │
│   └── community/                     # Community-contributed platforms
│       ├── rockpi/
│       ├── nanopi/
│       └── README.md
│
├── containers/                        # Universal build containers (unchanged)
│   ├── builder/
│   ├── tester/
│   └── dev/
│
├── configs/                           # Shared configs (network, security)
│   ├── network/
│   ├── security/
│   └── services/
│
├── scripts/
│   ├── build.sh                       # Platform-agnostic orchestrator
│   ├── hardware-loader.sh             # NEW: YAML profile parser
│   ├── benchmark-build.sh
│   └── clean-docker.sh
│
├── docs/
│   ├── platforms/                     # NEW: Per-platform documentation
│   │   ├── index.md                  # Comparison table
│   │   ├── raspberrypi.md
│   │   ├── orangepi.md
│   │   └── contributing-platforms.md
│   ├── architecture/
│   │   ├── multi-platform-strategy.md    # This document
│   │   ├── hardware-profiles.md          # Profile schema reference
│   │   └── migration-roadmap.md          # Implementation plan
│   └── getting-started/
│       ├── quickstart-pi.md          # Pi remains primary
│       └── quickstart-orangepi.md
│
├── cache/                             # Per-platform caches
│   ├── raspberrypi-3b-plus-bullseye-armhf-base-v1.tar.gz
│   └── orangepi-5-plus-bookworm-arm64-base-v1.tar.gz
│
└── output/                            # Per-platform outputs
```

## Architecture Principles

### 1. Abstraction Through Profiles

**Problem**: Current build system hardcodes Raspberry Pi-specific values throughout build stages.

**Solution**: YAML-based hardware profiles that describe platform-specific configurations.

**Benefits**:
- Single source of truth for hardware specifications
- Easy to add new platforms (just create YAML file)
- Version-controlled platform configurations
- Self-documenting hardware requirements

See [Hardware Profiles](hardware-profiles.md) for detailed schema.

### 2. Platform Hooks System

**Problem**: Some platforms require unique build steps (e.g., U-Boot vs Pi firmware).

**Solution**: Optional pre/post hooks that platforms can provide.

**Implementation**:
```bash
# In build.sh
if [[ -f "platforms/${PLATFORM}/hooks/pre-customize.sh" ]]; then
    source "platforms/${PLATFORM}/hooks/pre-customize.sh"
fi
```

**Benefits**:
- Platforms control their own special logic
- Core build pipeline stays clean
- Opt-in complexity (Pi doesn't need hooks)

### 3. Backward Compatibility Layer

**Problem**: Existing users have scripts using `PIMELEON_RPI_MODEL`.

**Solution**: Alias old variables to new ones, maintain API compatibility.

**Implementation**:
```bash
# New variables
PIMELEON_PLATFORM="${PIMELEON_PLATFORM:-raspberrypi}"
PIMELEON_MODEL="${PIMELEON_MODEL:-3B+}"

# Backward compatibility
PIMELEON_RPI_MODEL="${PIMELEON_RPI_MODEL:-${PIMELEON_MODEL}}"

# Allow old variable to override new
if [[ -n "${PIMELEON_RPI_MODEL}" ]]; then
    PIMELEON_PLATFORM="raspberrypi"
    PIMELEON_MODEL="${PIMELEON_RPI_MODEL}"
fi
```

### 4. Conditional Logic in Build Stages

**Problem**: Device trees, bootloaders, packages differ per platform.

**Solution**: Replace hardcoded values with profile-driven conditionals.

**Before**:
```bash
# stage2-customize.sh (line 74)
sudo cp "${MOUNT_POINT}/boot/bcm2710-rpi-3-b-plus.dtb" "${BOOT_MOUNT}/"
```

**After**:
```bash
# Load from profile
if [[ -n "${BOOT_DEVICE_TREE}" ]]; then
    sudo cp "${MOUNT_POINT}/boot/${BOOT_DEVICE_TREE}" "${BOOT_MOUNT}/"
fi
```

### 5. Platform-Specific Caching

**Problem**: Different platforms need different base systems.

**Solution**: Platform-specific cache keys.

**Before**:
```bash
CACHE_KEY="pimeleon-rpi3-bullseye-base-v1.tar.gz"
```

**After**:
```bash
CACHE_KEY="${PLATFORM}-${MODEL}-${OS_VERSION}-${ARCH}-base-v${VERSION}.tar.gz"
# Example: orangepi-5-plus-bookworm-arm64-base-v1.tar.gz
```

## Community Governance Model

### Core Team Responsibilities

The core team (maintainers of this repository) will:

1. **Maintain Core Infrastructure**:
   - `platforms/core/` shared libraries
   - Build system (`containers/`, `scripts/`)
   - Documentation framework
   - CI/CD pipeline

2. **Own Primary Platforms**:
   - `platforms/raspberrypi/` - All Pi models (flagship platform)
   - `platforms/orangepi/` - Initially as proof-of-concept
   - Future expansion as resources allow

3. **Review Community Contributions**:
   - Review and merge community platform PRs
   - Ensure quality standards
   - Provide feedback and guidance

### Platform Maintainer Role

Community members can become **Platform Maintainers** for specific platforms:

**Requirements**:
- Successfully submit working platform profile + tests
- Commit to maintaining platform for 6+ months minimum
- Respond to platform-specific issues within 2 weeks
- Keep platform up-to-date with core system changes

**Benefits**:
- Listed as maintainer in `platforms/${PLATFORM}/README.md`
- Optional write access to platform-specific directory
- Recognition badge in community
- Direct input on platform-specific features

**Responsibilities**:
- Maintain platform profile accuracy
- Fix platform-specific build issues
- Update platform documentation
- Support users on platform-specific questions

### Contribution Process

See [Contributing Platforms](../contributing/adding-platforms.md) for detailed guide.

**High-level process**:
1. Fork repository
2. Create `platforms/${PLATFORM}/profiles/${MODEL}.yaml`
3. Add platform-specific tests
4. Build successfully in local environment
5. Submit PR with build logs and test results
6. Core team reviews within 1 week
7. Address feedback and iterate
8. Merge once all checks pass

## Marketing & Branding Strategy

### Brand Identity Preservation

**Primary Message**: "Pimeleon - Containerized build system for Raspberry Pi routers"

**Secondary Message**: "Also supports Orange Pi, Rock Pi, and custom ARM SBCs"

### Positioning

- **Raspberry Pi**: Flagship platform, first-class support, primary focus
- **Orange Pi**: Proof-of-concept, secondary platform, core team maintained
- **Community Platforms**: Experimental, community-supported, best-effort

### Documentation Hierarchy

1. **Home Page** (`docs/index.md`):
   - Lead with Raspberry Pi quick start
   - Mention multi-platform support in feature list
   - Link to platform comparison page (not prominent)

2. **Getting Started** (`docs/getting-started/`):
   - `quickstart-pi.md` - Primary, most detailed
   - `quickstart-orangepi.md` - Secondary
   - Community platforms - Link to platform-specific README

3. **Platform Docs** (`docs/platforms/`):
   - Comparison table (not advertised heavily)
   - Per-platform technical details
   - Community platform gallery

### GitHub Topics (in priority order)

1. `raspberry-pi` (primary)
2. `router`
3. `docker`
4. `arm`
5. `orange-pi`
6. `single-board-computer`
7. `cross-compilation`

### SEO Strategy

**Primary Keywords** (maintain current rankings):
- "raspberry pi router"
- "pi router build"
- "custom raspberry pi router"

**Secondary Keywords** (expand reach):
- "orange pi router"
- "arm router build"
- "sbc router firmware"

## Risk Assessment & Mitigation

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking changes to Pi builds | Medium | High | Extensive testing, backward compat layer, staged rollout |
| Profile complexity explosion | High | Medium | Strict schema, good defaults, documentation |
| Build failures on exotic hardware | High | Low | Require working test before merge, platform maintainer support |
| Cache storage growth | Medium | Medium | Per-platform limits, LRU eviction, cloud storage option |
| CI/CD pipeline slowdown | High | Medium | Parallel builds, selective platform testing, caching |

### Community Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Abandoned platforms | High | Low | 6-month commitment, archive unmaintained, clear status badges |
| Low-quality contributions | Medium | Medium | Strict PR review, test requirements, build validation |
| Support burden increase | High | Medium | Platform maintainers handle issues, clear support policy |
| Fragmented community | Low | Medium | Central documentation, unified communication channels |

### Marketing Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Brand dilution | Medium | High | Keep Pi front-center, clear messaging hierarchy |
| Community confusion | Medium | Medium | Clear docs hierarchy, platform status badges |
| Feature parity expectations | High | Medium | Document platform limitations upfront, clear support levels |
| SEO ranking loss | Low | High | Maintain primary keywords, add secondaries gradually |

## Success Metrics

### Technical Success (6 months)

- ✅ **3+ platforms supported**: Pi 3B+, Pi 4B, Orange Pi 5+
- ✅ **Build time**: <15 minutes with caching (all platforms)
- ✅ **Test coverage**: 95%+ for profile system
- ✅ **Zero breaking changes**: Existing Pi builds work identically
- ✅ **CI/CD performance**: Full platform matrix <30 minutes

### Community Success (6 months)

- 🎯 **1-2 platform maintainers**: Active community members
- 🎯 **5+ community platforms**: Rock Pi, Nano Pi, etc.
- 🎯 **GitHub activity**: +20 stars, +10 forks
- 🎯 **Platform discussions**: 10+ issues/PRs related to platforms

### Marketing Success (6 months)

- 🎯 **Primary SEO**: Top 5 for "raspberry pi router build"
- 🎯 **Secondary SEO**: Appear in "orange pi router" searches
- 🎯 **Traffic**: 50+ doc views/week from non-Pi platforms
- 🎯 **Brand**: Maintain "Pimeleon" recognition in community

### Maintenance Success (ongoing)

- 🎯 **Maintenance time**: <2 hours/month per community platform
- 🎯 **Review speed**: Platform PRs reviewed within 1 week
- 🎯 **Documentation sync**: 100% accuracy between code and docs
- 🎯 **Support distribution**: 50%+ of platform questions answered by maintainers

## Implementation Roadmap

See [Migration Roadmap](migration-roadmap.md) for detailed phase-by-phase implementation plan.

**High-level timeline** (3-6 months):

- **Phase 1 (Weeks 1-4)**: Foundation - Platform structure, profiles, hardware loader
- **Phase 2 (Weeks 5-8)**: Abstraction - Refactor build stages for profiles
- **Phase 3 (Weeks 9-12)**: Proof-of-concept - Orange Pi 5+ support
- **Phase 4 (Weeks 13-20)**: Community enablement - Contribution guidelines, CI/CD matrix
- **Phase 5 (Weeks 21-24)**: Refinement - Performance optimization, documentation polish

## Related Documentation

- [Hardware Profiles Schema](hardware-profiles.md) - YAML profile reference
- [Migration Roadmap](migration-roadmap.md) - Detailed implementation plan
- [Contributing Platforms](../contributing/adding-platforms.md) - Community contribution guide
- [Platform Comparison](../platforms/README.md) - Supported platforms matrix

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2025-01-06 | Core Team | Initial strategic document |
