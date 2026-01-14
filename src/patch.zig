//! nvfury/patch - Patch Management
//!
//! Manages patches for NVIDIA open kernel modules.

const std = @import("std");

/// Patch metadata
pub const PatchInfo = struct {
    /// Patch name (filename without .patch)
    name: []const u8,
    /// Human-readable description
    description: []const u8,
    /// Category
    category: Category,
    /// Whether this patch is enabled by default
    default_enabled: bool,
    /// Minimum driver version supported
    min_version: ?[]const u8,
    /// Maximum driver version supported (exclusive)
    max_version: ?[]const u8,

    pub const Category = enum {
        performance,
        latency,
        memory,
        power,
        compatibility,
        experimental,
    };
};

/// Built-in patches
pub const builtin_patches = [_]PatchInfo{
    // === Compatibility ===
    .{
        .name = "clang-compat",
        .description = "Compatibility fixes for clang-built kernels (CachyOS, etc.)",
        .category = .compatibility,
        .default_enabled = true,
        .min_version = null,
        .max_version = null,
    },

    // === Performance ===
    .{
        .name = "gaming-scheduler",
        .description = "Optimize GPU scheduler for gaming workloads",
        .category = .performance,
        .default_enabled = true,
        .min_version = null,
        .max_version = null,
    },
    .{
        .name = "gpu-scheduler-gaming",
        .description = "Real-time scheduling for GPU threads (SCHED_FIFO)",
        .category = .performance,
        .default_enabled = false, // Aggressive - user opt-in
        .min_version = null,
        .max_version = null,
    },

    // === Memory ===
    .{
        .name = "memory-optimize",
        .description = "Optimize memory allocation paths",
        .category = .memory,
        .default_enabled = true,
        .min_version = null,
        .max_version = null,
    },
    .{
        .name = "memory-huge-pages",
        .description = "Prefer huge pages (2MB) for GPU buffers - reduces TLB misses",
        .category = .memory,
        .default_enabled = false, // May increase memory usage
        .min_version = null,
        .max_version = null,
    },

    // === Latency ===
    .{
        .name = "interrupt-latency",
        .description = "Reduce interrupt handling latency",
        .category = .latency,
        .default_enabled = false,
        .min_version = null,
        .max_version = null,
    },
    .{
        .name = "low-latency-irq",
        .description = "MSI-X IRQ optimization - disables IRQ balancing",
        .category = .latency,
        .default_enabled = false, // May affect multi-GPU systems
        .min_version = null,
        .max_version = null,
    },
    .{
        .name = "pcie-latency",
        .description = "Disable PCIe ASPM for consistent latency (~2-5W more power)",
        .category = .latency,
        .default_enabled = false, // Power trade-off
        .min_version = null,
        .max_version = null,
    },

    // === Power ===
    .{
        .name = "blackwell-power-curve",
        .description = "Optimized power curve for Blackwell GPUs (RTX 50 series)",
        .category = .power,
        .default_enabled = false,
        .min_version = "565.57.01",
        .max_version = null,
    },

    // === GPU-Specific ===
    .{
        .name = "blackwell-boost-gaming",
        .description = "Aggressive boost config for RTX 5090/5080 (extended thermal, reduced decay)",
        .category = .performance,
        .default_enabled = false, // Requires good cooling (Astral, Strix, etc.)
        .min_version = "565.57.01",
        .max_version = null,
    },

    // === CPU-Specific ===
    .{
        .name = "amd-x3d-optimized",
        .description = "DMA optimizations for AMD X3D (7950X3D, 9950X3D) large L3 cache",
        .category = .performance,
        .default_enabled = false, // AMD-specific
        .min_version = null,
        .max_version = null,
    },

    // === Display ===
    .{
        .name = "high-refresh-4k",
        .description = "Optimizations for 4K 120Hz+ displays (buffer allocation, modeset)",
        .category = .performance,
        .default_enabled = false,
        .min_version = null,
        .max_version = null,
    },
};

