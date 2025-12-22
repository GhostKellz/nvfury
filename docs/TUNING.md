# Module Parameter Tuning

Guide to NVIDIA kernel module parameters and nvfury presets.

## Overview

NVIDIA kernel modules accept various parameters that affect performance, power management, and feature enablement. nvfury manages these via presets written to `/etc/modprobe.d/nvfury.conf`.

```bash
# Apply a preset
sudo nvfury tune gaming

# Check current status
nvfury tune status
```

---

## Presets

### gaming (Recommended)

Maximum performance with low latency for gaming.

```bash
sudo nvfury tune gaming
```

**Parameters:**
| Parameter | Value | Effect |
|-----------|-------|--------|
| UsePageAttributeTable | 1 | Better memory performance |
| EnablePCIeGen3 | 1 | Full PCIe bandwidth |
| EnableMSI | 1 | Message Signaled Interrupts |
| PreserveVideoMemoryAllocations | 1 | Faster resume from suspend |
| DynamicPowerManagement | 0x02 | Fine-grained power control |
| EnableGpuFirmware | 1 | GSP firmware (required 590+) |
| EnableResizableBar | 1 | ReBAR for RTX 30/40/50 |

---

### balanced

Balance of performance and power efficiency.

```bash
sudo nvfury tune balanced
```

**Parameters:**
| Parameter | Value | Effect |
|-----------|-------|--------|
| UsePageAttributeTable | 1 | Better memory performance |
| EnablePCIeGen3 | 1 | Full PCIe bandwidth |
| EnableMSI | 1 | Message Signaled Interrupts |
| PreserveVideoMemoryAllocations | 1 | Faster resume |
| DynamicPowerManagement | 0x01 | Coarse power management |
| EnableGpuFirmware | 1 | GSP firmware |
| EnableResizableBar | 1 | ReBAR enabled |

---

### quiet

Power saving for reduced heat and noise.

```bash
sudo nvfury tune quiet
```

**Parameters:**
| Parameter | Value | Effect |
|-----------|-------|--------|
| UsePageAttributeTable | 1 | Better memory performance |
| EnablePCIeGen3 | 0 | Allow lower PCIe speeds |
| EnableMSI | 1 | Message Signaled Interrupts |
| PreserveVideoMemoryAllocations | 0 | Save memory |
| DynamicPowerManagement | 0x02 | Fine-grained power |
| EnableGpuFirmware | 1 | GSP firmware |
| EnableResizableBar | 0 | Disabled for power saving |

---

### benchmark

Maximum performance for benchmarking.

```bash
sudo nvfury tune benchmark
```

**Parameters:**
| Parameter | Value | Effect |
|-----------|-------|--------|
| UsePageAttributeTable | 1 | Better memory performance |
| EnablePCIeGen3 | 1 | Full PCIe bandwidth |
| EnableMSI | 1 | Message Signaled Interrupts |
| PreserveVideoMemoryAllocations | 1 | Faster resume |
| DynamicPowerManagement | 0x00 | Disabled for max perf |
| TemporaryFilePath | /dev/shm | RAM-based temp storage |
| EnableGpuFirmware | 1 | GSP firmware |
| EnableResizableBar | 1 | ReBAR enabled |

---

## Parameter Reference

### NVreg_UsePageAttributeTable

Controls use of PAT (Page Attribute Table) for memory mapping.

| Value | Effect |
|-------|--------|
| 0 | Disabled (compatibility mode) |
| 1 | Enabled (better performance) |

**Recommendation:** Always enable unless experiencing stability issues.

---

### NVreg_EnablePCIeGen3

Forces PCIe Gen3 link speed negotiation.

| Value | Effect |
|-------|--------|
| 0 | Auto-negotiate (may use Gen2) |
| 1 | Force Gen3+ negotiation |

**Note:** Modern GPUs (RTX 30/40/50) use PCIe Gen4/5; this ensures minimum Gen3.

---

### NVreg_EnableMSI

Enables Message Signaled Interrupts.

| Value | Effect |
|-------|--------|
| 0 | Use legacy interrupts |
| 1 | Use MSI/MSI-X |

**Recommendation:** Always enable for lower latency.

---

### NVreg_PreserveVideoMemoryAllocations

Preserves VRAM allocations across suspend/resume.

| Value | Effect |
|-------|--------|
| 0 | Clear VRAM on suspend (slower resume) |
| 1 | Preserve VRAM (faster resume) |

**Recommendation:** Enable for gaming systems with suspend usage.

---

### NVreg_DynamicPowerManagement

