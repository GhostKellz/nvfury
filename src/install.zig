//! nvfury/install - Module Installation
//!
//! Handles installation and backup of kernel modules.

const std = @import("std");
const builder = @import("builder.zig");

/// Installation result
pub const InstallResult = struct {
    success: bool,
    backup_path: ?[]const u8,
    installed_modules: []const []const u8,
    error_message: ?[]const u8,
};

/// Installation options
pub const InstallOptions = struct {
    /// Path to built modules
    source_path: []const u8,
    /// Kernel version to install for
    kernel_version: ?[]const u8 = null,
    /// Create backup before install
    create_backup: bool = true,
    /// Backup directory
    backup_dir: []const u8 = "/var/lib/nvfury/backup/",
    /// Verify modules load after install
    verify: bool = true,
    /// Dry run - don't actually install
    dry_run: bool = false,
};

/// Get module installation path for a kernel version
pub fn getModulePath(allocator: std.mem.Allocator, kernel_version: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "/lib/modules/{s}/kernel/drivers/video/nvidia/", .{kernel_version});
}

/// Install kernel modules
pub fn install(allocator: std.mem.Allocator, options: InstallOptions) !InstallResult {
    // Get kernel version
    const kernel_version = options.kernel_version orelse try builder.getKernelVersion(allocator);
    defer if (options.kernel_version == null) allocator.free(kernel_version);

    const dest_path = try getModulePath(allocator, kernel_version);
    defer allocator.free(dest_path);

    var backup_path: ?[]u8 = null;

    // Create backup if requested
    if (options.create_backup) {
        backup_path = try createBackup(allocator, kernel_version, options.backup_dir);
    }

    if (options.dry_run) {
        return InstallResult{
            .success = true,
            .backup_path = backup_path,
            .installed_modules = &builder.nvidia_modules,
            .error_message = null,
        };
    }

    // Create destination directory
    const io = std.Options.debug_io;
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "mkdir", "-p", dest_path },
    }) catch {
        return InstallResult{
            .success = false,
            .backup_path = backup_path,
            .installed_modules = &.{},
            .error_message = "Failed to create module directory",
        };
    };

    // Copy each module
    for (builder.nvidia_modules) |module_name| {
        const src = try std.fs.path.join(allocator, &.{ options.source_path, module_name });
        defer allocator.free(src);

        const dst = try std.fs.path.join(allocator, &.{ dest_path, module_name });
        defer allocator.free(dst);

        const cp_result = std.process.run(allocator, io, .{
            .argv = &.{ "cp", src, dst },
        }) catch {
            return InstallResult{
                .success = false,
                .backup_path = backup_path,
                .installed_modules = &.{},
                .error_message = "Failed to copy module files",
            };
        };
        allocator.free(cp_result.stdout);
        allocator.free(cp_result.stderr);
        if (cp_result.term != .exited or cp_result.term.exited != 0) {
            return InstallResult{
                .success = false,
                .backup_path = backup_path,
                .installed_modules = &.{},
                .error_message = "Failed to copy module files",
            };
        }
    }

    // Run depmod
    try runDepmod(allocator, kernel_version);

    // Verify if requested
    if (options.verify) {
        if (!try verifyModulesLoad(allocator)) {
            return InstallResult{
                .success = false,
                .backup_path = backup_path,
                .installed_modules = &builder.nvidia_modules,
                .error_message = "Module verification failed - modules may not load correctly",
            };
        }
    }

    return InstallResult{
        .success = true,
        .backup_path = backup_path,
        .installed_modules = &builder.nvidia_modules,
        .error_message = null,
    };
}

