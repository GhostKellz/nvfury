//! nvfury uninstall - Clean removal of nvfury-installed NVIDIA drivers
//!
//! Removes NVIDIA kernel modules installed by nvfury, cleans up
//! DKMS entries, modprobe configs, and optionally restores backups.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// Uninstall options
pub const UninstallOptions = struct {
    /// Remove DKMS entries
    remove_dkms: bool = true,
    /// Remove modprobe configuration
    remove_modprobe: bool = true,
    /// Remove nvfury cache
    remove_cache: bool = false,
    /// Remove nvfury config
    remove_config: bool = false,
    /// Restore from backup after removal
    restore_backup: bool = false,
    /// Specific backup path to restore
    backup_path: ?[]const u8 = null,
    /// Dry run - show what would be done
    dry_run: bool = false,
};

/// Result of uninstall operation
pub const UninstallResult = struct {
    success: bool,
    modules_removed: u32,
    dkms_removed: bool,
    modprobe_removed: bool,
    cache_removed: bool,
    config_removed: bool,
    backup_restored: bool,
    error_msg: ?[]const u8,
};

/// NVIDIA kernel modules managed by nvfury
const nvidia_modules = [_][]const u8{
    "nvidia",
    "nvidia_drm",
    "nvidia_modeset",
    "nvidia_uvm",
    "nvidia_peermem",
};

/// Paths used by nvfury
const nvfury_paths = struct {
    const modprobe_conf = "/etc/modprobe.d/nvfury.conf";
    const modprobe_blacklist = "/etc/modprobe.d/nvfury-blacklist.conf";
    const cache_dir = "~/.cache/nvfury";
    const config_dir = "~/.config/nvfury";
    const backup_dir = "/var/lib/nvfury/backup";
    const mok_dir = "/var/lib/nvfury/mok";
    const dkms_name = "nvidia-open";
};

/// Check if running as root
fn isRoot() bool {
    const uid = std.os.linux.getuid();
    return uid == 0;
}

/// Expand ~ to home directory
fn expandHome(allocator: Allocator, path: []const u8) ![]const u8 {
    if (path.len == 0) return allocator.dupe(u8, path);

    if (path[0] == '~') {
        // Use C library getenv since we link libc
        const home_ptr = std.c.getenv("HOME");
        const home = if (home_ptr) |ptr| std.mem.sliceTo(ptr, 0) else "/root";
        const total_len = home.len + path.len - 1;
        const result = try allocator.alloc(u8, total_len);
        @memcpy(result[0..home.len], home);
        if (path.len > 1) {
            @memcpy(result[home.len..], path[1..]);
        }
        return result;
    }

    return allocator.dupe(u8, path);
}

/// Check if a path exists using test command
fn pathExists(allocator: Allocator) bool {
    _ = allocator;
    // Simplified - we'll check in the actual functions
    return true;
}

/// Unload NVIDIA kernel modules
fn unloadModules(allocator: Allocator, dry_run: bool) !u32 {
    const io = std.Options.debug_io;
    var count: u32 = 0;

    // Unload in reverse dependency order
    const unload_order = [_][]const u8{
        "nvidia_drm",
        "nvidia_modeset",
        "nvidia_uvm",
        "nvidia_peermem",
        "nvidia",
    };

    for (unload_order) |module| {
        // Check if module is loaded
        const check_result = std.process.run(allocator, io, .{
            .argv = &.{"lsmod"},
        }) catch continue;
        defer allocator.free(check_result.stdout);
        defer allocator.free(check_result.stderr);

        if (std.mem.indexOf(u8, check_result.stdout, module) == null) {
            continue;
        }

        if (dry_run) {
            count += 1;
            continue;
        }

        // Unload the module
        const result = std.process.run(allocator, io, .{
            .argv = &.{ "rmmod", module },
        }) catch continue;
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term == .exited and result.term.exited == 0) {
            count += 1;
        }
    }

    return count;
}

