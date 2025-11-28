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
    .{
        .name = "gaming-scheduler",
        .description = "Optimize GPU scheduler for gaming workloads",
        .category = .performance,
        .default_enabled = true,
        .min_version = null,
        .max_version = null,
    },
    .{
        .name = "memory-optimize",
        .description = "Optimize memory allocation paths",
        .category = .memory,
        .default_enabled = true,
        .min_version = null,
        .max_version = null,
    },
    .{
        .name = "interrupt-latency",
        .description = "Reduce interrupt handling latency",
        .category = .latency,
        .default_enabled = false,
        .min_version = null,
        .max_version = null,
    },
    .{
        .name = "blackwell-power-curve",
        .description = "Optimized power curve for Blackwell GPUs",
        .category = .power,
        .default_enabled = false,
        .min_version = "565.57.01",
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
    var child = std.process.Child.init(&.{
        "patch",
        "-p1",
        "-d",
        source_dir,
        "-i",
        patch_path,
    }, allocator);

    child.stderr_behavior = .Pipe;
    child.stdout_behavior = .Pipe;

    _ = try child.spawnAndWait();

    return PatchResult{
        .success = true,
        .patch_name = std.fs.path.basename(patch_path),
        .message = "Patch applied successfully",
    };
}

/// Check if a patch applies cleanly (dry run)
pub fn checkPatch(allocator: std.mem.Allocator, source_dir: []const u8, patch_path: []const u8) !bool {
    var child = std.process.Child.init(&.{
        "patch",
        "-p1",
        "--dry-run",
        "-d",
        source_dir,
        "-i",
        patch_path,
    }, allocator);

    child.stderr_behavior = .Pipe;
    child.stdout_behavior = .Pipe;

    const term = try child.spawnAndWait();

    return term.Exited == 0;
}

/// Revert a patch from the source tree
pub fn revertPatch(allocator: std.mem.Allocator, source_dir: []const u8, patch_path: []const u8) !PatchResult {
    var child = std.process.Child.init(&.{
        "patch",
        "-p1",
        "-R",
        "-d",
        source_dir,
        "-i",
        patch_path,
    }, allocator);

    child.stderr_behavior = .Pipe;
    child.stdout_behavior = .Pipe;

    _ = try child.spawnAndWait();

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

test "patch info" {
    try std.testing.expect(builtin_patches.len > 0);
    try std.testing.expectEqualStrings("gaming-scheduler", builtin_patches[0].name);
}
