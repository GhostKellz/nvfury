//! nvfury/dkms - DKMS Integration
//!
//! Manages DKMS registration for automatic module rebuilds on kernel updates.

const std = @import("std");
const builder = @import("builder.zig");

/// DKMS configuration template
const dkms_conf_template =
    \\# nvfury DKMS configuration
    \\# Auto-generated - do not edit manually
    \\
    \\PACKAGE_NAME="nvidia-open"
    \\PACKAGE_VERSION="{s}"
    \\
    \\MAKE="make -C kernel-open modules KERNEL_UNAME=${{kernelver}} CC='{s}' CFLAGS='{s}'"
    \\CLEAN="make -C kernel-open clean"
    \\
    \\BUILT_MODULE_NAME[0]="nvidia"
    \\BUILT_MODULE_LOCATION[0]="kernel-open/"
    \\DEST_MODULE_LOCATION[0]="/kernel/drivers/video/nvidia/"
    \\
    \\BUILT_MODULE_NAME[1]="nvidia-modeset"
    \\BUILT_MODULE_LOCATION[1]="kernel-open/"
    \\DEST_MODULE_LOCATION[1]="/kernel/drivers/video/nvidia/"
    \\
    \\BUILT_MODULE_NAME[2]="nvidia-uvm"
    \\BUILT_MODULE_LOCATION[2]="kernel-open/"
    \\DEST_MODULE_LOCATION[2]="/kernel/drivers/video/nvidia/"
    \\
    \\BUILT_MODULE_NAME[3]="nvidia-drm"
    \\BUILT_MODULE_LOCATION[3]="kernel-open/"
    \\DEST_MODULE_LOCATION[3]="/kernel/drivers/video/nvidia/"
    \\
    \\AUTOINSTALL="yes"
    \\
;

/// DKMS registration result
pub const DkmsResult = struct {
    success: bool,
    message: []const u8,
};

/// DKMS options
pub const DkmsOptions = struct {
    /// Driver version
    version: []const u8,
    /// Source directory
    source_dir: []const u8,
    /// Compiler to use
    cc: []const u8 = "zig cc",
    /// CFLAGS
    cflags: []const u8 = "-march=native -O3 -flto",
};

/// Register module with DKMS
pub fn register(allocator: std.mem.Allocator, options: DkmsOptions) !DkmsResult {
    const io = std.Options.debug_io;
    const dkms_base = "/usr/src";
    const dkms_dir = try std.fmt.allocPrint(allocator, "{s}/nvidia-open-{s}", .{ dkms_base, options.version });
    defer allocator.free(dkms_dir);

    // Create DKMS source directory using mkdir -p
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "mkdir", "-p", dkms_dir },
    }) catch return DkmsResult{
        .success = false,
        .message = "Failed to create DKMS directory",
    };

    // Copy source to DKMS directory
    const copy_result = std.process.run(allocator, io, .{
        .argv = &.{ "cp", "-r", options.source_dir, dkms_dir },
    }) catch return DkmsResult{
        .success = false,
        .message = "Failed to copy source to DKMS directory",
    };
    allocator.free(copy_result.stdout);
    allocator.free(copy_result.stderr);

    if (copy_result.term != .exited or copy_result.term.exited != 0) {
        return DkmsResult{
            .success = false,
            .message = "Failed to copy source to DKMS directory",
        };
    }

    // Generate dkms.conf
    const conf_path = try std.fs.path.join(allocator, &.{ dkms_dir, "dkms.conf" });
    defer allocator.free(conf_path);

    const conf_content = try std.fmt.allocPrint(allocator, dkms_conf_template, .{
        options.version,
        options.cc,
        options.cflags,
    });
    defer allocator.free(conf_content);

    // Write config file using posix
    const fd = std.posix.openat(std.posix.AT.FDCWD, conf_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch {
        return DkmsResult{
            .success = false,
            .message = "Failed to create dkms.conf",
        };
    };
    defer std.posix.close(fd);
    const write_result = std.c.write(fd, conf_content.ptr, conf_content.len);
    if (write_result < 0) {
        return DkmsResult{
            .success = false,
            .message = "Failed to write dkms.conf",
        };
    }

    // Run dkms add
    const add_result = std.process.run(allocator, io, .{
        .argv = &.{ "dkms", "add", "-m", "nvidia-open", "-v", options.version },
    }) catch return DkmsResult{
        .success = false,
        .message = "DKMS add failed",
    };
    allocator.free(add_result.stdout);
    allocator.free(add_result.stderr);

    if (add_result.term != .exited or add_result.term.exited != 0) {
        return DkmsResult{
            .success = false,
            .message = "DKMS add failed",
        };
    }

    return DkmsResult{
        .success = true,
        .message = "Module registered with DKMS successfully",
    };
}

