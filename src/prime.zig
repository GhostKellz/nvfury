//! nvfury/prime - Hybrid Graphics Management
//!
//! Manages PRIME render offload for systems with NVIDIA + Intel/AMD iGPU.
//! Supports dynamic GPU switching and per-application GPU selection.

const std = @import("std");
const config = @import("config.zig");
const gpu = @import("gpu.zig");

/// PRIME render offload environment variables
pub const offload_env = struct {
    /// Use NVIDIA GPU for Vulkan
    pub const vulkan = "VK_DRIVER_FILES=/usr/share/vulkan/icd.d/nvidia_icd.json";
    /// Use NVIDIA GPU for GLX
    pub const glx = "__NV_PRIME_RENDER_OFFLOAD=1";
    /// Provider for GLX
    pub const glx_provider = "__GLX_VENDOR_LIBRARY_NAME=nvidia";
    /// Use NVIDIA GPU for VA-API
    pub const vaapi = "LIBVA_DRIVER_NAME=nvidia";
    /// Use NVIDIA GPU for VDPAU
    pub const vdpau = "VDPAU_DRIVER=nvidia";
};

/// Graphics mode
pub const GraphicsMode = enum {
    integrated, // iGPU only (Intel/AMD)
    discrete, // NVIDIA only
    hybrid, // Dynamic switching (PRIME)
    unknown,

    pub fn description(self: GraphicsMode) []const u8 {
        return switch (self) {
            .integrated => "Integrated GPU only (Intel/AMD) - Best battery life",
            .discrete => "NVIDIA GPU only - Maximum performance",
            .hybrid => "Hybrid mode - Dynamic switching with PRIME offload",
            .unknown => "Unknown configuration",
        };
    }
};

/// Detect current graphics mode
pub fn detectMode() GraphicsMode {
    // Check if NVIDIA module is loaded
    const nvidia_loaded = isModuleLoaded("nvidia");

    // Check if integrated GPU is available
    const has_intel = hasIntelGpu();
    const has_amd_igpu = hasAmdIgpu();
    const has_igpu = has_intel or has_amd_igpu;

    // Check if NVIDIA is the only active GPU
    const nvidia_only = checkNvidiaOnly();

    if (!nvidia_loaded) {
        if (has_igpu) return .integrated;
        return .unknown;
    }

    if (nvidia_only) {
        return .discrete;
    }

    if (has_igpu and nvidia_loaded) {
        return .hybrid;
    }

    return .unknown;
}

/// Check if a kernel module is loaded
fn isModuleLoaded(module: []const u8) bool {
    var path_buf: [128]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/sys/module/{s}", .{module}) catch return false;

    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .DIRECTORY = true }, 0) catch return false;
    _ = std.c.close(fd);
    return true;
}

/// Check for Intel integrated GPU
fn hasIntelGpu() bool {
    // Check for Intel GPU in /sys/class/drm
    const fd = std.posix.openat(std.posix.AT.FDCWD, "/sys/class/drm", .{ .DIRECTORY = true }, 0) catch return false;
    _ = std.c.close(fd);

    // Check for i915 module
    return isModuleLoaded("i915");
}

/// Check for AMD integrated GPU
fn hasAmdIgpu() bool {
    // Check for amdgpu module (could be dGPU too, but commonly iGPU on laptops)
    if (!isModuleLoaded("amdgpu")) return false;

    // Try to detect if it's an APU by checking for specific device classes
    // APUs typically have both CPU and GPU on same die
    const fd = std.posix.openat(std.posix.AT.FDCWD, "/sys/class/drm/card0/device/vendor", .{}, 0) catch return false;
    defer _ = std.c.close(fd);

    var buf: [16]u8 = undefined;
    const n = std.posix.read(fd, &buf) catch return false;
    if (n < 6) return false;

    // Check for AMD vendor ID (0x1002)
    const vendor = std.mem.trim(u8, buf[0..n], " \t\n\r");
    return std.mem.eql(u8, vendor, "0x1002");
}

/// Check if NVIDIA is the only GPU rendering
fn checkNvidiaOnly() bool {
    // If no other GPU modules are loaded, NVIDIA is the only one
    return !hasIntelGpu() and !hasAmdIgpu();
}

