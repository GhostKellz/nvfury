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

/// Default compiler flags for gaming optimization (kernel-module safe)
/// Note: LTO and some flags don't work well with kernel module builds
pub const gaming_cflags = [_][]const u8{
    "-march=native",
    "-O3",
    // Note: -flto causes issues with kernel module linking
    // Note: -fno-semantic-interposition can break kernel module loading
};

/// Build options
pub const BuildOptions = struct {
    /// Source directory
    source_dir: []const u8,
    /// Output directory for built modules
    output_dir: []const u8,
    /// Kernel version to build for (null = current kernel)
    kernel_version: ?[]const u8 = null,
    /// Use zig cc as compiler (disabled by default - NVIDIA Makefile compatibility issues)
    use_zig_cc: bool = false,
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

    // Detect kernel compiler (clang vs gcc) by reading /proc/version
    const kernel_cc = detectKernelCompiler();

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

    // Determine compiler - use what the kernel was built with
    const cc = if (options.use_zig_cc) "zig cc" else kernel_cc;

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
    // Use EXTRA_CFLAGS to append our flags without overwriting NVIDIA's required flags
    try env_map.put("EXTRA_CFLAGS", cflags.items);
    try env_map.put("CC", cc);
    try env_map.put("KDIR", kernel_dir);

    // For clang-built kernels, set LLVM=1 to tell Kbuild to use LLVM-compatible flags
    // Also set LD, AR, NM, etc. to LLVM tools for consistent toolchain
    if (std.mem.eql(u8, kernel_cc, "clang")) {
        try env_map.put("LLVM", "1");
        try env_map.put("LD", "ld.lld");
        try env_map.put("AR", "llvm-ar");
        try env_map.put("NM", "llvm-nm");
        try env_map.put("OBJCOPY", "llvm-objcopy");
        try env_map.put("OBJDUMP", "llvm-objdump");
        try env_map.put("STRIP", "llvm-strip");
    }

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

    if (term != .Exited or term.Exited != 0) {
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

/// Detect what compiler was used to build the running kernel
/// Reads /proc/version to check for "clang" or "gcc"
pub fn detectKernelCompiler() []const u8 {
    const file = std.fs.openFileAbsolute("/proc/version", .{}) catch return "gcc";
    defer file.close();

    var buf: [512]u8 = undefined;
    const len = file.read(&buf) catch return "gcc";
    const version_str = buf[0..len];

    // Check if kernel was built with clang
    if (std.mem.indexOf(u8, version_str, "clang") != null) {
        return "clang";
    }

    return "gcc";
}

test "builder" {
    try std.testing.expect(nvidia_modules.len == 4);
    try std.testing.expect(gaming_cflags.len > 0);
}

test "detect kernel compiler" {
    const cc = detectKernelCompiler();
    try std.testing.expect(std.mem.eql(u8, cc, "clang") or std.mem.eql(u8, cc, "gcc"));
}
