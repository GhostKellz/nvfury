# Building NVIDIA Open Kernel Modules

Complete guide to building NVIDIA open kernel modules with nvfury.

## Prerequisites

### Required Packages

**Arch Linux / CachyOS:**
```bash
sudo pacman -S base-devel linux-headers git curl dkms
```

**For clang-built kernels (CachyOS):**
```bash
sudo pacman -S clang lld llvm
```

### Verify Prerequisites

```bash
# Check kernel headers
ls /usr/src/linux-headers-$(uname -r)

# Check compiler
nvfury status | grep "Kernel Compiler"
```

---

## Basic Build

### Build Latest Version

```bash
nvfury build
```

This will:
1. Fetch latest release from GitHub
2. Cache source in `~/.cache/nvfury/nvidia-open/<version>/`
3. Detect kernel compiler (gcc/clang)
4. Build kernel modules

### Build Specific Version

```bash
# List available versions
nvfury versions

# Build specific version
nvfury build --version 580.105.08
```

---

## Building with Patches

### Default Patches

Apply all patches marked as `default: true`:

```bash
nvfury build --patches default
```

Default patches include:
- `clang-compat` - CachyOS/clang kernel compatibility
- `gaming-scheduler` - GPU scheduler optimization
- `memory-optimize` - Memory allocation improvements

### Custom Patch Selection

```bash
# Single patch
nvfury build --patches gaming-scheduler

# Multiple patches (comma-separated)
nvfury build --patches clang-compat,gaming-scheduler,amd-x3d-optimized

# Hardware-specific selection
nvfury build --patches blackwell-boost-gaming,high-refresh-4k,pcie-latency
```

### Recommended Patch Sets

**For RTX 5090/5080 + AMD X3D:**
```bash
nvfury build --patches default,blackwell-boost-gaming,amd-x3d-optimized
```

**For 4K 240Hz OLED:**
```bash
nvfury build --patches default,high-refresh-4k
```

**For low latency gaming:**
```bash
nvfury build --patches default,low-latency-irq,pcie-latency
```

---

## Clang/LLVM Kernel Support

nvfury automatically detects clang-built kernels (common on CachyOS) and configures the LLVM toolchain:

### Auto-Detection

```bash
# Check kernel compiler
cat /proc/version | grep -o 'clang\|gcc'

# nvfury detects this automatically
nvfury status | grep "Kernel Compiler"
```

### What nvfury Does for Clang Kernels

When a clang-built kernel is detected, nvfury sets:

```bash
LLVM=1
CC=clang
LD=ld.lld
AR=llvm-ar
NM=llvm-nm
OBJCOPY=llvm-objcopy
OBJDUMP=llvm-objdump
STRIP=llvm-strip
```

This prevents errors like:
```
error: unrecognized command line option '-mretpoline-external-thunk'
```

---

## Build Output

### Success Output

```
nvfury build
---------------------------------------------------
Fetching NVIDIA open kernel modules...
Version: 590.48.01
Source:  (cached)

Building modules...
Build completed in 47.9s
Output: /root/.cache/nvfury/nvidia-open/590.48.01

Run 'sudo nvfury install' to install the built modules.
```

### Build Location

Built modules are located in:
```
~/.cache/nvfury/nvidia-open/<version>/kernel-open/
├── nvidia.ko
├── nvidia-drm.ko
├── nvidia-modeset.ko
└── nvidia-uvm.ko
```

---

## Troubleshooting

### Missing Kernel Headers

```
Error: Kernel headers not found
```

**Solution:**
```bash
# Arch Linux
sudo pacman -S linux-headers

# For specific kernel
sudo pacman -S linux-cachyos-headers
```

### LLVM Toolchain Errors

```
error: file format not recognized
```

**Solution:** Ensure full LLVM toolchain is installed:
```bash
sudo pacman -S clang lld llvm
```

### Permission Denied

```
Error: Permission denied writing to /usr/src
```

**Solution:** Use sudo for install operations:
```bash
sudo nvfury install --dkms ...
```

### Git Clone Failed

```
Error: GitCloneFailed
```

**Solution:** Check network connection and GitHub availability:
```bash
curl -s https://api.github.com/repos/NVIDIA/open-gpu-kernel-modules/releases/latest
```

---

## Advanced Options

### Dry Run

See what would be built without actually building:

```bash
nvfury build --dry-run --patches default
```

### Build from Local Source

If you've manually downloaded or modified the source:

```bash
nvfury build --source /path/to/nvidia-open-590.48.01
```

### Force Re-fetch

Clear cache and re-download:

```bash
rm -rf ~/.cache/nvfury/nvidia-open/590.48.01
nvfury build --version 590.48.01
```

---

## Build Performance

### Typical Build Times

| System | Time |
|--------|------|
| Ryzen 9 7950X3D | ~45s |
| Ryzen 7 5800X | ~90s |
| Intel i7-12700K | ~60s |

### Parallel Builds

The build uses all available CPU cores by default via `make -j$(nproc)`.

---

## Next Steps

After building:

1. **Install modules:** See [DKMS.md](DKMS.md)
2. **Apply tuning:** See [TUNING.md](TUNING.md)
3. **Reboot** to load new modules
