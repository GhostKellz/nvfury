# nvfury

<p align="center">
  <img src="https://img.shields.io/badge/Zig-F7A41D?style=for-the-badge&logo=zig&logoColor=white" alt="Zig">
  <img src="https://img.shields.io/badge/NVIDIA-76B900?style=for-the-badge&logo=nvidia&logoColor=white" alt="NVIDIA">
  <img src="https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/Gaming-E60012?style=for-the-badge&logo=playstation&logoColor=white" alt="Gaming">
  <img src="https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white" alt="Arch Linux">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/Status-Active-brightgreen?style=flat-square" alt="Status">
  <img src="https://img.shields.io/badge/PRs-Welcome-ff69b4?style=flat-square" alt="PRs Welcome">
</p>

**Performance-Tuned NVIDIA Open Driver Builder for Linux Gaming**

nvfury is a Zig-based build system that fetches, patches, and compiles the NVIDIA open-gpu-kernel-modules with gaming-optimized settings, compiler flags, and module parameters.

## Vision

```
┌─────────────────────────────────────────────────────────────┐
│                     Your Games                               │
├─────────────────────────────────────────────────────────────┤
│                   nvcontrol / nvprime                        │
├─────────────────────────────────────────────────────────────┤
│                      nvfury                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  fetch  │  patch  │  build  │  install  │  tune     │   │
│  └─────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│              nvidia-open-gpu-kernel-modules                  │
├─────────────────────────────────────────────────────────────┤
│                    Linux Kernel                              │
└─────────────────────────────────────────────────────────────┘
```

## Why nvfury?

The NVIDIA open kernel modules are a great step forward, but they ship with conservative defaults. nvfury unleashes their full potential:

| Aspect | Stock nvidia-open | nvfury |
|--------|-------------------|--------|
| **Compiler** | System GCC | zig cc with -march=native |
| **Optimization** | -O2 | -O3 + LTO |
| **Module params** | Conservative defaults | Gaming-optimized |
| **Updates** | Manual | Auto-fetch latest |
| **Patches** | None | Community gaming patches |
| **Build system** | Make | Zig build (reproducible) |

## Features

### Auto-Fetch & Build
```bash
# Fetch latest nvidia-open and build optimized modules
nvfury build

# Build specific version
nvfury build --version 580.105.08

# Build from local source
nvfury build --source ~/nvidia-open-gpu-kernel-modules
```

### Gaming-Optimized Module Parameters
```bash
# Apply gaming preset (low latency, max performance)
nvfury tune gaming

# Apply quiet preset (efficiency, low power)
nvfury tune quiet

# Show current module parameters
nvfury tune status
```

### Patch Management
```bash
# List available patches
nvfury patch list

# Apply community gaming patches
nvfury patch apply gaming-scheduler

# Create custom patch
nvfury patch create my-tweak
```

### DKMS Integration
```bash
# Install as DKMS module (rebuilds on kernel update)
nvfury install --dkms

# Install without DKMS (manual rebuild needed)
nvfury install --direct
```

## Optimizations Applied

### Compiler Flags
- `-march=native` - CPU-specific optimizations
- `-O3` - Aggressive optimization level
- `-flto` - Link-time optimization
- `-fno-semantic-interposition` - Better inlining

### Module Parameters (Gaming Preset)
```
NVreg_UsePageAttributeTable=1      # Better memory performance
NVreg_EnablePCIeGen3=1             # Force PCIe Gen3+
NVreg_EnableMSI=1                  # Message Signaled Interrupts
NVreg_PreserveVideoMemoryAllocations=1  # Faster suspend/resume
NVreg_TemporaryFilePath=/tmp       # Faster temp storage
NVreg_EnableGpuFirmware=1          # Enable GSP firmware (590+)
```

### GSP Firmware (Driver 590+)

Driver 590+ supports GSP (GPU System Processor) firmware mode, which offloads
GPU initialization to the on-chip RISC-V controller:

- **Faster initialization** - GPU init/reset is quicker
- **Better power management** - More efficient suspend/resume
- **Native firmware** - Uses GPU's built-in firmware vs userspace blob

nvfury automatically enables GSP on compatible drivers.

### Potential Patches (Community Sourced)
- Scheduler hints for GPU-bound workloads
- Reduced spinlock contention
- Optimized memory allocation paths
- Gaming-specific power state handling

## Architecture

```
nvfury/
├── src/
│   ├── main.zig           # CLI entry point
│   ├── fetch.zig          # Git/tarball fetcher
│   ├── patch.zig          # Patch management
│   ├── build.zig          # Zig cc build orchestration
│   ├── install.zig        # Module installation
│   ├── tune.zig           # Module parameter management
│   └── dkms.zig           # DKMS integration
├── patches/               # Gaming patches
│   ├── gaming-scheduler.patch
│   └── memory-optimize.patch
├── presets/               # Module parameter presets
│   ├── gaming.toml
│   ├── quiet.toml
│   └── balanced.toml
├── build.zig              # Zig build system
└── build.zig.zon          # Dependencies
```

## Requirements

- **Zig 0.12+** - Build system and C compiler
- **Linux Kernel 6.0+** - With kernel headers
- **NVIDIA GPU** - GTX 1600+ / RTX 2000+ (open module compatible)
- **Git** - For fetching nvidia-open source

## Supported GPUs

nvfury builds the NVIDIA open kernel modules, which support:

| Architecture | GPUs | Support |
|--------------|------|---------|
| **Blackwell** | RTX 5090, 5080, 5070, 5060 | Full |
| **Ada Lovelace** | RTX 4090, 4080, 4070, 4060 | Full |
| **Ampere** | RTX 3090, 3080, 3070, 3060 | Full |
| **Turing** | RTX 2080, 2070, 2060, GTX 1660/1650 | Full |

Note: GTX 1000 series (Pascal) requires proprietary driver.

## Installation

### From Source
```bash
git clone https://github.com/GhostKellz/nvfury
cd nvfury
zig build -Doptimize=ReleaseFast
sudo zig-out/bin/nvfury install --dkms
```

### Arch Linux (AUR)
```bash
yay -S nvfury-git
```

## Usage Examples

### First Time Setup
```bash
# Build and install optimized driver
nvfury build
sudo nvfury install --dkms

# Apply gaming optimizations
sudo nvfury tune gaming

# Reboot to load new modules
sudo reboot
```

### Update to Latest Driver
```bash
# Fetch and build latest
nvfury build --latest

# Install (DKMS handles kernel updates)
sudo nvfury install --dkms
```

### Benchmark Mode
```bash
# Build with benchmark instrumentation
nvfury build --benchmark

# Run performance comparison
nvfury benchmark --compare stock
```

## Safety

nvfury includes safety features:
- **Backup** - Creates backup of current modules before install
- **Rollback** - `nvfury rollback` restores previous driver
- **Validation** - Verifies module signatures and integrity
- **Dry-run** - `--dry-run` shows what would happen

## Integration

nvfury integrates with the nv* ecosystem:

| Project | Integration |
|---------|-------------|
| **nvcontrol** | GUI for nvfury settings |
| **nvprime** | Platform-level driver management |
| **ghostkernel** | Eventual deep integration |

## Related Projects

- [nvidia-open-gpu-kernel-modules](https://github.com/NVIDIA/open-gpu-kernel-modules) - Upstream source
- [nvcontrol](https://github.com/GhostKellz/nvcontrol) - GPU control panel
- [ghostkernel](https://github.com/GhostKellz/ghostkernel) - Gaming-optimized kernel

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**Unleash your GPU's full potential.**