/// PRIME status information
pub const PrimeStatus = struct {
    mode: GraphicsMode,
    nvidia_loaded: bool,
    nvidia_runtime_pm: bool,
    igpu_type: ?[]const u8,
    active_gpu: []const u8,
    power_state: []const u8,
};

/// Get detailed PRIME status
pub fn getStatus(allocator: std.mem.Allocator) !PrimeStatus {
    const mode = detectMode();
    const nvidia_loaded = isModuleLoaded("nvidia");

    // Check NVIDIA runtime PM status
    var runtime_pm = false;
    const pm_fd = std.posix.openat(std.posix.AT.FDCWD, "/sys/bus/pci/devices/0000:01:00.0/power/runtime_status", .{}, 0) catch null;
    if (pm_fd) |fd| {
        defer _ = std.c.close(fd);
        var buf: [32]u8 = undefined;
        const n = std.posix.read(fd, &buf) catch 0;
        if (n > 0) {
            const status = std.mem.trim(u8, buf[0..n], " \t\n\r");
            runtime_pm = std.mem.eql(u8, status, "suspended");
        }
    }

    // Determine iGPU type
    var igpu_type: ?[]const u8 = null;
    if (hasIntelGpu()) {
        igpu_type = "Intel";
    } else if (hasAmdIgpu()) {
        igpu_type = "AMD";
    }

    // Determine active GPU
    const active_gpu = switch (mode) {
        .integrated => igpu_type orelse "Unknown iGPU",
        .discrete => "NVIDIA",
        .hybrid => "Dynamic (PRIME)",
        .unknown => "Unknown",
    };

    // Power state
    var power_state: []const u8 = "Unknown";
    if (nvidia_loaded) {
        if (runtime_pm) {
            power_state = "Suspended (D3)";
        } else {
            power_state = "Active (D0)";
        }
    } else {
        power_state = "Off";
    }

    _ = allocator;
    return PrimeStatus{
        .mode = mode,
        .nvidia_loaded = nvidia_loaded,
        .nvidia_runtime_pm = runtime_pm,
        .igpu_type = igpu_type,
        .active_gpu = active_gpu,
        .power_state = power_state,
    };
}

/// Generate environment for PRIME offload
pub fn getOffloadEnv(allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s} {s} {s}", .{
        offload_env.glx,
        offload_env.glx_provider,
        offload_env.vulkan,
    });
}

/// Create a wrapper script for running apps on NVIDIA GPU
pub fn createOffloadScript(allocator: std.mem.Allocator, output_path: []const u8) !void {
    const script =
        \\#!/bin/bash
        \\# nvfury PRIME offload wrapper
        \\# Run applications on the NVIDIA GPU
        \\
        \\export __NV_PRIME_RENDER_OFFLOAD=1
        \\export __GLX_VENDOR_LIBRARY_NAME=nvidia
        \\export __VK_LAYER_NV_optimus=NVIDIA_only
        \\export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
        \\
        \\exec "$@"
        \\
    ;

    const expanded_path = try config.expandPath(allocator, output_path);
    defer allocator.free(expanded_path);

    const fd = try std.posix.openat(std.posix.AT.FDCWD, expanded_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o755);
    defer _ = std.c.close(fd);

    const write_result = std.c.write(fd, script.ptr, script.len);
    if (write_result < 0) return error.WriteError;
}

/// X11 configuration for PRIME
pub const xorg_prime_conf =
    \\# nvfury PRIME configuration
    \\# /etc/X11/xorg.conf.d/10-nvidia-prime.conf
    \\
    \\Section "ServerLayout"
    \\    Identifier "layout"
    \\    Option "AllowNVIDIAGPUScreens"
    \\EndSection
    \\
    \\Section "Device"
    \\    Identifier "nvidia"
    \\    Driver "nvidia"
    \\    BusID "PCI:1:0:0"
    \\    Option "AllowEmptyInitialConfiguration"
    \\EndSection
    \\
;

/// Modprobe configuration for PRIME power management
pub const modprobe_prime_conf =
    \\# nvfury PRIME power management
    \\# /etc/modprobe.d/nvidia-prime-pm.conf
    \\
    \\# Enable runtime power management for NVIDIA GPU
    \\options nvidia NVreg_DynamicPowerManagement=0x02
    \\
    \\# Preserve video memory on suspend (for hybrid mode)
    \\options nvidia NVreg_PreserveVideoMemoryAllocations=1
    \\
