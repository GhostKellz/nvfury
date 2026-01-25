//! nvfury/build_cache - Build Cache Management
//!
//! Tracks source hashes to skip redundant rebuilds when source is unchanged.
//! Uses SHA256 hashing of key source files to detect changes.

const std = @import("std");
const config = @import("config.zig");

/// Build cache metadata
pub const BuildMeta = struct {
    /// Source version (e.g., "590.48.01")
    version: []const u8,
    /// SHA256 hash of source directory (key files)
    source_hash: [64]u8,
    /// Kernel version built for
    kernel_version: []const u8,
    /// Build timestamp (unix seconds)
    build_time: i64,
    /// Compiler used
    compiler: []const u8,
    /// CFLAGS used
    cflags: []const u8,
    /// Whether build succeeded
    success: bool,

    /// Check if this cache entry matches current build parameters
    pub fn matches(self: BuildMeta, version: []const u8, source_hash: []const u8, kernel_version: []const u8) bool {
        return std.mem.eql(u8, self.version, version) and
            std.mem.eql(u8, &self.source_hash, source_hash) and
            std.mem.eql(u8, self.kernel_version, kernel_version);
    }

    /// Serialize to JSON
    pub fn toJson(self: BuildMeta, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "{\n");
        try buf.appendSlice(allocator, "  \"version\": \"");
        try buf.appendSlice(allocator, self.version);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"source_hash\": \"");
        try buf.appendSlice(allocator, &self.source_hash);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"kernel_version\": \"");
        try buf.appendSlice(allocator, self.kernel_version);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"build_time\": ");
        var num_buf: [32]u8 = undefined;
        const ts_str = std.fmt.bufPrint(&num_buf, "{d}", .{self.build_time}) catch unreachable;
        try buf.appendSlice(allocator, ts_str);
        try buf.appendSlice(allocator, ",\n");

        try buf.appendSlice(allocator, "  \"compiler\": \"");
        try buf.appendSlice(allocator, self.compiler);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"cflags\": \"");
        try buf.appendSlice(allocator, self.cflags);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"success\": ");
        try buf.appendSlice(allocator, if (self.success) "true" else "false");
        try buf.appendSlice(allocator, "\n}\n");

        return buf.toOwnedSlice(allocator);
    }

    /// Parse from JSON
    pub fn fromJson(allocator: std.mem.Allocator, json: []const u8) !BuildMeta {
        const version = try parseJsonString(allocator, json, "\"version\"");
        errdefer allocator.free(version);

        const source_hash_str = try parseJsonString(allocator, json, "\"source_hash\"");
        defer allocator.free(source_hash_str);

        const kernel_version = try parseJsonString(allocator, json, "\"kernel_version\"");
        errdefer allocator.free(kernel_version);

        const compiler = try parseJsonString(allocator, json, "\"compiler\"");
        errdefer allocator.free(compiler);

        const cflags = try parseJsonString(allocator, json, "\"cflags\"");
        errdefer allocator.free(cflags);

        var source_hash: [64]u8 = undefined;
        if (source_hash_str.len >= 64) {
            @memcpy(&source_hash, source_hash_str[0..64]);
        } else {
            @memset(&source_hash, '0');
        }

        return BuildMeta{
            .version = version,
            .source_hash = source_hash,
            .kernel_version = kernel_version,
            .build_time = parseJsonInt(json, "\"build_time\"") orelse 0,
            .compiler = compiler,
            .cflags = cflags,
            .success = parseJsonBool(json, "\"success\"") orelse false,
        };
    }

    pub fn deinit(self: *BuildMeta, allocator: std.mem.Allocator) void {
        allocator.free(self.version);
        allocator.free(self.kernel_version);
        allocator.free(self.compiler);
        allocator.free(self.cflags);
        self.* = undefined;
    }
};

/// Files to hash for source change detection (relative to source root)
/// These are the key files that affect the build output
const hash_files = [_][]const u8{
    "kernel-open/Makefile",
    "kernel-open/nvidia/nv-kernel.o_binary",
    "kernel-open/nvidia-modeset/nv-modeset-kernel.o_binary",
    "kernel-open/nvidia-uvm/uvm_common.c",
    "kernel-open/nvidia-drm/nvidia-drm.c",
    "version.mk",
    "NVIDIA-kernel-module-source-TempVersion",
};

