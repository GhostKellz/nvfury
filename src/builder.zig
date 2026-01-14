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
    /// Use ccache for faster rebuilds (auto-detected if not specified)
    use_ccache: ?bool = null,
    /// Custom ccache directory (null = default ~/.cache/ccache)
    ccache_dir: ?[]const u8 = null,
};

/// Ccache statistics
pub const CcacheStats = struct {
    cache_hits: u64,
    cache_misses: u64,
    cache_size: []const u8,
    max_size: []const u8,
    hit_rate: f32,
};

/// Check if ccache is available
pub fn isCcacheAvailable() bool {
    const io = std.Options.debug_io;
    const result = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "which", "ccache" },
    }) catch return false;
    std.heap.page_allocator.free(result.stdout);
    std.heap.page_allocator.free(result.stderr);
    return result.term == .exited and result.term.exited == 0;
}

/// Get ccache statistics (caller must free strings)
pub fn getCcacheStats(allocator: std.mem.Allocator) !CcacheStats {
    const io = std.Options.debug_io;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "ccache", "-s" },
    }) catch return error.SystemResources;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return parseCcacheStats(allocator, result.stdout);
}

/// Parse ccache stats output
fn parseCcacheStats(allocator: std.mem.Allocator, output: []const u8) !CcacheStats {
    var stats = CcacheStats{
        .cache_hits = 0,
        .cache_misses = 0,
        .cache_size = try allocator.dupe(u8, "0 B"),
        .max_size = try allocator.dupe(u8, "0 B"),
        .hit_rate = 0.0,
    };

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "cache hit")) |_| {
            // Parse "cache hit (direct)" or "Hits:" lines
            const num = parseNumber(line);
            stats.cache_hits += num;
        } else if (std.mem.indexOf(u8, line, "cache miss")) |_| {
            const num = parseNumber(line);
            stats.cache_misses += num;
        } else if (std.mem.indexOf(u8, line, "Cache size")) |_| {
            if (std.mem.indexOf(u8, line, ":")) |colon| {
                const value = std.mem.trim(u8, line[colon + 1 ..], " \t\r\n");
                allocator.free(stats.cache_size);
                stats.cache_size = try allocator.dupe(u8, value);
            }
        } else if (std.mem.indexOf(u8, line, "Max cache size")) |_| {
            if (std.mem.indexOf(u8, line, ":")) |colon| {
                const value = std.mem.trim(u8, line[colon + 1 ..], " \t\r\n");
                allocator.free(stats.max_size);
                stats.max_size = try allocator.dupe(u8, value);
            }
        }
    }

    const total = stats.cache_hits + stats.cache_misses;
    if (total > 0) {
        stats.hit_rate = @as(f32, @floatFromInt(stats.cache_hits)) / @as(f32, @floatFromInt(total)) * 100.0;
    }

    return stats;
}

/// Parse a number from a string (finds first sequence of digits)
fn parseNumber(s: []const u8) u64 {
    var num: u64 = 0;
    var in_number = false;

    for (s) |c| {
        if (std.ascii.isDigit(c)) {
            num = num * 10 + (c - '0');
            in_number = true;
        } else if (in_number) {
            break;
        }
    }

    return num;
}

/// Clear ccache
pub fn clearCcache(allocator: std.mem.Allocator) !void {
    const io = std.Options.debug_io;
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "ccache", "-C" },
    }) catch return error.SystemResources;
}