;

/// udev rules for PRIME power management
pub const udev_prime_rules =
    \\# nvfury PRIME power management udev rules
    \\# /etc/udev/rules.d/80-nvidia-pm.rules
    \\
    \\# Enable runtime PM for NVIDIA VGA/3D controller
    \\ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
    \\ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
    \\
    \\# Remove NVIDIA GPU from PM management when unbinding
    \\ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
    \\ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"
    \\
;

/// Write PRIME configuration files
pub fn writeConfigs(allocator: std.mem.Allocator, writer: *std.Io.Writer) !bool {
    const io = std.Options.debug_io;

    // Check if running as root
    const euid = std.c.geteuid();
    if (euid != 0) {
        try writer.print("Error: Writing PRIME configs requires root privileges.\n", .{});
        try writer.print("Run with sudo: sudo nvfury prime setup\n", .{});
        return false;
    }

    // Write X11 config
    const xorg_path = "/etc/X11/xorg.conf.d/10-nvidia-prime.conf";
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "mkdir", "-p", "/etc/X11/xorg.conf.d" },
    }) catch {};

    const xorg_fd = std.posix.openat(std.posix.AT.FDCWD, xorg_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch {
        try writer.print("Warning: Could not write X11 config\n", .{});
        return false;
    };
    _ = std.c.write(xorg_fd, xorg_prime_conf.ptr, xorg_prime_conf.len);
    _ = std.c.close(xorg_fd);
    try writer.print("Created: {s}\n", .{xorg_path});

    // Write modprobe config
    const modprobe_path = "/etc/modprobe.d/nvidia-prime-pm.conf";
    const modprobe_fd = std.posix.openat(std.posix.AT.FDCWD, modprobe_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch {
        try writer.print("Warning: Could not write modprobe config\n", .{});
        return false;
    };
    _ = std.c.write(modprobe_fd, modprobe_prime_conf.ptr, modprobe_prime_conf.len);
    _ = std.c.close(modprobe_fd);
    try writer.print("Created: {s}\n", .{modprobe_path});

    // Write udev rules
    const udev_path = "/etc/udev/rules.d/80-nvidia-pm.rules";
    const udev_fd = std.posix.openat(std.posix.AT.FDCWD, udev_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch {
        try writer.print("Warning: Could not write udev rules\n", .{});
        return false;
    };
    _ = std.c.write(udev_fd, udev_prime_rules.ptr, udev_prime_rules.len);
    _ = std.c.close(udev_fd);
    try writer.print("Created: {s}\n", .{udev_path});

    // Reload udev rules
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "udevadm", "control", "--reload-rules" },
    }) catch {};

    _ = std.process.run(allocator, io, .{
        .argv = &.{ "udevadm", "trigger" },
    }) catch {};

    return true;
}

/// Print PRIME status
pub fn printStatus(allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    const status = try getStatus(allocator);

    try writer.print("PRIME Hybrid Graphics Status\n\n", .{});
    try writer.print("  Mode:          {s}\n", .{@tagName(status.mode)});
    try writer.print("  Description:   {s}\n", .{status.mode.description()});
    try writer.print("\n", .{});
    try writer.print("  NVIDIA Loaded: {}\n", .{status.nvidia_loaded});
    try writer.print("  Runtime PM:    {}\n", .{status.nvidia_runtime_pm});
    try writer.print("  Power State:   {s}\n", .{status.power_state});
    try writer.print("\n", .{});

    if (status.igpu_type) |igpu| {
        try writer.print("  Integrated:    {s}\n", .{igpu});
    }
    try writer.print("  Active GPU:    {s}\n", .{status.active_gpu});

    // Show offload instructions
    if (status.mode == .hybrid) {
        try writer.print("\nTo run an application on NVIDIA GPU:\n", .{});
        try writer.print("  nvfury prime offload <command>\n", .{});
        try writer.print("\nOr manually:\n", .{});
        try writer.print("  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <command>\n", .{});
    }
}

test "prime module" {
    _ = GraphicsMode.hybrid.description();
    _ = detectMode();
}