/// Remove DKMS entries for nvidia-open
fn removeDkms(allocator: Allocator, dry_run: bool) !bool {
    const io = std.Options.debug_io;

    // List DKMS modules to find nvidia-open
    const list_result = std.process.run(allocator, io, .{
        .argv = &.{ "dkms", "status" },
    }) catch return false;
    defer allocator.free(list_result.stdout);
    defer allocator.free(list_result.stderr);

    // Find nvidia-open entries
    var lines = std.mem.splitScalar(u8, list_result.stdout, '\n');
    var removed_any = false;

    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "nvidia-open") == null and
            std.mem.indexOf(u8, line, "nvidia/") == null)
        {
            continue;
        }

        // Parse version from line like "nvidia-open/590.48.01, 6.7.0-arch1-1, x86_64: installed"
        var parts = std.mem.splitScalar(u8, line, '/');
        _ = parts.next(); // skip name
        const version_part = parts.next() orelse continue;

        var version_parts = std.mem.splitScalar(u8, version_part, ',');
        const version = std.mem.trim(u8, version_parts.next() orelse continue, " ");

        if (dry_run) {
            removed_any = true;
            continue;
        }

        // Remove DKMS module
        const remove_result = std.process.run(allocator, io, .{
            .argv = &.{ "dkms", "remove", "-m", "nvidia-open", "-v", version, "--all" },
        }) catch continue;
        defer allocator.free(remove_result.stdout);
        defer allocator.free(remove_result.stderr);

        if (remove_result.term == .exited and remove_result.term.exited == 0) {
            removed_any = true;
        }
    }

    // Also try to remove the DKMS source directory
    if (!dry_run) {
        _ = std.process.run(allocator, io, .{
            .argv = &.{ "rm", "-rf", "/usr/src/nvidia-open-*" },
        }) catch {};
    }

    return removed_any;
}

/// Remove modprobe configuration files
fn removeModprobeConfig(allocator: Allocator, dry_run: bool) !bool {
    const io = std.Options.debug_io;
    var removed = false;

    const configs = [_][]const u8{
        nvfury_paths.modprobe_conf,
        nvfury_paths.modprobe_blacklist,
    };

    for (configs) |config_path| {
        // Check if file exists using test command
        const check = std.process.run(allocator, io, .{
            .argv = &.{ "test", "-e", config_path },
        }) catch continue;
        defer allocator.free(check.stdout);
        defer allocator.free(check.stderr);

        if (check.term != .exited or check.term.exited != 0) continue;

        if (dry_run) {
            removed = true;
            continue;
        }

        const result = std.process.run(allocator, io, .{
            .argv = &.{ "rm", "-f", config_path },
        }) catch continue;
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term == .exited and result.term.exited == 0) {
            removed = true;
        }
    }

    return removed;
}

/// Remove nvfury cache directory
fn removeCache(allocator: Allocator, dry_run: bool) !bool {
    const io = std.Options.debug_io;

    const cache_path = try expandHome(allocator, nvfury_paths.cache_dir);
    defer allocator.free(cache_path);

    // Check if directory exists
    const check = std.process.run(allocator, io, .{
        .argv = &.{ "test", "-d", cache_path },
    }) catch return false;
    defer allocator.free(check.stdout);
    defer allocator.free(check.stderr);

    if (check.term != .exited or check.term.exited != 0) return false;

    if (dry_run) {
        return true;
    }

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "rm", "-rf", cache_path },
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return result.term == .exited and result.term.exited == 0;
}

/// Remove nvfury config directory
fn removeConfig(allocator: Allocator, dry_run: bool) !bool {
    const io = std.Options.debug_io;

    const config_path = try expandHome(allocator, nvfury_paths.config_dir);
    defer allocator.free(config_path);

    // Check if directory exists
    const check = std.process.run(allocator, io, .{
        .argv = &.{ "test", "-d", config_path },
    }) catch return false;
    defer allocator.free(check.stdout);
    defer allocator.free(check.stderr);

    if (check.term != .exited or check.term.exited != 0) return false;

    if (dry_run) {
        return true;
    }

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "rm", "-rf", config_path },
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return result.term == .exited and result.term.exited == 0;
}

