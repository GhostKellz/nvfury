# DKMS Integration

Guide to installing NVIDIA modules via DKMS for automatic kernel update rebuilds.

## What is DKMS?

DKMS (Dynamic Kernel Module Support) automatically rebuilds kernel modules when:
- The kernel is updated
- The module source is updated

This ensures your NVIDIA drivers continue working after kernel updates without manual intervention.

---

## Prerequisites

### Install DKMS

**Arch Linux / CachyOS:**
```bash
sudo pacman -S dkms
```

**Verify installation:**
```bash
nvfury status | grep DKMS
# Should show: DKMS: Available
```

---

## Installing via DKMS

### Step 1: Build Modules

```bash
nvfury build --patches default
```

Note the output path:
```
Output: /home/user/.cache/nvfury/nvidia-open/590.48.01
```

### Step 2: Install via DKMS

```bash
sudo nvfury install --dkms \
  --source ~/.cache/nvfury/nvidia-open/590.48.01 \
  --version 590.48.01
```

### What This Does

1. **Copies source** to `/usr/src/nvidia-open-590.48.01/`
2. **Generates dkms.conf** with build configuration
3. **Registers** module with DKMS
4. **Builds** for current kernel
5. **Installs** modules to `/lib/modules/`

---

## DKMS Commands

### Check Status

```bash
dkms status
# nvidia-open/590.48.01: installed (kernel 6.18.2-1-cachyos-lto)
```

### Manual Rebuild

If needed after kernel update:
```bash
sudo dkms build nvidia-open/590.48.01
sudo dkms install nvidia-open/590.48.01
```

### Remove Module

```bash
sudo dkms remove nvidia-open/590.48.01 --all
```

---

## DKMS Configuration

nvfury generates `/usr/src/nvidia-open-<version>/dkms.conf`:

```bash
# nvfury DKMS configuration
PACKAGE_NAME="nvidia-open"
PACKAGE_VERSION="590.48.01"

MAKE="make -C kernel-open modules KERNEL_UNAME=${kernelver} CC='clang' CFLAGS='-march=native -O3'"
CLEAN="make -C kernel-open clean"

BUILT_MODULE_NAME[0]="nvidia"
BUILT_MODULE_LOCATION[0]="kernel-open/"
DEST_MODULE_LOCATION[0]="/kernel/drivers/video/nvidia/"

BUILT_MODULE_NAME[1]="nvidia-modeset"
BUILT_MODULE_LOCATION[1]="kernel-open/"
DEST_MODULE_LOCATION[1]="/kernel/drivers/video/nvidia/"

BUILT_MODULE_NAME[2]="nvidia-uvm"
BUILT_MODULE_LOCATION[2]="kernel-open/"
DEST_MODULE_LOCATION[2]="/kernel/drivers/video/nvidia/"

BUILT_MODULE_NAME[3]="nvidia-drm"
BUILT_MODULE_LOCATION[3]="kernel-open/"
DEST_MODULE_LOCATION[3]="/kernel/drivers/video/nvidia/"

AUTOINSTALL="yes"
```

---

## Kernel Update Workflow

### Automatic (DKMS)

1. System updates kernel via pacman/apt
2. DKMS hook triggers automatically
3. Modules rebuild for new kernel
4. Reboot loads new modules

### Manual Verification

After kernel update:
```bash
# Check DKMS built for new kernel
dkms status

# Verify modules load
modinfo nvidia | grep version
```

---

## Troubleshooting

### DKMS Build Fails

```bash
# View build log
cat /var/lib/dkms/nvidia-open/590.48.01/build/make.log
```

**Common causes:**
- Missing kernel headers
- Compiler mismatch (gcc vs clang)
- Source corruption

**Solutions:**
```bash
# Install headers for current kernel
sudo pacman -S linux-headers  # or linux-cachyos-headers

# Rebuild from scratch
sudo dkms remove nvidia-open/590.48.01 --all
nvfury build --patches default
sudo nvfury install --dkms ...
```

### Module Not Loading After Update

```bash
# Check if built for current kernel
dkms status | grep $(uname -r)

# If not built:
sudo dkms build nvidia-open/590.48.01 -k $(uname -r)
sudo dkms install nvidia-open/590.48.01 -k $(uname -r)
```

### Compiler Mismatch

If kernel was built with different compiler:

```bash
# Check kernel compiler
cat /proc/version

# Ensure DKMS uses matching compiler
# nvfury detects this automatically
```

For CachyOS (clang kernel), nvfury sets `LLVM=1` in dkms.conf.

---

## Multiple Kernel Support

DKMS can maintain modules for multiple kernels:

```bash
# Build for specific kernel
sudo dkms build nvidia-open/590.48.01 -k 6.17.0-1-cachyos-lto
sudo dkms install nvidia-open/590.48.01 -k 6.17.0-1-cachyos-lto

# Check all installed
dkms status
# nvidia-open/590.48.01: installed (kernel 6.18.2-1-cachyos-lto)
# nvidia-open/590.48.01: installed (kernel 6.17.0-1-cachyos-lto)
```

---

## Upgrading Driver Version

### Step 1: Build New Version

```bash
nvfury build --version 591.01.02 --patches default
```

### Step 2: Remove Old DKMS Entry

```bash
sudo dkms remove nvidia-open/590.48.01 --all
```

### Step 3: Install New Version

```bash
sudo nvfury install --dkms \
  --source ~/.cache/nvfury/nvidia-open/591.01.02 \
  --version 591.01.02
```

### Step 4: Reboot

```bash
sudo reboot
```

---

## Direct Install (Alternative)

If you prefer not to use DKMS:

```bash
# Build modules
nvfury build --patches default

# Copy modules directly (manual process)
sudo cp ~/.cache/nvfury/nvidia-open/590.48.01/kernel-open/*.ko \
  /lib/modules/$(uname -r)/kernel/drivers/video/nvidia/

# Update module dependencies
sudo depmod -a

# Load modules
sudo modprobe nvidia
```

**Warning:** Direct install requires manual rebuild after every kernel update.

---

## Best Practices

1. **Always use DKMS** for desktop systems
2. **Keep source cached** in `~/.cache/nvfury/` for rebuilds
3. **Test builds** with `nvfury build --dry-run` first
4. **Verify after updates** with `nvfury status`
5. **Keep one version back** in DKMS for rollback

---

## Integration with Pacman Hooks

For Arch Linux, pacman automatically triggers DKMS via hooks in `/usr/share/libalpm/hooks/`.

No additional configuration needed - DKMS rebuilds are automatic.

### Custom Hook (Optional)

Create `/etc/pacman.d/hooks/nvfury-status.hook`:

```ini
[Trigger]
Operation = Upgrade
Type = Package
Target = linux
Target = linux-headers

[Action]
Description = Checking nvfury NVIDIA driver status...
When = PostTransaction
Exec = /usr/bin/nvfury status
```

This shows driver status after kernel upgrades.