/// Compute SHA256 hash of key source files
pub fn computeSourceHash(allocator: std.mem.Allocator, source_dir: []const u8) ![64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    // Hash each key file
    for (hash_files) |file| {
        const file_path = try std.fs.path.join(allocator, &.{ source_dir, file });
        defer allocator.free(file_path);

        const fd = std.posix.openat(std.posix.AT.FDCWD, file_path, .{}, 0) catch {
            // File doesn't exist - hash the path name to represent "missing"
            hasher.update("MISSING:");
            hasher.update(file);
            continue;
        };
        defer std.posix.close(fd);

        // Read file in chunks and hash
        var buf: [8192]u8 = undefined;
        while (true) {
            const n = std.posix.read(fd, &buf) catch break;
            if (n == 0) break;
            hasher.update(buf[0..n]);
        }
    }

    // Also hash directory listing of kernel-open to catch added/removed files
    const kernel_open_dir = try std.fs.path.join(allocator, &.{ source_dir, "kernel-open" });
    defer allocator.free(kernel_open_dir);

    const io = std.Options.debug_io;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "ls", "-la", kernel_open_dir },
    }) catch null;

    if (result) |r| {
        hasher.update(r.stdout);
        allocator.free(r.stdout);
        allocator.free(r.stderr);
    }

    // Finalize hash
    var hash: [32]u8 = undefined;
    hasher.final(&hash);

    // Convert to hex string
    var hex: [64]u8 = undefined;
    for (hash, 0..) |byte, i| {
        const chars = "0123456789abcdef";
        hex[i * 2] = chars[byte >> 4];
        hex[i * 2 + 1] = chars[byte & 0x0f];
    }

    return hex;
}

/// Cache file path for a specific version
fn getCachePath(allocator: std.mem.Allocator, version: []const u8) ![]u8 {
    const cache_dir = try config.expandPath(allocator, "~/.cache/nvfury/build-meta");
    defer allocator.free(cache_dir);

    return std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ cache_dir, version });
}

/// Read cached build metadata for a version
pub fn readBuildMeta(allocator: std.mem.Allocator, version: []const u8) !?BuildMeta {
    const cache_path = try getCachePath(allocator, version);
    defer allocator.free(cache_path);

    const fd = std.posix.openat(std.posix.AT.FDCWD, cache_path, .{}, 0) catch return null;
    defer std.posix.close(fd);

    // Get file size
    const size_i64 = std.c.lseek64(fd, 0, 2);
    if (size_i64 < 0 or size_i64 > 16384) return null;
    _ = std.c.lseek64(fd, 0, 0);
    const size: usize = @intCast(size_i64);

    const content = try allocator.alloc(u8, size);
    defer allocator.free(content);

    var total_read: usize = 0;
    while (total_read < size) {
        const n = std.posix.read(fd, content[total_read..]) catch return null;
        if (n == 0) break;
        total_read += n;
    }

    return try BuildMeta.fromJson(allocator, content[0..total_read]);
}

/// Write build metadata to cache
pub fn writeBuildMeta(allocator: std.mem.Allocator, meta: BuildMeta) !void {
    // Ensure cache directory exists
    const cache_dir = try config.expandPath(allocator, "~/.cache/nvfury/build-meta");
    defer allocator.free(cache_dir);

    const io = std.Options.debug_io;
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "mkdir", "-p", cache_dir },
    }) catch {};

    const cache_path = try getCachePath(allocator, meta.version);
    defer allocator.free(cache_path);

    const json = try meta.toJson(allocator);
    defer allocator.free(json);

    const fd = try std.posix.openat(std.posix.AT.FDCWD, cache_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer std.posix.close(fd);

    const write_result = std.c.write(fd, json.ptr, json.len);
    if (write_result < 0) return error.WriteError;
}

/// Check if a rebuild is needed
pub const CacheCheckResult = struct {
    /// Whether a rebuild is needed
    needs_rebuild: bool,
    /// Reason for rebuild (if needed)
    reason: Reason,
    /// Cached metadata (if available)
    cached_meta: ?BuildMeta,

    pub const Reason = enum {
        no_cache, // No cached build exists
        source_changed, // Source hash changed
        kernel_changed, // Different kernel version
        build_failed, // Previous build failed
        cache_valid, // Cache is valid, no rebuild needed
    };

    pub fn deinit(self: *CacheCheckResult, allocator: std.mem.Allocator) void {
        if (self.cached_meta) |*m| m.deinit(allocator);
        self.* = undefined;
    }
};

/// Check if source needs rebuilding
pub fn checkCache(allocator: std.mem.Allocator, version: []const u8, source_dir: []const u8, kernel_version: []const u8) !CacheCheckResult {
    // Read existing cache
    const cached = try readBuildMeta(allocator, version);
    if (cached == null) {
        return CacheCheckResult{
            .needs_rebuild = true,
            .reason = .no_cache,
            .cached_meta = null,
        };
    }

    var meta = cached.?;

    // Check if previous build failed
    if (!meta.success) {
        return CacheCheckResult{
            .needs_rebuild = true,
            .reason = .build_failed,
            .cached_meta = meta,
        };
    }

    // Check kernel version
    if (!std.mem.eql(u8, meta.kernel_version, kernel_version)) {
        return CacheCheckResult{
            .needs_rebuild = true,
            .reason = .kernel_changed,
            .cached_meta = meta,
        };
    }

    // Compute current source hash
    const current_hash = try computeSourceHash(allocator, source_dir);

    // Compare hashes
    if (!std.mem.eql(u8, &meta.source_hash, &current_hash)) {
        return CacheCheckResult{
            .needs_rebuild = true,
            .reason = .source_changed,
            .cached_meta = meta,
        };
    }

    // Cache is valid
    return CacheCheckResult{
        .needs_rebuild = false,
        .reason = .cache_valid,
        .cached_meta = meta,
    };
}