/// Restore modules from backup
fn restoreBackup(allocator: Allocator, backup_path: ?[]const u8, dry_run: bool) !bool {
    const io = std.Options.debug_io;

    // Determine backup path
    const path = backup_path orelse nvfury_paths.backup_dir;

    // Check if backup directory exists
    const check = std.process.run(allocator, io, .{
        .argv = &.{ "test", "-d", path },
    }) catch return false;
    defer allocator.free(check.stdout);
    defer allocator.free(check.stderr);

    if (check.term != .exited or check.term.exited != 0) return false;

    if (dry_run) {
        return true;
    }

    // Get kernel version
    const uname_result = std.process.run(allocator, io, .{
        .argv = &.{ "uname", "-r" },
    }) catch return false;
    defer allocator.free(uname_result.stdout);
    defer allocator.free(uname_result.stderr);

    const kernel_version = std.mem.trim(u8, uname_result.stdout, " \n\t");
    const dest_path = std.fmt.allocPrint(allocator, "/lib/modules/{s}/updates/", .{kernel_version}) catch return false;
    defer allocator.free(dest_path);

    // Create destination directory
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "mkdir", "-p", dest_path },
    }) catch {};

    // Find and copy the most recent backup
    const find_result = std.process.run(allocator, io, .{
        .argv = &.{ "ls", "-t", path },
    }) catch return false;
    defer allocator.free(find_result.stdout);
    defer allocator.free(find_result.stderr);

    var lines = std.mem.splitScalar(u8, find_result.stdout, '\n');
    const first_backup = lines.next() orelse return false;
    if (first_backup.len == 0) return false;

    const full_backup_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, first_backup }) catch return false;
    defer allocator.free(full_backup_path);

    // Copy modules
    const cp_result = std.process.run(allocator, io, .{
        .argv = &.{ "cp", "-r", full_backup_path, dest_path },
    }) catch return false;
    defer allocator.free(cp_result.stdout);
    defer allocator.free(cp_result.stderr);

    if (cp_result.term != .exited or cp_result.term.exited != 0) {
        return false;
    }

    // Run depmod
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "depmod", "-a" },
    }) catch {};

    return true;
}

/// Perform full uninstall
pub fn uninstall(allocator: Allocator, options: UninstallOptions) !UninstallResult {
    var result = UninstallResult{
        .success = true,
        .modules_removed = 0,
        .dkms_removed = false,
        .modprobe_removed = false,
        .cache_removed = false,
        .config_removed = false,
        .backup_restored = false,
        .error_msg = null,
    };

    // Check root for system operations
    if (!options.dry_run and !isRoot()) {
        if (options.remove_dkms or options.remove_modprobe or options.restore_backup) {
            result.error_msg = "Root privileges required for system operations";
            result.success = false;
            return result;
        }
    }

    // Unload modules first
    result.modules_removed = unloadModules(allocator, options.dry_run) catch 0;

    // Remove DKMS entries
    if (options.remove_dkms) {
        result.dkms_removed = removeDkms(allocator, options.dry_run) catch false;
    }

    // Remove modprobe config
    if (options.remove_modprobe) {
        result.modprobe_removed = removeModprobeConfig(allocator, options.dry_run) catch false;
    }

    // Remove cache
    if (options.remove_cache) {
        result.cache_removed = removeCache(allocator, options.dry_run) catch false;
    }

    // Remove config
    if (options.remove_config) {
        result.config_removed = removeConfig(allocator, options.dry_run) catch false;
    }

    // Restore backup
    if (options.restore_backup) {
        result.backup_restored = restoreBackup(allocator, options.backup_path, options.dry_run) catch false;
    }

    return result;
}

