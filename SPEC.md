# nvfury — NVIDIA Open Kernel Module Forge

**Performance-Tuned NVIDIA Open Driver Builder for Linux Gaming**

nvfury is a Zig-based build system that fetches, patches, compiles, and installs NVIDIA’s open GPU kernel modules with aggressive performance tuning for gaming, real-time graphics, and low-latency workloads.

It exists to bridge the gap between:
- NVIDIA’s conservative upstream defaults
- Your high-performance Linux stack (nvcontrol, nvprime, ghostkernel)
- RTX 50 / Blackwell hardware

nvfury is not just a builder — it is a driver optimization and lifecycle system.

---

## 1. Core Goals

nvfury is built around five core principles:

1. **Performance First**
   Stock NVIDIA Open modules prioritize safety and compatibility. nvfury prioritizes speed, latency, and responsiveness.

2. **Zig Native**
   Zig is used for:
   - Build orchestration
   - C toolchain injection
   - Reproducible, deterministic module builds

3. **Blackwell First-Class Citizen**
   RTX 50 / 5090 and newer architectures are the primary targets.

4. **Full Stack Integration**
   Designed to integrate with:
   - nvcontrol
   - nvprime
   - ghostkernel
   - nvbind

5. **Safe by Design**
   Backups, rollbacks, and sanity checks are mandatory — never brick the system.

---

## 2. Position in Your Stack

┌─────────────────────────────────┐
│ Games │
├─────────────────────────────────┤
│ nvcontrol / nvprime │
├─────────────────────────────────┤
│ nvfury │
│ fetch | patch | build | tune │
├─────────────────────────────────┤
│ NVIDIA Open GPU Kernel Mods │
├─────────────────────────────────┤
│ Linux Kernel │
└─────────────────────────────────┘


nvfury does NOT replace NVIDIA drivers — it forges them.

---

## 3. Functional Scope

nvfury handles:

- Fetching official NVIDIA Open source
- Applying performance patches
- Building with Zig-optimized toolchain
- Installing / managing modules
- DKMS support
- Runtime tuning and validation

It does NOT handle:
- Userland (that’s nvprime + nvcontrol)
- Vulkan / DXVK layers (that’s nvprime + ghostVK)
- Kernel building (that’s ghostkernel / ghk)

---

## 4. CLI Command Specification

### 4.1 Build

```bash
nvfury build
nvfury build --version 580.105.08
nvfury build --source ~/nvidia-open/
nvfury build --latest
nvfury build --benchmark
```

Responsibilities:
- Download NVIDIA open kernel modules
- Validate integrity
- Apply patch sets
- Compile using Zig CC
- Produce build artifacts in cache

---

### 4.2 Install

```bash
nvfury install --direct
nvfury install --dkms
```

Responsibilities:
- Backup previous modules
- Install new modules
- Register to DKMS (if enabled)
- Verify loadability

---

### 4.3 Patch Management

```bash
nvfury patch list
nvfury patch apply <name>
nvfury patch create <name>
```

nvfury maintains its own patch ecosystem:
- `gaming-scheduler.patch`
- `memory-optimize.patch`
- `interrupt-latency.patch`
- `blackwell-power-curve.patch`

---

### 4.4 Module Tuning

```bash
nvfury tune gaming
nvfury tune balanced
nvfury tune quiet
nvfury tune status
```

These generate and apply `/etc/modprobe.d/nvfury.conf`

---

### 4.5 Validation

```bash
nvfury status
nvfury doctor
nvfury rollback
```

Status includes:
- Module version
- Active parameters
- Driver state
- GPU compatibility

---

## 5. Compiler Strategy

nvfury replaces NVIDIA's stock build process with:

- Zig `cc` driver
- Custom Makefile hooks
- Deterministic compile layers

Compiler flags:

```zig
-march=native
-O3
-flto
-fno-semantic-interposition
-fvisibility=hidden
-fno-plt
```

Optional:
```zig
-mtune=znver4
```

---

## 6. Module Parameter Presets

Default parameters (Gaming Profile):

```conf
NVreg_UsePageAttributeTable=1
NVreg_EnablePCIeGen3=1
NVreg_EnableMSI=1
NVreg_PreserveVideoMemoryAllocations=1
NVreg_DynamicPowerManagement=0x02
NVreg_TemporaryFilePath=/tmp
NVreg_InitializeSystemMemoryAllocations=0
```

Other profiles:
- `quiet.toml` → power saving, lower clocks
- `balanced.toml` → stable and efficient
- `benchmark.toml` → max performance, dev only

---

## 7. Directory Layout
```text
nvfury/
├── src/
│ ├── main.zig
│ ├── fetch.zig
│ ├── patch.zig
│ ├── build.zig
│ ├── install.zig
│ ├── tune.zig
│ ├── dkms.zig
│ └── verify.zig
├── patches/
│ ├── gaming-scheduler.patch
│ ├── latency-optimize.patch
│ ├── blackwell-tweaks.patch
│ └── memory-optimize.patch
├── presets/
│ ├── gaming.toml
│ ├── balanced.toml
│ └── quiet.toml
├── build.zig
└── build.zig.zon
```
---

## 8. Hardware Support

Supported architectures:
- Blackwell (RTX 5090 — primary target)
- Ada Lovelace (RTX 4090 / 4080)
- Ampere (RTX 30 series)
- Turing (RTX 20 + GTX 16 series only)

Not supported:
- Pascal (GTX 10xx) — proprietary only

---

## 9. Integration Architecture

nvfury integrates into your ecosystem like this:

| Project | Role |
|--------|------|
| nvcontrol | GUI + control layer |
| nvprime | Platform / runtime |
| ghostkernel | Kernel builds |
| nvbind | Container GPU runtime |

nvfury will expose an IPC API:
```
/run/nvfury.sock
```

For nvcontrol + nvprime to communicate with.

---

## 10. Safety Model

nvfury enforces:

- Pre-install driver backup
- Bootable fallback option
- Automatic rollback if module fails to load
- Dry-run verification mode

Rollback example:
```bash
nvfury rollback
```

Restores last known good driver modules.

---

## 11. Long-Term Vision

nvfury eventually becomes:

- The default builder for GhostKernel NVIDIA integration
- A backend for nvprime driver management
- A power-user alternative to distro NVIDIA packages
- A Blackwell-first ecosystem tool

---

## 12. Philosophy

NVIDIA gave us the freedom.

nvfury gives us control.

Not vendor locked.  
Not distro restricted.  
Not watered down.

Just raw, tuned, accelerated Linux graphics.