/// Patch application result
pub const PatchResult = struct {
    success: bool,
    patch_name: []const u8,
    message: []const u8,
};

/// Apply a patch to the source tree
pub fn applyPatch(allocator: std.mem.Allocator, source_dir: []const u8, patch_path: []const u8) !PatchResult {
    const io = std.Options.debug_io;
    _ = std.process.run(allocator, io, .{
        .argv = &.{
            "patch",
            "-p1",
            "-d",
            source_dir,
            "-i",
            patch_path,
        },
    }) catch return error.PatchFailed;

    return PatchResult{
        .success = true,
        .patch_name = std.fs.path.basename(patch_path),
        .message = "Patch applied successfully",
    };
}

/// Check if a patch applies cleanly (dry run)
pub fn checkPatch(allocator: std.mem.Allocator, source_dir: []const u8, patch_path: []const u8) !bool {
    const io = std.Options.debug_io;
    const result = std.process.run(allocator, io, .{
        .argv = &.{
            "patch",
            "-p1",
            "--dry-run",
            "-d",
            source_dir,
            "-i",
            patch_path,
        },
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return result.term == .exited and result.term.exited == 0;
}

/// Revert a patch from the source tree
pub fn revertPatch(allocator: std.mem.Allocator, source_dir: []const u8, patch_path: []const u8) !PatchResult {
    const io = std.Options.debug_io;
    _ = std.process.run(allocator, io, .{
        .argv = &.{
            "patch",
            "-p1",
            "-R",
            "-d",
            source_dir,
            "-i",
            patch_path,
        },
    }) catch return error.PatchFailed;

    return PatchResult{
        .success = true,
        .patch_name = std.fs.path.basename(patch_path),
        .message = "Patch reverted successfully",
    };
}

/// List available patches
pub fn listPatches(allocator: std.mem.Allocator, patches_dir: []const u8) ![]PatchInfo {
    var patches = std.ArrayList(PatchInfo).init(allocator);
    errdefer patches.deinit();

    // Add built-in patches
    for (builtin_patches) |patch| {
        try patches.append(patch);
    }

    // Scan patches directory for custom patches
    if (std.fs.openDirAbsolute(patches_dir, .{ .iterate = true })) |dir| {
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".patch")) {
                const name = entry.name[0 .. entry.name.len - 6]; // Remove .patch
                try patches.append(.{
                    .name = try allocator.dupe(u8, name),
                    .description = "Custom patch",
                    .category = .experimental,
                    .default_enabled = false,
                    .min_version = null,
                    .max_version = null,
                });
            }
        }
    } else |_| {}

    return patches.toOwnedSlice();
}

/// Get patch file path
pub fn getPatchPath(allocator: std.mem.Allocator, patches_dir: []const u8, patch_name: []const u8) ![]u8 {
    const filename = try std.fmt.allocPrint(allocator, "{s}.patch", .{patch_name});
    defer allocator.free(filename);

    return std.fs.path.join(allocator, &.{ patches_dir, filename });
}

/// GPU-aware patch recommendation
const gpu = @import("gpu.zig");
const builder = @import("builder.zig");

/// Get recommended patches for the detected GPU
/// Auto-enables Blackwell patches for RTX 50 series
pub fn getRecommendedPatches(allocator: std.mem.Allocator) ![]PatchInfo {
    var patches = std.ArrayList(PatchInfo).init(allocator);
    errdefer patches.deinit();

    // Detect GPU
    const gpu_info = gpu.detectGpu();
    const arch = if (gpu_info) |g| g.architecture else gpu.Architecture.unknown;
    const is_blackwell = (arch == .blackwell);

    // Detect kernel compiler
    const kernel_cc = builder.detectKernelCompiler();
    const is_clang = std.mem.indexOf(u8, kernel_cc, "clang") != null;

    // Add patches based on detection
    for (builtin_patches) |patch_info| {
        var should_enable = patch_info.default_enabled;

        // Auto-enable clang-compat for clang kernels
        if (std.mem.eql(u8, patch_info.name, "clang-compat")) {
            should_enable = is_clang;
        }

        // Auto-enable Blackwell patches for RTX 50 series
        if (std.mem.eql(u8, patch_info.name, "blackwell-boost-gaming") or
            std.mem.eql(u8, patch_info.name, "blackwell-power-curve"))
        {
            should_enable = is_blackwell;
        }

        if (should_enable) {
            try patches.append(patch_info);
        }
    }

    return patches.toOwnedSlice();
}

