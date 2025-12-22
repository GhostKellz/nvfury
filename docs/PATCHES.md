# nvfury Patches

Complete documentation for all available kernel module patches.

## Overview

nvfury patches modify NVIDIA's open kernel modules at compile time to optimize for specific use cases. Patches are applied during the build process using the `--patches` flag.

```bash
# Apply default patches
nvfury build --patches default

# Apply specific patches
nvfury build --patches gaming-scheduler,amd-x3d-optimized
```

## Patch Categories

| Category | Description |
|----------|-------------|
| **compatibility** | Fixes for specific kernel configurations |
| **performance** | General performance improvements |
| **memory** | Memory allocation optimizations |
| **latency** | Interrupt and timing optimizations |
| **power** | Power management tuning |

---

## Compatibility Patches

### clang-compat

**Category:** compatibility
**Default:** Yes
**Files Modified:** `nvidia/nv-linux.h`

Compatibility fixes for clang-built kernels (CachyOS, Clear Linux, etc.).

**What it does:**
- Fixes compiler-specific macros
- Resolves clang/gcc incompatibilities
- Prevents build errors on LLVM toolchain

**When to use:**
- CachyOS with `linux-cachyos` kernel
- Any kernel built with `CC=clang`
- Shows "clang" in `nvfury status`

---

## Performance Patches

### gaming-scheduler

**Category:** performance
**Default:** Yes
**Files Modified:** `nvidia/nv-kthread-q.c`

Optimizes GPU kernel thread scheduling for gaming workloads.

**What it does:**
- Sets GPU threads to SCHED_NORMAL with nice -5
- Improves frame time consistency
- Reduces scheduling latency for GPU work

**When to use:**
- All gaming systems
- Frame-sensitive workloads

---

### gpu-scheduler-gaming

**Category:** performance
**Default:** No (aggressive)
**Files Modified:** `nvidia/nv-kthread-q.c`

Real-time scheduling for GPU threads using SCHED_FIFO.

**What it does:**
- Sets GPU threads to SCHED_FIFO priority 50
- Maximum scheduling priority for GPU work
- May impact system responsiveness under load

**When to use:**
- Competitive gaming where every ms matters
- Systems with sufficient CPU headroom
- Not recommended for streaming/recording

**Caution:** Can cause audio dropouts or system stutters if CPU is loaded.

---

### blackwell-boost-gaming

**Category:** performance
**Default:** No
**Min Version:** 565.57.01
**Files Modified:** `nvidia/nv-pstate.c`

Aggressive boost configuration for RTX 5090/5080 (GB102/GB103).

**What it does:**
- Extends boost duration before thermal throttling
- Reduces boost clock decay rate (100ms → 200ms)
- Optimizes for sustained high clocks
- Targets P0 state by default

**When to use:**
- RTX 5090 or RTX 5080 GPUs
- Premium cooling solutions (ASUS Astral, Strix, etc.)
- 4K high-refresh gaming

**Hardware requirements:**
- Adequate cooling (custom loop or high-end air)
- Good case airflow
- Quality power delivery

---

### amd-x3d-optimized

**Category:** performance
**Default:** No
**Files Modified:** `nvidia/nv-dma.c`

DMA optimizations for AMD Ryzen X3D processors.

**What it does:**
- Optimizes DMA buffer allocation for large L3 cache
- Uses write-combining for GPU-bound buffers
- Aligns allocations to 64-byte cache lines
- Reduces PCIe round-trips

**When to use:**
- AMD Ryzen 7 7800X3D
- AMD Ryzen 9 7950X3D
- AMD Ryzen 9 9950X3D
- Any AMD CPU with 3D V-Cache

**Performance impact:** 5-10% improvement in CPU-GPU data transfer efficiency.

---

### high-refresh-4k

**Category:** performance
**Default:** No
**Files Modified:** `nvidia-drm/nvidia-drm-gem.c`, `nvidia-drm/nvidia-drm-modeset.c`

Optimizations for 4K displays at 120Hz and above.

**What it does:**
- Pre-allocates quadruple buffers for 240Hz
- Uses uncached/write-combining for scanout buffers
- Minimizes atomic commit latency
- Optimizes for VRR/G-Sync operation

**Bandwidth requirements:**
| Resolution | Refresh | Bandwidth |
|------------|---------|-----------|
| 4K | 144Hz | 33 Gbps (DP 2.0) |
| 4K | 165Hz | 38 Gbps (DP 2.1) |
| 4K | 240Hz | 48 Gbps (DP 2.1 UHBR20) |

