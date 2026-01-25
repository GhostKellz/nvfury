# nvfury CLI Reference

Complete reference for all nvfury commands and options.

## Global Options

```bash
nvfury --version    # Show version
nvfury --help       # Show help
nvfury -v           # Short version flag
nvfury -h           # Short help flag
```

---

## status

Display current driver and system status.

```bash
nvfury status
```

**Output includes:**
- Installed driver version (from `/sys/module/nvidia/version`)
- Kernel version
- Kernel headers availability
- DKMS availability
- Kernel compiler (gcc/clang)
- Current tuning preset
- Module parameters

**Example output:**
```
nvfury 0.2.0
---------------------------------------------------
Installed Driver: 590.48.01
Kernel Version:   6.18.2-1-cachyos-lto
Kernel Headers:   Available
DKMS:             Available
Kernel Compiler:  clang

nvfury Tuning Status
---------------------------------------------------
Active Preset: gaming
Module Parameters:
  UsePageAttributeTable: true
  EnablePCIeGen3:        true
  EnableMSI:             true
  EnableGpuFirmware:     true (GSP)
  EnableResizableBar:    true (ReBAR)
```

---

## versions

List available driver versions from GitHub.

```bash
nvfury versions
```

**Features:**
- Fetches releases from NVIDIA/open-gpu-kernel-modules
- Marks currently installed version
- Shows up to 20 recent versions
- Falls back to known versions if offline

**Example output:**
```
Available NVIDIA Open Kernel Module Versions:
  590.48.01  (installed)
  580.94.13
  580.119.02
  590.44.01
  ...
```

---

## build

Fetch and build NVIDIA open kernel modules.

```bash
nvfury build [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--version <ver>` | Build specific version (e.g., `590.48.01`) |
| `--source <path>` | Build from local source directory |
| `--latest` | Fetch and build latest release (default) |
| `--patches <list>` | Apply patches during build |
| `--dry-run` | Show what would be done without building |

### Patches Option

```bash
# Apply default-enabled patches
nvfury build --patches default

# Apply specific patches (comma-separated)
nvfury build --patches clang-compat,gaming-scheduler,amd-x3d-optimized

# Apply patches for specific hardware
nvfury build --patches blackwell-boost-gaming,high-refresh-4k
```

### Examples

```bash
# Build latest version
nvfury build

# Build specific version
nvfury build --version 580.105.08

# Build with all default patches
nvfury build --patches default

# Build with custom patch selection
nvfury build --patches clang-compat,gaming-scheduler,memory-optimize

# Dry run to see what would happen
nvfury build --dry-run --patches default

# Build from local source
nvfury build --source /path/to/nvidia-open-590.48.01
```

### Build Process

1. **Fetch** - Downloads source from GitHub (cached in `~/.cache/nvfury/`)
2. **Patch** - Applies selected patches (if `--patches` specified)
3. **Detect** - Identifies kernel compiler (gcc/clang)
4. **Configure** - Sets up LLVM toolchain if clang kernel
5. **Build** - Compiles kernel modules

---

## install

Install built modules to the system.

```bash
sudo nvfury install [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--dkms` | Install via DKMS (recommended, auto-rebuild) |
| `--direct` | Install directly (manual rebuild needed) |
| `--source <path>` | Source directory with built modules |
| `--version <ver>` | Driver version being installed |
| `--no-backup` | Skip backup of existing modules |

### Examples

```bash
# Install via DKMS (recommended)
sudo nvfury install --dkms \
  --source ~/.cache/nvfury/nvidia-open/590.48.01 \
  --version 590.48.01

# Direct install (no DKMS)
sudo nvfury install --direct \
  --source ~/.cache/nvfury/nvidia-open/590.48.01 \
  --version 590.48.01
```

### DKMS vs Direct

| Method | Auto-rebuild | Persistence | Recommended |
|--------|--------------|-------------|-------------|
| DKMS | Yes (on kernel update) | Yes | Yes |
| Direct | No | Until kernel update | No |

---

## tune

Apply module parameter presets.

```bash
sudo nvfury tune <preset>
nvfury tune status
```

### Presets

| Preset | Description |
|--------|-------------|
| `gaming` | Maximum performance, low latency, ReBAR + GSP enabled |
| `balanced` | Balance of performance and efficiency |
| `quiet` | Power saving, reduced heat/noise |
| `benchmark` | Maximum performance for testing |

### Examples

```bash
# Show current tuning status
nvfury tune status

# Apply gaming preset
sudo nvfury tune gaming

# Apply quiet preset for power saving
sudo nvfury tune quiet
```

### What Tune Does

Writes module parameters to `/etc/modprobe.d/nvfury.conf`:

```
options nvidia NVreg_UsePageAttributeTable=1 NVreg_EnablePCIeGen3=1 ...
```

See [TUNING.md](TUNING.md) for detailed parameter documentation.

---

## patch

Manage kernel module patches.

```bash
nvfury patch <subcommand>
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `list` | List all available patches |
| `apply <name>` | Apply a specific patch |
| `status` | Show applied patches |

### Examples

```bash
# List available patches
nvfury patch list