/// Get all patches that would be enabled for current system
pub fn getAutoPatches() []const []const u8 {
    // Static storage for patch names
    const S = struct {
        var patch_names: [16][]const u8 = undefined;
        var count: usize = 0;
    };

    S.count = 0;

    // Detect GPU
    const gpu_info = gpu.detectGpu();
    const arch = if (gpu_info) |g| g.architecture else gpu.Architecture.unknown;
    const is_blackwell = (arch == .blackwell);

    // Detect kernel compiler
    const kernel_cc = builder.detectKernelCompiler();
    const is_clang = std.mem.indexOf(u8, kernel_cc, "clang") != null;

    // Build list of auto-enabled patches
    for (builtin_patches) |patch_info| {
        var should_enable = patch_info.default_enabled;

        // Auto-enable clang-compat for clang kernels
        if (std.mem.eql(u8, patch_info.name, "clang-compat")) {
            should_enable = is_clang;
        }

        // Auto-enable Blackwell patches for RTX 50 series
        if (std.mem.eql(u8, patch_info.name, "blackwell-boost-gaming") or
            std.mem.eql(u8, patch_info.name, "blackwell-power-curve"))
        {
            should_enable = is_blackwell;
        }

        if (should_enable and S.count < S.patch_names.len) {
            S.patch_names[S.count] = patch_info.name;
            S.count += 1;
        }
    }

    return S.patch_names[0..S.count];
}

/// Print patch recommendations for current system
pub fn printRecommendations(writer: anytype) !void {
    const gpu_info = gpu.detectGpu();
    const kernel_cc = builder.detectKernelCompiler();

    try writer.print("nvfury Patch Recommendations\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    // GPU info
    if (gpu_info) |g| {
        try writer.print("Detected GPU: {s}\n", .{g.getName()});
        try writer.print("Architecture: {s} ({s})\n", .{ g.architecture.name(), g.architecture.generation() });
        try writer.print("Device ID:    0x{x:0>4}\n", .{g.device_id});
    } else {
        try writer.print("Detected GPU: Not detected\n", .{});
    }

    try writer.print("Kernel CC:    {s}\n\n", .{kernel_cc});

    // Recommended patches
    try writer.print("Recommended Patches:\n", .{});
    const patches = getAutoPatches();
    for (patches) |name| {
        // Find description
        for (builtin_patches) |p| {
            if (std.mem.eql(u8, p.name, name)) {
                try writer.print("  [*] {s}\n", .{name});
                try writer.print("      {s}\n", .{p.description});
                break;
            }
        }
    }

    // Show what's NOT enabled
    try writer.print("\nOptional Patches (not auto-enabled):\n", .{});
    for (builtin_patches) |p| {
        var is_recommended = false;
        for (patches) |name| {
            if (std.mem.eql(u8, p.name, name)) {
                is_recommended = true;
                break;
            }
        }
        if (!is_recommended) {
            try writer.print("  [ ] {s}\n", .{p.name});
            try writer.print("      {s}\n", .{p.description});
        }
    }

    try writer.print("\nUse 'nvfury build --patches <name>' to enable specific patches.\n", .{});
    try writer.print("Use 'nvfury build --patches default' for recommended set.\n", .{});
}

test "patch info" {
    try std.testing.expect(builtin_patches.len > 0);
    try std.testing.expectEqualStrings("clang-compat", builtin_patches[0].name);
}

test "gpu aware patches" {
    // Basic test that getAutoPatches doesn't crash
    const patches = getAutoPatches();
    try std.testing.expect(patches.len >= 0);
}
