<p align="center">
  <img src="../assets/logo/nvfury.png" alt="nvfury logo" width="400">
</p>

# nvfury Documentation

Performance-tuned NVIDIA open kernel module builder for Linux gaming.

## Overview

nvfury simplifies building NVIDIA's open-source kernel modules from source with gaming-focused optimizations. It handles:

- **Fetching** - Downloads specific versions from GitHub
- **Patching** - Applies performance and compatibility patches
- **Building** - Compiles with proper toolchain (clang/gcc detection)
- **Installing** - DKMS integration for automatic rebuilds
- **Tuning** - Module parameters for gaming workloads

## Quick Start

```bash
# Check current status
nvfury status

# List available versions
nvfury versions

# Build latest with default patches
nvfury build --patches default

# Install via DKMS
sudo nvfury install --dkms --source ~/.cache/nvfury/nvidia-open/590.48.01 --version 590.48.01

# Apply gaming tuning preset
sudo nvfury tune gaming
```

## Documentation Index

| Document | Description |
|----------|-------------|
| [COMMANDS.md](COMMANDS.md) | Complete CLI reference |
| [BUILDING.md](BUILDING.md) | Build process and options |
| [PATCHES.md](PATCHES.md) | Available patches and usage |
| [TUNING.md](TUNING.md) | Module parameters and presets |
| [DKMS.md](DKMS.md) | DKMS integration guide |

## Supported Configurations

### GPUs
- NVIDIA RTX 40 series (Ada Lovelace)
- NVIDIA RTX 50 series (Blackwell) - with dedicated patches

### Kernels
- GCC-built kernels (standard)
- Clang/LLVM-built kernels (CachyOS, etc.)

### Distributions
- Arch Linux / CachyOS / EndeavourOS
- Any distro with kernel headers and build tools

## Target Audience

nvfury is designed for:
- Gamers who want optimized NVIDIA drivers
- Users on rolling releases who need latest drivers quickly
- CachyOS users with clang-built kernels
- Enthusiasts with high-end hardware (RTX 5090, X3D CPUs, 4K 240Hz displays)

## Requirements

- Zig 0.14+ (build tool)
- Git (source fetching)
- Kernel headers (`linux-headers` package)
- Build essentials (make, etc.)
- DKMS (optional, for auto-rebuild)
- curl (GitHub API)

## Project Structure

```
nvfury/
├── src/           # Zig source code
│   ├── main.zig   # CLI entry point
│   ├── fetch.zig  # GitHub fetching
│   ├── builder.zig# Build orchestration
│   ├── patch.zig  # Patch management
│   ├── tune.zig   # Module parameters
│   ├── dkms.zig   # DKMS integration
│   └── config.zig # Configuration
├── patches/       # Kernel module patches
├── docs/          # Documentation
└── dev/           # Docker dev environment
```

## License

MIT License - See LICENSE file.