/// Build module via DKMS
pub fn buildDkms(allocator: std.mem.Allocator, version: []const u8, kernel_version: ?[]const u8) !DkmsResult {
    const io = std.Options.debug_io;
    const kver = kernel_version orelse try builder.getKernelVersion(allocator);
    defer if (kernel_version == null) allocator.free(kver);

    var child = std.process.spawn(io, .{
        .argv = &.{ "dkms", "build", "-m", "nvidia-open", "-v", version, "-k", kver },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch return DkmsResult{ .success = false, .message = "DKMS build failed to start" };

    const term = child.wait(io) catch return DkmsResult{ .success = false, .message = "DKMS build failed" };
    if (term != .exited or term.exited != 0) {
        return DkmsResult{ .success = false, .message = "DKMS build failed" };
    }

    return DkmsResult{ .success = true, .message = "DKMS build completed" };
}

/// Install module via DKMS
pub fn installDkms(allocator: std.mem.Allocator, version: []const u8, kernel_version: ?[]const u8) !DkmsResult {
    const io = std.Options.debug_io;
    const kver = kernel_version orelse try builder.getKernelVersion(allocator);
    defer if (kernel_version == null) allocator.free(kver);

    var child = std.process.spawn(io, .{
        .argv = &.{ "dkms", "install", "-m", "nvidia-open", "-v", version, "-k", kver },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch return DkmsResult{ .success = false, .message = "DKMS install failed to start" };

    const term = child.wait(io) catch return DkmsResult{ .success = false, .message = "DKMS install failed" };
    if (term != .exited or term.exited != 0) {
        return DkmsResult{ .success = false, .message = "DKMS install failed" };
    }

    return DkmsResult{ .success = true, .message = "DKMS install completed" };
}

/// Remove module from DKMS
pub fn unregister(allocator: std.mem.Allocator, version: []const u8) !DkmsResult {
    const io = std.Options.debug_io;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "dkms", "remove", "-m", "nvidia-open", "-v", version, "--all" },
    }) catch return DkmsResult{ .success = false, .message = "DKMS remove failed" };
    allocator.free(result.stdout);
    allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        return DkmsResult{ .success = false, .message = "DKMS remove failed" };
    }

    return DkmsResult{ .success = true, .message = "Module removed from DKMS" };
}

/// Get DKMS status for nvidia-open
pub fn getStatus(allocator: std.mem.Allocator) ![]u8 {
    const io = std.Options.debug_io;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "dkms", "status", "-m", "nvidia-open" },
    }) catch return error.SystemResources;
    defer allocator.free(result.stderr);

    // Return stdout directly (caller owns it)
    return result.stdout;
}

/// Check if DKMS is available
pub fn isDkmsAvailable() bool {
    // Try to open the file to check if it exists
    const fd = std.posix.openat(std.posix.AT.FDCWD, "/usr/sbin/dkms", .{}, 0) catch return false;
    std.posix.close(fd);
    return true;
}

test "dkms module" {
    try std.testing.expect(dkms_conf_template.len > 0);
}
