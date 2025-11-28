//! nvfury/builder - Build System
//!
//! Orchestrates the build of NVIDIA open kernel modules with Zig cc.

const std = @import("std");
const config = @import("config.zig");

/// Build result
pub const BuildResult = struct {
    /// Path to built modules
    output_path: []const u8,
    /// List of built module files
    modules: []const []const u8,
    /// Build duration in nanoseconds
    duration_ns: u64,
    /// Whether build succeeded
    success: bool,
    /// Error message if failed
    error_message: ?[]const u8,
};

/// Kernel module file names
pub const nvidia_modules = [_][]const u8{
    "nvidia.ko",
    "nvidia-modeset.ko",
    "nvidia-uvm.ko",
    "nvidia-drm.ko",
};

/// Default compiler flags for gaming optimization
pub const gaming_cflags = [_][]const u8{
    "-march=native",
    "-O3",
    "-flto",
    "-fno-semantic-interposition",
    "-fvisibility=hidden",
    "-fno-plt",
};

/// Build options
pub const BuildOptions = struct {
    /// Source directory
    source_dir: []const u8,
    /// Output directory for built modules
    output_dir: []const u8,
    /// Kernel version to build for (null = current kernel)
    kernel_version: ?[]const u8 = null,
    /// Use zig cc as compiler
    use_zig_cc: bool = true,
    /// Enable LTO
    lto: bool = true,
    /// Extra CFLAGS
    extra_cflags: []const u8 = "",
    /// Parallel jobs (0 = auto)
    jobs: u32 = 0,
    /// Dry run - don't actually build
    dry_run: bool = false,
};

/// Build NVIDIA open kernel modules
pub fn build(allocator: std.mem.Allocator, options: BuildOptions) !BuildResult {
    var timer = std.time.Timer.start() catch null;

    // Get kernel version
    const kernel_version = options.kernel_version orelse try getKernelVersion(allocator);
    defer if (options.kernel_version == null) allocator.free(kernel_version);

    // Get kernel source/headers path
    const kernel_dir = try std.fmt.allocPrint(allocator, "/lib/modules/{s}/build", .{kernel_version});
    defer allocator.free(kernel_dir);

    // Verify kernel headers exist
    std.fs.accessAbsolute(kernel_dir, .{}) catch {
        return BuildResult{
            .output_path = "",
            .modules = &.{},
            .duration_ns = 0,
            .success = false,
            .error_message = "Kernel headers not found. Install linux-headers package.",
        };
    };

    // Build CFLAGS
    var cflags: std.ArrayListUnmanaged(u8) = .{};
    defer cflags.deinit(allocator);

    for (gaming_cflags) |flag| {
        try cflags.appendSlice(allocator, flag);
        try cflags.append(allocator, ' ');
    }
    if (options.extra_cflags.len > 0) {
        try cflags.appendSlice(allocator, options.extra_cflags);
    }

    // Determine compiler
    const cc = if (options.use_zig_cc) "zig cc" else "gcc";

    // Determine job count
    const jobs = if (options.jobs == 0)
        std.Thread.getCpuCount() catch 4
    else
        options.jobs;

    if (options.dry_run) {
        return BuildResult{
            .output_path = options.output_dir,
            .modules = &nvidia_modules,
            .duration_ns = 0,
            .success = true,
            .error_message = null,
        };
    }

    // Run make
    const jobs_str = try std.fmt.allocPrint(allocator, "-j{d}", .{jobs});
    defer allocator.free(jobs_str);

    const cflags_env = try std.fmt.allocPrint(allocator, "CFLAGS={s}", .{cflags.items});
    defer allocator.free(cflags_env);

    const cc_env = try std.fmt.allocPrint(allocator, "CC={s}", .{cc});
    defer allocator.free(cc_env);

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    try env_map.put("CFLAGS", cflags.items);
    try env_map.put("CC", cc);
    try env_map.put("KDIR", kernel_dir);

    var child = std.process.Child.init(&.{
        "make",
        jobs_str,
        "-C",
        options.source_dir,
        "modules",
    }, allocator);

    child.env_map = &env_map;
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const term = try child.spawnAndWait();
    const duration_ns: u64 = if (timer) |*t| t.read() else 0;

    if (term.Exited != 0) {
        return BuildResult{
            .output_path = "",
            .modules = &.{},
            .duration_ns = duration_ns,
            .success = false,
            .error_message = "Build failed",
        };
    }

    return BuildResult{
        .output_path = options.output_dir,
        .modules = &nvidia_modules,
        .duration_ns = duration_ns,
        .success = true,
        .error_message = null,
    };
}

/// Get current kernel version
pub fn getKernelVersion(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&.{ "uname", "-r" }, allocator);
    child.stdout_behavior = .Pipe;

    try child.spawn();

    var buf: [256]u8 = undefined;
    var total: usize = 0;

    // Read all output from stdout pipe
    if (child.stdout) |stdout| {
        while (total < buf.len) {
            const len = stdout.read(buf[total..]) catch break;
            if (len == 0) break;
            total += len;
        }
    }

    _ = try child.wait();

    // Trim trailing newline
    var end = total;
    while (end > 0 and (buf[end - 1] == '\n' or buf[end - 1] == '\r')) {
        end -= 1;
    }

    return allocator.dupe(u8, buf[0..end]);
}

/// Check if kernel headers are available
pub fn hasKernelHeaders(kernel_version: []const u8) bool {
    var buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "/lib/modules/{s}/build", .{kernel_version}) catch return false;
    return std.fs.accessAbsolute(path, .{}) != error.FileNotFound;
}

/// Get Zig version for logging
pub fn getZigVersion(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&.{ "zig", "version" }, allocator);
    child.stdout_behavior = .Pipe;

    try child.spawn();

    var buf: [64]u8 = undefined;
    var total: usize = 0;

    if (child.stdout) |stdout| {
        while (total < buf.len) {
            const len = stdout.read(buf[total..]) catch break;
            if (len == 0) break;
            total += len;
        }
    }

    _ = try child.wait();

    var end = total;
    while (end > 0 and (buf[end - 1] == '\n' or buf[end - 1] == '\r')) {
        end -= 1;
    }

    return allocator.dupe(u8, buf[0..end]);
}

test "builder" {
    try std.testing.expect(nvidia_modules.len == 4);
    try std.testing.expect(gaming_cflags.len > 0);
}