/// Create backup of existing modules
pub fn createBackup(allocator: std.mem.Allocator, kernel_version: []const u8, backup_dir: []const u8) ![]u8 {
    // Create timestamped backup directory
    const ts = std.posix.clock_gettime(.REALTIME) catch return error.SystemResources;
    const timestamp: i64 = ts.sec;
    const backup_path = try std.fmt.allocPrint(allocator, "{s}/{s}-{d}/", .{ backup_dir, kernel_version, timestamp });
    errdefer allocator.free(backup_path);

    // Create parent directories recursively
    const io = std.Options.debug_io;
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "mkdir", "-p", backup_path },
    }) catch return error.SystemResources;

    // Copy existing modules to backup
    const src_path = try getModulePath(allocator, kernel_version);
    defer allocator.free(src_path);

    for (builder.nvidia_modules) |module_name| {
        const src = try std.fs.path.join(allocator, &.{ src_path, module_name });
        defer allocator.free(src);

        const dst = try std.fs.path.join(allocator, &.{ backup_path, module_name });
        defer allocator.free(dst);

        const cp_result = std.process.run(allocator, io, .{
            .argv = &.{ "cp", src, dst },
        }) catch continue; // Module doesn't exist or copy failed, skip
        allocator.free(cp_result.stdout);
        allocator.free(cp_result.stderr);
    }

    return backup_path;
}

/// Restore modules from backup
pub fn restore(allocator: std.mem.Allocator, backup_path: []const u8, kernel_version: []const u8) !void {
    const io = std.Options.debug_io;
    const dest_path = try getModulePath(allocator, kernel_version);
    defer allocator.free(dest_path);

    for (builder.nvidia_modules) |module_name| {
        const src = try std.fs.path.join(allocator, &.{ backup_path, module_name });
        defer allocator.free(src);

        const dst = try std.fs.path.join(allocator, &.{ dest_path, module_name });
        defer allocator.free(dst);

        const cp_result = std.process.run(allocator, io, .{
            .argv = &.{ "cp", src, dst },
        }) catch continue;
        allocator.free(cp_result.stdout);
        allocator.free(cp_result.stderr);
    }

    try runDepmod(allocator, kernel_version);
}

/// Run depmod to rebuild module dependencies
fn runDepmod(_: std.mem.Allocator, kernel_version: []const u8) !void {
    const io = std.Options.debug_io;
    var child = std.process.spawn(io, .{
        .argv = &.{ "depmod", "-a", kernel_version },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch return error.SystemResources;

    _ = child.wait(io) catch return error.SystemResources;
}

/// Verify modules can be loaded (using modinfo)
fn verifyModulesLoad(allocator: std.mem.Allocator) !bool {
    const io = std.Options.debug_io;
    for (builder.nvidia_modules) |module_name| {
        // Strip .ko extension
        const name = module_name[0 .. module_name.len - 3];

        const result = std.process.run(allocator, io, .{
            .argv = &.{ "modinfo", name },
        }) catch return false;
        allocator.free(result.stdout);
        allocator.free(result.stderr);

        if (result.term != .exited or result.term.exited != 0) {
            return false;
        }
    }
    return true;
}

/// Unload NVIDIA modules (for update)
pub fn unloadModules(allocator: std.mem.Allocator) !void {
    const io = std.Options.debug_io;
    // Unload in reverse dependency order
    const unload_order = [_][]const u8{
        "nvidia_drm",
        "nvidia_uvm",
        "nvidia_modeset",
        "nvidia",
    };

    for (unload_order) |module| {
        const result = std.process.run(allocator, io, .{
            .argv = &.{ "modprobe", "-r", module },
        }) catch continue;
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
}

/// Load NVIDIA modules
pub fn loadModules(allocator: std.mem.Allocator) !void {
    _ = allocator;
    const io = std.Options.debug_io;
    var child = std.process.spawn(io, .{
        .argv = &.{ "modprobe", "nvidia" },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch return error.SystemResources;

    _ = child.wait(io) catch return error.SystemResources;
}

test "install module" {
    const opts = InstallOptions{
        .source_path = "/test",
        .dry_run = true,
    };
    try std.testing.expect(opts.create_backup);
}