/// Print uninstall status
pub fn printStatus(allocator: Allocator, writer: anytype) !void {
    const io = std.Options.debug_io;

    try writer.print("nvfury Uninstall Status\n", .{});
    try writer.print("---------------------------------------------------\n\n", .{});

    // Check loaded modules
    try writer.print("Loaded NVIDIA Modules:\n", .{});
    const lsmod_result = std.process.run(allocator, io, .{
        .argv = &.{"lsmod"},
    }) catch {
        try writer.print("  Could not check (lsmod failed)\n", .{});
        return;
    };
    defer allocator.free(lsmod_result.stdout);
    defer allocator.free(lsmod_result.stderr);

    var found_any = false;
    for (nvidia_modules) |module| {
        if (std.mem.indexOf(u8, lsmod_result.stdout, module) != null) {
            try writer.print("  {s}: loaded\n", .{module});
            found_any = true;
        }
    }
    if (!found_any) {
        try writer.print("  (none loaded)\n", .{});
    }

    // Check DKMS
    try writer.print("\nDKMS Status:\n", .{});
    const dkms_result = std.process.run(allocator, io, .{
        .argv = &.{ "dkms", "status" },
    }) catch {
        try writer.print("  DKMS not available\n", .{});
        return;
    };
    defer allocator.free(dkms_result.stdout);
    defer allocator.free(dkms_result.stderr);

    var lines = std.mem.splitScalar(u8, dkms_result.stdout, '\n');
    var found_dkms = false;
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "nvidia") != null) {
            try writer.print("  {s}\n", .{line});
            found_dkms = true;
        }
    }
    if (!found_dkms) {
        try writer.print("  No nvidia DKMS entries\n", .{});
    }

    // Check config files
    try writer.print("\nConfiguration Files:\n", .{});

    const configs = [_]struct { path: []const u8, name: []const u8 }{
        .{ .path = nvfury_paths.modprobe_conf, .name = "modprobe config" },
        .{ .path = nvfury_paths.modprobe_blacklist, .name = "blacklist config" },
    };

    for (configs) |cfg| {
        const check = std.process.run(allocator, io, .{
            .argv = &.{ "test", "-e", cfg.path },
        }) catch {
            try writer.print("  {s}: unknown\n", .{cfg.name});
            continue;
        };
        defer allocator.free(check.stdout);
        defer allocator.free(check.stderr);

        const exists = check.term == .exited and check.term.exited == 0;
        try writer.print("  {s}: {s}\n", .{ cfg.name, if (exists) "present" else "not found" });
    }

    // Check cache
    try writer.print("\nCache/Config Directories:\n", .{});
    const cache_path = expandHome(allocator, nvfury_paths.cache_dir) catch nvfury_paths.cache_dir;
    const config_path = expandHome(allocator, nvfury_paths.config_dir) catch nvfury_paths.config_dir;
    defer if (cache_path.ptr != nvfury_paths.cache_dir.ptr) allocator.free(cache_path);
    defer if (config_path.ptr != nvfury_paths.config_dir.ptr) allocator.free(config_path);

    // Check cache exists
    const cache_check = std.process.run(allocator, io, .{
        .argv = &.{ "test", "-d", cache_path },
    }) catch null;
    if (cache_check) |cc| {
        defer allocator.free(cc.stdout);
        defer allocator.free(cc.stderr);
        try writer.print("  Cache ({s}): {s}\n", .{ cache_path, if (cc.term == .exited and cc.term.exited == 0) "present" else "not found" });
    }

    // Check config exists
    const config_check = std.process.run(allocator, io, .{
        .argv = &.{ "test", "-d", config_path },
    }) catch null;
    if (config_check) |cc| {
        defer allocator.free(cc.stdout);
        defer allocator.free(cc.stderr);
        try writer.print("  Config ({s}): {s}\n", .{ config_path, if (cc.term == .exited and cc.term.exited == 0) "present" else "not found" });
    }

    // Check backups
    try writer.print("\nBackups:\n", .{});
    const backup_check = std.process.run(allocator, io, .{
        .argv = &.{ "test", "-d", nvfury_paths.backup_dir },
    }) catch null;
    if (backup_check) |bc| {
        defer allocator.free(bc.stdout);
        defer allocator.free(bc.stderr);
        try writer.print("  Backup dir ({s}): {s}\n", .{ nvfury_paths.backup_dir, if (bc.term == .exited and bc.term.exited == 0) "present" else "not found" });
    }
}

test "expand home" {
    const allocator = std.testing.allocator;
    const path = try expandHome(allocator, "~/.config/test");
    defer allocator.free(path);
    try std.testing.expect(path.len > 0);
    try std.testing.expect(path[0] != '~');
}