Controls GPU power management behavior.

| Value | Effect |
|-------|--------|
| 0x00 | Disabled (always full power) |
| 0x01 | Coarse-grained (basic power saving) |
| 0x02 | Fine-grained (aggressive power saving) |

**For gaming:** Use 0x02 (fine-grained) - GPU powers down quickly at idle.
**For benchmarks:** Use 0x00 (disabled) - prevents any power state changes.

---

### NVreg_EnableGpuFirmware (GSP)

Enables GPU System Processor firmware.

| Value | Effect |
|-------|--------|
| 0 | Disable GSP (legacy mode) |
| 1 | Enable GSP firmware |

**Important:**
- Required for driver 590+ on RTX 30/40/50 series
- GSP offloads display and security tasks to dedicated processor
- Improves driver stability and features

---

### NVreg_EnableResizableBar (ReBAR)

Enables Resizable BAR support.

| Value | Effect |
|-------|--------|
| 0 | Disable ReBAR |
| 1 | Enable ReBAR |

**Requirements:**
- Supported GPU (RTX 30/40/50 series)
- ReBAR enabled in BIOS
- Above 4G Decoding enabled in BIOS

**Performance impact:** 5-15% improvement in some games.

---

### NVreg_TemporaryFilePath

Sets the path for driver temporary files.

| Value | Effect |
|-------|--------|
| /tmp | Standard temp directory |
| /dev/shm | RAM-based (faster, benchmark mode) |

---

### NVreg_InitializeSystemMemoryAllocations

Controls system memory initialization.

| Value | Effect |
|-------|--------|
| 0 | Skip initialization (faster) |
| 1 | Initialize all allocations (safer) |

**Recommendation:** 0 for gaming, 1 for security-sensitive workloads.

---

## Configuration File

nvfury writes to `/etc/modprobe.d/nvfury.conf`:

```bash
# nvfury generated configuration
# Do not edit - regenerate with 'nvfury tune'

options nvidia NVreg_UsePageAttributeTable=1 NVreg_EnablePCIeGen3=1 NVreg_EnableMSI=1 NVreg_PreserveVideoMemoryAllocations=1 NVreg_DynamicPowerManagement=0x02 NVreg_TemporaryFilePath=/tmp NVreg_InitializeSystemMemoryAllocations=0 NVreg_EnableGpuFirmware=1 NVreg_EnableResizableBar=1
```

---

## Applying Changes

After running `nvfury tune`:

### Option 1: Reboot (Recommended)
```bash
sudo reboot
```

### Option 2: Reload Module (Risky)
```bash
# Stop display manager
sudo systemctl stop sddm  # or gdm, lightdm

# Unload modules
sudo modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia

# Reload
sudo modprobe nvidia

# Restart display manager
sudo systemctl start sddm
```

---

## Verifying Settings

### Check Loaded Parameters

```bash
# View current module parameters
cat /sys/module/nvidia/parameters/NVreg_EnableResizableBar
cat /sys/module/nvidia/parameters/NVreg_EnableGpuFirmware

# Or use nvidia-smi
nvidia-smi -q | grep -i "bar\|gsp"
```

### Check nvfury Status

```bash
nvfury tune status
```

---

## ReBAR Setup

For ReBAR to work:

1. **BIOS Settings:**
   - Enable "Above 4G Decoding"
   - Enable "Resizable BAR" / "Smart Access Memory"
   - May be under PCIe settings or Advanced

2. **Linux Kernel:**
   - Kernel 5.12+ recommended
   - `pci=realloc` kernel parameter may help

3. **nvfury:**
   ```bash
   sudo nvfury tune gaming  # ReBAR enabled by default
   ```

4. **Verify:**
   ```bash
   nvidia-smi -q | grep "BAR1"
   # Should show full VRAM size, not 256MB
   ```

---

## Troubleshooting

### GSP Firmware Errors

```
NVRM: GPU System Processor (GSP) firmware load failed
```

**Solution:**
- Ensure driver version matches firmware
- Check `/lib/firmware/nvidia/` for GSP firmware files
- Try `sudo nvfury tune gaming` to ensure GSP is enabled

### ReBAR Not Working

**Check BIOS:**
- Above 4G Decoding must be enabled
- CSM (Compatibility Support Module) should be disabled

**Check kernel:**
```bash
dmesg | grep -i "bar\|rebar"
```

### Module Won't Load

```bash
# Check for errors
dmesg | tail -50 | grep -i nvidia

# Verify config syntax
cat /etc/modprobe.d/nvfury.conf
```
