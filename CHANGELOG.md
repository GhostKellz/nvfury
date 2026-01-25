# Changelog

All notable changes to nvfury will be documented in this file.

## [0.2.0] - 2026-01-25

### Added

- **Auto-update checker** (`check-update`, `update-daemon`)
  - Checks for new driver versions from GitHub
  - Systemd timer for automatic checking every 12 hours
  - Desktop notifications via libnotify

- **Build cache** (`build-cache`)
  - SHA256 source hashing to skip redundant rebuilds
  - Tracks build metadata per version

- **PRIME hybrid graphics** (`prime`)
  - Status detection for hybrid laptops
  - `prime offload` to run apps on NVIDIA GPU
  - `prime setup` to configure X11/modprobe/udev

- **SecureBoot signing** (`sign`)
  - MOK key generation and enrollment
  - Module signing for SecureBoot systems

- **Benchmarking** (`benchmark`)
  - Performance benchmark suite
  - JSON export for comparison

- **Configuration management** (`config`)
  - JSON config file support
  - Driver version pinning
  - Configurable patches directory

- **Pre-flight checks** (`preflight`)
  - Kernel headers, compiler, disk space checks
  - GPU detection and driver compatibility

- **Uninstall command** (`uninstall`)
  - Clean removal of nvfury-installed drivers
  - DKMS cleanup
  - Optional backup restore

- **Shell completions**
  - Bash completion script
  - Zsh completion script
  - Fish completion script

- **Man page** (`man/nvfury.1`)

- **Systemd units**
  - `nvfury-update.service`
  - `nvfury-update.timer`

### Changed

- Updated PKGBUILD to install all assets (man page, completions, patches, systemd units)
- Improved documentation in `docs/COMMANDS.md`

### Fixed

- Hardcoded patches path now configurable via settings

## [0.1.0] - 2025-12-20

### Added

- Initial release
- Fetch NVIDIA open-gpu-kernel-modules from GitHub
- Build with optimized compiler flags
- Patch system with gaming-focused patches
- DKMS installation support
- Direct module installation
- Rollback functionality
- Tuning presets (gaming, balanced, quiet, benchmark)
- GPU detection and architecture info
- Multi-GPU support