/// Check if built modules exist in output directory
pub fn hasBuiltModules(allocator: std.mem.Allocator, output_dir: []const u8) bool {
    const modules = [_][]const u8{
        "kernel-open/nvidia.ko",
        "kernel-open/nvidia-modeset.ko",
        "kernel-open/nvidia-uvm.ko",
        "kernel-open/nvidia-drm.ko",
    };

    for (modules) |module| {
        const module_path = std.fs.path.join(allocator, &.{ output_dir, module }) catch continue;
        defer allocator.free(module_path);

        const fd = std.posix.openat(std.posix.AT.FDCWD, module_path, .{}, 0) catch return false;
        std.posix.close(fd);
    }

    return true;
}

/// Clear all build cache
pub fn clearCache(allocator: std.mem.Allocator) !void {
    const cache_dir = try config.expandPath(allocator, "~/.cache/nvfury/build-meta");
    defer allocator.free(cache_dir);

    const io = std.Options.debug_io;
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "rm", "-rf", cache_dir },
    }) catch {};
}

/// Get cache status summary
pub const CacheStatus = struct {
    entries: u32,
    total_size: u64,
    versions: std.ArrayListUnmanaged([]const u8),

    pub fn deinit(self: *CacheStatus, allocator: std.mem.Allocator) void {
        for (self.versions.items) |v| allocator.free(v);
        self.versions.deinit(allocator);
        self.* = undefined;
    }
};

pub fn getCacheStatus(allocator: std.mem.Allocator) !CacheStatus {
    var status = CacheStatus{
        .entries = 0,
        .total_size = 0,
        .versions = .{},
    };

    const cache_dir = try config.expandPath(allocator, "~/.cache/nvfury/build-meta");
    defer allocator.free(cache_dir);

    const io = std.Options.debug_io;
    var dir = std.Io.Dir.openDirAbsolute(io, cache_dir, .{ .iterate = true }) catch return status;
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
            status.entries += 1;

            // Extract version from filename (remove .json)
            const version = entry.name[0 .. entry.name.len - 5];
            try status.versions.append(allocator, try allocator.dupe(u8, version));
        }
    }

    return status;
}

// JSON parsing helpers
fn parseJsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const key_pos = std.mem.indexOf(u8, json, key) orelse return allocator.dupe(u8, "");
    const after_key = json[key_pos + key.len ..];

    const colon_pos = std.mem.indexOfScalar(u8, after_key, ':') orelse return allocator.dupe(u8, "");
    const after_colon = after_key[colon_pos + 1 ..];

    const quote_start = std.mem.indexOfScalar(u8, after_colon, '"') orelse return allocator.dupe(u8, "");
    const value_start = after_colon[quote_start + 1 ..];

    const quote_end = std.mem.indexOfScalar(u8, value_start, '"') orelse return allocator.dupe(u8, "");

    return allocator.dupe(u8, value_start[0..quote_end]);
}

fn parseJsonInt(json: []const u8, key: []const u8) ?i64 {
    const key_pos = std.mem.indexOf(u8, json, key) orelse return null;
    const after_key = json[key_pos + key.len ..];

    const colon_pos = std.mem.indexOfScalar(u8, after_key, ':') orelse return null;
    const after_colon = std.mem.trim(u8, after_key[colon_pos + 1 ..], " \t\n\r");

    var num: i64 = 0;
    for (after_colon) |c| {
        if (std.ascii.isDigit(c)) {
            num = num * 10 + (c - '0');
        } else if (c != ' ' and c != '\t') {
            break;
        }
    }

    return num;
}

fn parseJsonBool(json: []const u8, key: []const u8) ?bool {
    const key_pos = std.mem.indexOf(u8, json, key) orelse return null;
    const after_key = json[key_pos + key.len ..];

    const colon_pos = std.mem.indexOfScalar(u8, after_key, ':') orelse return null;
    const after_colon = std.mem.trim(u8, after_key[colon_pos + 1 ..], " \t\n\r");

    if (std.mem.startsWith(u8, after_colon, "true")) return true;
    if (std.mem.startsWith(u8, after_colon, "false")) return false;

    return null;
}

test "build meta json roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var source_hash: [64]u8 = undefined;
    @memset(&source_hash, 'a');

    const meta = BuildMeta{
        .version = try allocator.dupe(u8, "590.48.01"),
        .source_hash = source_hash,
        .kernel_version = try allocator.dupe(u8, "6.18.4-273-tkg-linux-ghost"),
        .build_time = 1706200000,
        .compiler = try allocator.dupe(u8, "ccache clang"),
        .cflags = try allocator.dupe(u8, "-march=native -O3"),
        .success = true,
    };

    const json = try meta.toJson(allocator);
    var parsed = try BuildMeta.fromJson(allocator, json);
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("590.48.01", parsed.version);
    try std.testing.expectEqualStrings("6.18.4-273-tkg-linux-ghost", parsed.kernel_version);
    try std.testing.expect(parsed.success);
}