# Apply a specific patch (requires source directory)
nvfury patch apply gaming-scheduler
```

See [PATCHES.md](PATCHES.md) for detailed patch documentation.

---

## rollback

Restore previous driver version.

```bash
sudo nvfury rollback
```

**Note:** Requires a previous backup created during `nvfury install`.

---

## uninstall

Remove nvfury-installed NVIDIA drivers.

```bash
nvfury uninstall [options]
```

### Options

| Option | Description |
|--------|-------------|
| `status` | Show what is installed and would be removed |
| `--dry-run, -n` | Show what would be done without doing it |
| `--all` | Also remove cache and config directories |
| `--keep-dkms` | Don't remove DKMS entries |
| `--keep-config` | Don't remove modprobe configuration |
| `--remove-cache` | Remove ~/.cache/nvfury |
| `--remove-config` | Remove ~/.config/nvfury |
| `--restore` | Restore modules from backup after removal |
| `--backup <path>` | Specify backup path to restore from |

### Examples

```bash
# See what's installed
nvfury uninstall status

# Preview what would be removed
nvfury uninstall --dry-run

# Remove drivers
sudo nvfury uninstall

# Remove everything including cache
sudo nvfury uninstall --all

# Remove and restore from backup
sudo nvfury uninstall --restore
```

---

## check-update

Check for available driver updates.

```bash
nvfury check-update [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--notify` | Send desktop notification if update available |
| `--force, -f` | Force recheck even if recently checked |

---

## update-daemon

Manage automatic update checking via systemd timer.

```bash
nvfury update-daemon <subcommand>
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `enable` | Install systemd timer (checks every 12 hours) |
| `disable` | Remove systemd timer |
| `status` | Show timer status and last check |

---

## prime

Manage hybrid graphics for laptops with NVIDIA + Intel/AMD iGPU.

```bash
nvfury prime <subcommand>
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `status` | Show current graphics mode |
| `offload <command>` | Run application on NVIDIA GPU |
| `setup` | Configure PRIME with X11/modprobe/udev files |

### Examples

```bash
# Check current mode
nvfury prime status

# Run game on NVIDIA GPU
nvfury prime offload ./game

# Configure system for PRIME
sudo nvfury prime setup
```

---

## sign

Manage MOK signing keys for SecureBoot.

```bash
nvfury sign <subcommand>
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `status` | Show signing key status |
| `setup` | Generate MOK signing key pair |
| `enroll` | Enroll MOK certificate (requires reboot) |
| `sign <path>` | Sign a kernel module |

### Examples

```bash
# Check SecureBoot and key status
nvfury sign status

# Generate signing keys
sudo nvfury sign setup

# Enroll with MOK (reboot required after)
sudo nvfury sign enroll

# Sign a module
sudo nvfury sign sign /path/to/nvidia.ko
```

---

## benchmark

Performance benchmarking.

```bash
nvfury benchmark <subcommand>
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `run` | Run performance benchmark suite |
| `compare <file>` | Compare with a previous benchmark |
| `export <file>` | Export results to JSON |

---

## config

Manage nvfury configuration.

```bash
nvfury config <subcommand>
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `show` | Show current configuration |
| `set <key> <value>` | Set a configuration value |
| `reset` | Reset to defaults |
| `path` | Show config file path |

### Configuration Keys

| Key | Description |
|-----|-------------|
| `pinned_version` | Pin to specific driver version |
| `auto_update_check` | Enable automatic update checking |
| `notifications` | Enable desktop notifications |
| `sign_modules` | Sign modules for SecureBoot |
| `use_dkms` | Use DKMS by default |
| `default_preset` | Default tuning preset |

### Examples

```bash
# Show current config
nvfury config show

# Pin to specific version
nvfury config set pinned_version 590.48.01

# Disable auto-update checks
nvfury config set auto_update_check false
```

---

## preflight

Run pre-build compatibility checks.

```bash
nvfury preflight
```

Checks:
- Kernel headers availability
- Compiler (gcc/clang) availability
- make, git availability
- Disk space
- NVIDIA GPU detection
- SecureBoot status
- Driver compatibility

---

## profile

Export/import tuning profiles in JSON format.

```bash
nvfury profile <subcommand>
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `list` | List available presets |
| `show <preset>` | Show preset parameters |
| `export <preset> <file>` | Export preset to JSON file |
| `import <file> [--apply]` | Import profile from JSON |

---

## gpus

Detect and list all GPUs with architecture info.

```bash
nvfury gpus
```

---

## recommend

Show recommended patches for detected GPU.

```bash
nvfury recommend
```

---

## cache

Manage ccache for compilation.

```bash
nvfury cache <subcommand>
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `status` | Show ccache statistics |
| `clear` | Clear ccache |

---

## build-cache

Manage source hash cache for skip-rebuild optimization.

```bash
nvfury build-cache <subcommand>
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `status` | Show cached builds and source hashes |
| `clear` | Clear build cache |

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NVFURY_CACHE_DIR` | Override cache directory (default: `~/.cache/nvfury/`) |
| `NVFURY_PATCHES_DIR` | Override patches directory |

---

## Configuration Files

| File | Purpose |
|------|---------|
| `/etc/modprobe.d/nvfury.conf` | Module parameters (written by `tune`) |
| `~/.cache/nvfury/` | Source cache directory |
| `/usr/src/nvidia-open-*` | DKMS source directory |