/// Build NVIDIA open kernel modules
pub fn build(allocator: std.mem.Allocator, options: BuildOptions) !BuildResult {
    var timer = std.time.Timer.start() catch null;

    // Get kernel version
    const kernel_version = options.kernel_version orelse try getKernelVersion(allocator);
    defer if (options.kernel_version == null) allocator.free(kernel_version);

    // Get kernel source/headers path
    const kernel_dir = try std.fmt.allocPrint(allocator, "/lib/modules/{s}/build", .{kernel_version});
    defer allocator.free(kernel_dir);

    // Verify kernel headers exist - try to open the directory
    const kernel_fd = std.posix.openat(std.posix.AT.FDCWD, kernel_dir, .{ .DIRECTORY = true }, 0) catch {
        return BuildResult{
            .output_path = "",
            .modules = &.{},
            .duration_ns = 0,
            .success = false,
            .error_message = "Kernel headers not found. Install linux-headers package.",
        };
    };
    std.posix.close(kernel_fd);

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
    // Optionally wrap with ccache for faster rebuilds
    const use_ccache = options.use_ccache orelse isCcacheAvailable();
    const cc = blk: {
        if (options.use_zig_cc) {
            break :blk "zig cc";
        } else if (use_ccache) {
            // ccache will wrap the actual compiler
            break :blk if (std.mem.eql(u8, kernel_cc, "clang")) "ccache clang" else "ccache gcc";
        } else {
            break :blk kernel_cc;
        }
    };

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

    // Build environment variable assignments for make
    var env_str: std.ArrayListUnmanaged(u8) = .{};
    defer env_str.deinit(allocator);

    try env_str.appendSlice(allocator, "EXTRA_CFLAGS='");
    try env_str.appendSlice(allocator, cflags.items);
    try env_str.appendSlice(allocator, "' CC='");
    try env_str.appendSlice(allocator, cc);
    try env_str.appendSlice(allocator, "' KDIR='");
    try env_str.appendSlice(allocator, kernel_dir);
    try env_str.appendSlice(allocator, "'");

    // Set ccache directory if using ccache and custom dir specified
    if (use_ccache) {
        if (options.ccache_dir) |ccache_dir| {
            try env_str.appendSlice(allocator, " CCACHE_DIR='");
            try env_str.appendSlice(allocator, ccache_dir);
            try env_str.appendSlice(allocator, "'");
        }
        try env_str.appendSlice(allocator, " CCACHE_COMPILERCHECK=content");
    }

    // For clang-built kernels, set LLVM=1 to tell Kbuild to use LLVM-compatible flags
    if (std.mem.eql(u8, kernel_cc, "clang")) {
        try env_str.appendSlice(allocator, " LLVM=1 LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip");
    }

    // Build the shell command
    const make_cmd = try std.fmt.allocPrint(allocator, "{s} make {s} -C {s} modules", .{
        env_str.items,
        jobs_str,
        options.source_dir,
    });
    defer allocator.free(make_cmd);

    const io = std.Options.debug_io;
    var child = std.process.spawn(io, .{
        .argv = &.{ "sh", "-c", make_cmd },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch {
        return BuildResult{
            .output_path = "",
            .modules = &.{},
            .duration_ns = 0,
            .success = false,
            .error_message = "Failed to spawn build process",
        };
    };

    const term = child.wait(io) catch {
        return BuildResult{
            .output_path = "",
            .modules = &.{},
            .duration_ns = 0,
            .success = false,
            .error_message = "Failed waiting for build process",
        };
    };
    const duration_ns: u64 = if (timer) |*t| t.read() else 0;

    if (term != .exited or term.exited != 0) {
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
    const io = std.Options.debug_io;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "uname", "-r" },
    }) catch return error.SystemResources;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        return error.SystemResources;
    }

    // Trim trailing newline
    var end = result.stdout.len;
    while (end > 0 and (result.stdout[end - 1] == '\n' or result.stdout[end - 1] == '\r')) {
        end -= 1;
    }

    return allocator.dupe(u8, result.stdout[0..end]);
}

/// Check if kernel headers are available
pub fn hasKernelHeaders(kernel_version: []const u8) bool {
    var buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "/lib/modules/{s}/build", .{kernel_version}) catch return false;
    // Try to open the directory to check if it exists
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .DIRECTORY = true }, 0) catch return false;
    std.posix.close(fd);
    return true;
}

/// Get Zig version for logging
pub fn getZigVersion(allocator: std.mem.Allocator) ![]u8 {
    const io = std.Options.debug_io;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "zig", "version" },
    }) catch return error.SystemResources;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        return error.SystemResources;
    }

    var end = result.stdout.len;
    while (end > 0 and (result.stdout[end - 1] == '\n' or result.stdout[end - 1] == '\r')) {
        end -= 1;
    }

    return allocator.dupe(u8, result.stdout[0..end]);
}

/// Detect what compiler was used to build the running kernel
/// Reads /proc/version to check for "clang" or "gcc"
pub fn detectKernelCompiler() []const u8 {
    const fd = std.posix.openat(std.posix.AT.FDCWD, "/proc/version", .{}, 0) catch return "gcc";
    defer std.posix.close(fd);

    var buf: [512]u8 = undefined;
    const len = std.posix.read(fd, &buf) catch return "gcc";
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
