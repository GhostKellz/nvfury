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
    const dkms_base = "/usr/src";
    const dkms_dir = try std.fmt.allocPrint(allocator, "{s}/nvidia-open-{s}", .{ dkms_base, options.version });
    defer allocator.free(dkms_dir);

    // Create DKMS source directory
    std.fs.makeDirAbsolute(dkms_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return DkmsResult{
            .success = false,
            .message = "Failed to create DKMS directory",
        },
    };

    // Copy source to DKMS directory
    // In practice, we'd use a proper recursive copy
    var child = std.process.Child.init(&.{
        "cp",
        "-r",
        options.source_dir,
        dkms_dir,
    }, allocator);

    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const copy_term = try child.spawnAndWait();
    if (copy_term != .Exited or copy_term.Exited != 0) {
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

    const conf_file = try std.fs.createFileAbsolute(conf_path, .{});
    defer conf_file.close();
    try conf_file.writeAll(conf_content);

    // Run dkms add
    var add_child = std.process.Child.init(&.{
        "dkms",
        "add",
        "-m",
        "nvidia-open",
        "-v",
        options.version,
    }, allocator);

    add_child.stderr_behavior = .Inherit;
    add_child.stdout_behavior = .Inherit;

    const add_term = try add_child.spawnAndWait();
    if (add_term != .Exited or add_term.Exited != 0) {
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
    const kver = kernel_version orelse try builder.getKernelVersion(allocator);
    defer if (kernel_version == null) allocator.free(kver);

    var child = std.process.Child.init(&.{
        "dkms",
        "build",
        "-m",
        "nvidia-open",
        "-v",
        version,
        "-k",
        kver,
    }, allocator);

    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const term = try child.spawnAndWait();
    if (term != .Exited or term.Exited != 0) {
        return DkmsResult{
            .success = false,
            .message = "DKMS build failed",
        };
    }

    return DkmsResult{
        .success = true,
        .message = "DKMS build completed",
    };
}

/// Install module via DKMS
pub fn installDkms(allocator: std.mem.Allocator, version: []const u8, kernel_version: ?[]const u8) !DkmsResult {
    const kver = kernel_version orelse try builder.getKernelVersion(allocator);
    defer if (kernel_version == null) allocator.free(kver);

    var child = std.process.Child.init(&.{
        "dkms",
        "install",
        "-m",
        "nvidia-open",
        "-v",
        version,
        "-k",
        kver,
    }, allocator);

    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const term = try child.spawnAndWait();
    if (term != .Exited or term.Exited != 0) {
        return DkmsResult{
            .success = false,
            .message = "DKMS install failed",
        };
    }

    return DkmsResult{
        .success = true,
        .message = "DKMS install completed",
    };
}

/// Remove module from DKMS
pub fn unregister(allocator: std.mem.Allocator, version: []const u8) !DkmsResult {
    var child = std.process.Child.init(&.{
        "dkms",
        "remove",
        "-m",
        "nvidia-open",
        "-v",
        version,
        "--all",
    }, allocator);

    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const term = try child.spawnAndWait();
    if (term != .Exited or term.Exited != 0) {
        return DkmsResult{
            .success = false,
            .message = "DKMS remove failed",
        };
    }

    return DkmsResult{
        .success = true,
        .message = "Module removed from DKMS",
    };
}

/// Get DKMS status for nvidia-open
pub fn getStatus(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&.{
        "dkms",
        "status",
        "-m",
        "nvidia-open",
    }, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    var buf = try allocator.alloc(u8, 4096);
    var total: usize = 0;

    if (child.stdout) |stdout| {
        while (total < buf.len) {
            const len = stdout.read(buf[total..]) catch break;
            if (len == 0) break;
            total += len;
        }
    }

    _ = try child.wait();

    // Shrink to actual size
    return allocator.realloc(buf, total) catch buf[0..total];
}

/// Check if DKMS is available
pub fn isDkmsAvailable() bool {
    return std.fs.accessAbsolute("/usr/sbin/dkms", .{}) != error.FileNotFound;
}

test "dkms module" {
    try std.testing.expect(dkms_conf_template.len > 0);
}