**When to use:**
- LG C4/G4 OLED (4K 144Hz)
- LG M4 OLED (4K 144Hz wireless)
- ASUS ROG Swift PG32UCDM (4K 240Hz)
- Any 4K 120Hz+ display

---

## Memory Patches

### memory-optimize

**Category:** memory
**Default:** Yes
**Files Modified:** `nvidia/nv-mempool.c`

Optimizes memory allocation paths for gaming.

**What it does:**
- Improves buffer allocation for frame data
- Reduces memory fragmentation
- Optimizes for repeated allocations

**When to use:**
- All gaming systems
- Long gaming sessions

---

### memory-huge-pages

**Category:** memory
**Default:** No
**Files Modified:** `nvidia/nv-mempool.c`

Prefers 2MB huge pages for GPU buffer allocations.

**What it does:**
- Requests huge pages for large GPU buffers
- Reduces TLB (Translation Lookaside Buffer) misses
- Improves memory access latency

**When to use:**
- Systems with ample RAM (32GB+)
- When huge pages are pre-allocated
- VRAM-heavy games

**Setup required:**
```bash
# Reserve huge pages at boot
echo "vm.nr_hugepages=1024" | sudo tee /etc/sysctl.d/hugepages.conf
```

---

## Latency Patches

### interrupt-latency

**Category:** latency
**Default:** No
**Files Modified:** `nvidia/nv-msi.c`

Reduces interrupt handling latency.

**What it does:**
- Optimizes MSI-X interrupt handling
- Reduces interrupt coalescing
- Faster GPU → CPU notification

**When to use:**
- Competitive FPS gaming
- Low-latency audio production
- VR applications

---

### low-latency-irq

**Category:** latency
**Default:** No
**Files Modified:** `nvidia/nv-msi.c`

MSI-X IRQ optimization that disables IRQ balancing.

**What it does:**
- Pins GPU interrupts to specific CPU cores
- Disables kernel IRQ balancing for GPU
- Reduces interrupt migration overhead

**When to use:**
- Single GPU systems
- When CPU affinity is configured
- Competitive gaming

**Not recommended for:**
- Multi-GPU systems (SLI/NVLink)
- Workstation configurations

---

### pcie-latency

**Category:** latency
**Default:** No
**Files Modified:** `nvidia/nv-pci.c`

Disables PCIe ASPM (Active State Power Management).

**What it does:**
- Disables PCIe L0s and L1 power states
- Maintains full PCIe link speed at all times
- Eliminates link state transition latency

**Trade-offs:**
- **Pro:** Consistent low latency
- **Con:** ~2-5W additional power draw
- **Con:** Slightly higher idle temperatures

**When to use:**
- Desktop systems (not laptops)
- When every millisecond matters
- Sufficient cooling available

---

## Power Patches

### blackwell-power-curve

**Category:** power
**Default:** No
**Min Version:** 565.57.01
**Files Modified:** `nvidia/nv-pstate.c`

Optimized power curve for Blackwell GPUs (RTX 50 series).

**What it does:**
- Adjusts power delivery curve for efficiency
- Optimizes for Blackwell's power architecture
- Balances performance and thermal headroom

**When to use:**
- RTX 5090, 5080, 5070 Ti, 5070
- When power efficiency matters
- Alternative to `blackwell-boost-gaming`

---

## Patch Combinations

### Recommended Sets

**Budget Gaming (any GPU):**
```bash
nvfury build --patches default
```

**High-End Gaming (RTX 40/50 series):**
```bash
nvfury build --patches default,high-refresh-4k
```

**RTX 5090 + AMD X3D:**
```bash
nvfury build --patches default,blackwell-boost-gaming,amd-x3d-optimized,high-refresh-4k
```

**Competitive/Low Latency:**
```bash
nvfury build --patches default,low-latency-irq,pcie-latency,interrupt-latency
```

**Power Efficient:**
```bash
nvfury build --patches clang-compat,memory-optimize
# Skip latency patches, use blackwell-power-curve for RTX 50
```

---

## Creating Custom Patches

Patches are standard unified diff format. Place in `patches/` directory:

```bash
# Create patch from modifications
cd nvidia-open-590.48.01
# Make changes...
git diff > ../patches/my-custom-patch.patch
```

Patch naming convention:
```
patches/
├── my-patch.patch           # Custom patch
└── feature-description.patch
```

Custom patches appear in `nvfury patch list` as "Custom patch" category.

---

## Patch Safety

All patches are:
- **Non-destructive** - Only add or modify, never remove safety checks
- **Reversible** - Can be reverted with `patch -R`
- **Tested** - Verified to compile and load
- **Conservative** - Prefer stability over aggressive optimization

If a patch doesn't apply cleanly, nvfury will skip it with a warning.
