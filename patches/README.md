# nvfury Patches

This directory contains patches for the NVIDIA open kernel modules.

## Available Patches

### gaming-scheduler.patch
Optimizes the GPU scheduler for gaming workloads with reduced latency.

### memory-optimize.patch
Improves memory allocation paths for better performance.

### interrupt-latency.patch (experimental)
Reduces interrupt handling latency. May not be suitable for all systems.

### blackwell-power-curve.patch
Optimized power curve specifically for Blackwell (RTX 50xx) GPUs.

## Creating Custom Patches

1. Make changes to the NVIDIA source
2. Generate a patch: `git diff > my-patch.patch`
3. Copy to this directory
4. Apply with: `nvfury patch apply my-patch`

## Patch Format

Patches should be in unified diff format (`diff -u` or `git diff`).
Use `-p1` strip level (standard for source tree patches).
