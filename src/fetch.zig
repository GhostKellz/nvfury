//! nvfury/fetch - Source Fetching
//!
//! Downloads and manages NVIDIA open-gpu-kernel-modules source code.

const std = @import("std");
const config = @import("config.zig");

/// NVIDIA open-gpu-kernel-modules repository URL
pub const NVIDIA_OPEN_REPO = "https://github.com/NVIDIA/open-gpu-kernel-modules.git";

/// GitHub releases API endpoint
pub const NVIDIA_RELEASES_API = "https://api.github.com/repos/NVIDIA/open-gpu-kernel-modules/releases";

/// Fetch result
pub const FetchResult = struct {
    /// Path to fetched source
    source_path: []const u8,
    /// Version that was fetched
    version: []const u8,
    /// Whether this was from cache
    from_cache: bool,
};

/// Fetch options
pub const FetchOptions = struct {
    /// Specific version to fetch (null = latest)
    version: ?[]const u8 = null,
    /// Force re-fetch even if cached
    force: bool = false,
    /// Cache directory
    cache_dir: []const u8 = "~/.cache/nvfury/nvidia-open/",
};

/// Fetch NVIDIA open kernel module source
pub fn fetchSource(allocator: std.mem.Allocator, options: FetchOptions) !FetchResult {
    const cache_path = try config.expandPath(allocator, options.cache_dir);
    defer allocator.free(cache_path);

    // Determine version to fetch
    const target_version = options.version orelse try getLatestVersion(allocator);
    defer if (options.version == null) allocator.free(target_version);

    const version_path = try std.fs.path.join(allocator, &.{ cache_path, target_version });
    errdefer allocator.free(version_path);

    // Check if already cached
    if (!options.force) {
        if (std.fs.openDirAbsolute(version_path, .{})) |d| {
            var dir = d;
            dir.close();
            return FetchResult{
                .source_path = version_path,
                .version = try allocator.dupe(u8, target_version),
                .from_cache = true,
            };
        } else |_| {}
    }

    // Create cache directory (including parents)
    std.fs.cwd().makePath(cache_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Clone the repository at the specific tag
    try gitClone(allocator, NVIDIA_OPEN_REPO, version_path, target_version);

    return FetchResult{
        .source_path = version_path,
        .version = try allocator.dupe(u8, target_version),
        .from_cache = false,
    };
}

/// Get the latest release version from GitHub
pub fn getLatestVersion(allocator: std.mem.Allocator) ![]u8 {
    // Try to fetch from GitHub API using curl (simpler than HTTP client for now)
    if (fetchLatestVersionViaCurl(allocator)) |version| {
        return version;
    } else |err| {
        // Log the error but fall back to known good version
        std.log.warn("Failed to fetch latest version from GitHub: {}", .{err});
        return allocator.dupe(u8, "590.48.01");
    }
}

/// Fetch the latest release version using curl command
fn fetchLatestVersionViaCurl(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&.{
        "curl",
        "-s",
        "-H",
        "Accept: application/vnd.github+json",
        "-H",
        "User-Agent: nvfury/0.1.0",
        NVIDIA_RELEASES_API ++ "/latest",
    }, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read stdout - Zig 0.16 unmanaged ArrayList
    var stdout_data: std.ArrayListUnmanaged(u8) = .{};
    defer stdout_data.deinit(allocator);

    if (child.stdout) |stdout_pipe| {
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = stdout_pipe.read(&buf) catch break;
            if (n == 0) break;
            try stdout_data.appendSlice(allocator, buf[0..n]);
            if (stdout_data.items.len > 64 * 1024) break; // Limit size
        }
    }

    const term = try child.wait();
    if (term != .Exited or term.Exited != 0) {
        return error.CurlFailed;
    }

    // Parse JSON to find tag_name
    return parseTagName(allocator, stdout_data.items);
}

/// Parse the tag_name from GitHub release JSON
fn parseTagName(allocator: std.mem.Allocator, json_data: []const u8) ![]u8 {
    // Simple JSON parsing for "tag_name": "XXX.XX.XX"
    // GitHub releases use tag_name for version strings

    const tag_needle = "\"tag_name\":";
    const tag_pos = std.mem.indexOf(u8, json_data, tag_needle) orelse return error.TagNotFound;
    const after_tag = json_data[tag_pos + tag_needle.len ..];

    // Find opening quote
    const quote_start = std.mem.indexOfScalar(u8, after_tag, '"') orelse return error.InvalidJson;
    const value_start = after_tag[quote_start + 1 ..];

    // Find closing quote
    const quote_end = std.mem.indexOfScalar(u8, value_start, '"') orelse return error.InvalidJson;
    const version = value_start[0..quote_end];

    // Validate version format (should be like "590.48.01" or "580.105.08")
    if (!isValidDriverVersion(version)) {
        return error.InvalidVersion;
    }

    return allocator.dupe(u8, version);
}

/// Validate that a string looks like an NVIDIA driver version
fn isValidDriverVersion(version: []const u8) bool {
    // Version format: XXX.XX.XX or XXX.XXX.XX
    // e.g., "590.48.01", "580.105.08", "565.77"
    if (version.len < 6 or version.len > 12) return false;

    var dot_count: usize = 0;
    for (version) |c| {
        if (c == '.') {
            dot_count += 1;
        } else if (!std.ascii.isDigit(c)) {
            return false;
        }
    }

    // Should have 1 or 2 dots
    return dot_count >= 1 and dot_count <= 2;
}

/// Version list result - caller must free items and call deinit
pub const VersionList = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged([]const u8),

    pub fn deinit(self: *VersionList) void {
        for (self.items.items) |v| self.allocator.free(v);
        self.items.deinit(self.allocator);
    }
};

/// Get list of available versions from GitHub
pub fn getAvailableVersions(allocator: std.mem.Allocator) !VersionList {
    var versions: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer {
        for (versions.items) |v| allocator.free(v);
        versions.deinit(allocator);
    }

    // Try to fetch from GitHub API using curl
    if (fetchVersionsViaCurl(allocator, &versions)) {
        return VersionList{ .allocator = allocator, .items = versions };
    } else |err| {
        std.log.warn("Failed to fetch versions from GitHub: {}, using defaults", .{err});
        // Fall back to known versions
        const defaults = [_][]const u8{
            "590.48.01",
            "585.143.02",
            "580.105.08",
            "575.51.02",
            "570.86.16",
        };
        for (defaults) |v| {
            try versions.append(allocator, try allocator.dupe(u8, v));
        }
        return VersionList{ .allocator = allocator, .items = versions };
    }
}

/// Fetch available versions using curl command
fn fetchVersionsViaCurl(allocator: std.mem.Allocator, versions: *std.ArrayListUnmanaged([]const u8)) !void {
    var child = std.process.Child.init(&.{
        "curl",
        "-s",
        "-H",
        "Accept: application/vnd.github+json",
        "-H",
        "User-Agent: nvfury/0.1.0",
        NVIDIA_RELEASES_API,
    }, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read stdout - Zig 0.16 unmanaged ArrayList
    var stdout_data: std.ArrayListUnmanaged(u8) = .{};
    defer stdout_data.deinit(allocator);

    if (child.stdout) |stdout_pipe| {
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = stdout_pipe.read(&buf) catch break;
            if (n == 0) break;
            try stdout_data.appendSlice(allocator, buf[0..n]);
            if (stdout_data.items.len > 256 * 1024) break; // Limit size
        }
    }

    const term = try child.wait();
    if (term != .Exited or term.Exited != 0) {
        return error.CurlFailed;
    }

    // Parse all tag_name values from the JSON array
    try parseAllTagNames(allocator, stdout_data.items, versions);
}

/// Parse all tag_name values from a GitHub releases JSON array
fn parseAllTagNames(allocator: std.mem.Allocator, json_data: []const u8, versions: *std.ArrayListUnmanaged([]const u8)) !void {
    const tag_needle = "\"tag_name\":";
    var offset: usize = 0;

    while (std.mem.indexOfPos(u8, json_data, offset, tag_needle)) |pos| {
        const after_tag = json_data[pos + tag_needle.len ..];

        // Find opening quote
        const quote_start = std.mem.indexOfScalar(u8, after_tag, '"') orelse break;
        const value_start = after_tag[quote_start + 1 ..];

        // Find closing quote
        const quote_end = std.mem.indexOfScalar(u8, value_start, '"') orelse break;
        const version = value_start[0..quote_end];

        // Validate and add if it's a valid driver version
        if (isValidDriverVersion(version)) {
            try versions.append(allocator, try allocator.dupe(u8, version));
        }

        // Move past this occurrence
        offset = pos + tag_needle.len + quote_start + 1 + quote_end + 1;

        // Limit to 20 versions
        if (versions.items.len >= 20) break;
    }

    if (versions.items.len == 0) {
        return error.NoVersionsFound;
    }
}

/// Clone a git repository at a specific tag
fn gitClone(allocator: std.mem.Allocator, repo_url: []const u8, dest_path: []const u8, tag: []const u8) !void {
    const tag_ref = try std.fmt.allocPrint(allocator, "refs/tags/{s}", .{tag});
    defer allocator.free(tag_ref);

    var child = std.process.Child.init(&.{
        "git",
        "clone",
        "--depth",
        "1",
        "--branch",
        tag,
        repo_url,
        dest_path,
    }, allocator);
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const term = try child.spawnAndWait();
    if (term != .Exited or term.Exited != 0) {
        return error.GitCloneFailed;
    }
}

/// Check if a specific version is cached
pub fn isCached(allocator: std.mem.Allocator, version: []const u8, cache_dir: []const u8) !bool {
    const cache_path = try config.expandPath(allocator, cache_dir);
    defer allocator.free(cache_path);

    const version_path = try std.fs.path.join(allocator, &.{ cache_path, version });
    defer allocator.free(version_path);

    if (std.fs.openDirAbsolute(version_path, .{})) |d| {
        var dir = d;
        dir.close();
        return true;
    } else |_| {
        return false;
    }
}

/// Static buffer for driver version (valid for lifetime of program)
var driver_version_buf: [64]u8 = undefined;
var driver_version_len: usize = 0;

/// Get detected driver version from system
pub fn getInstalledDriverVersion() ?[]const u8 {
    // Try to read from /sys/module/nvidia/version
    const file = std.fs.openFileAbsolute("/sys/module/nvidia/version", .{}) catch {
        return null;
    };
    defer file.close();

    driver_version_len = 0;

    // Read until buffer full or EOF
    while (driver_version_len < driver_version_buf.len) {
        const len = file.read(driver_version_buf[driver_version_len..]) catch return null;
        if (len == 0) break;
        driver_version_len += len;
    }

    if (driver_version_len == 0) return null;

    // Trim newline
    while (driver_version_len > 0 and (driver_version_buf[driver_version_len - 1] == '\n' or driver_version_buf[driver_version_len - 1] == '\r')) {
        driver_version_len -= 1;
    }

    return driver_version_buf[0..driver_version_len];
}

test "fetch module" {
    // Basic compilation test
    _ = FetchOptions{};
    _ = FetchResult{
        .source_path = "/test",
        .version = "580.105.08",
        .from_cache = true,
    };
}

test "version validation" {
    const testing = std.testing;
    try testing.expect(isValidDriverVersion("590.48.01"));
    try testing.expect(isValidDriverVersion("580.105.08"));
    try testing.expect(isValidDriverVersion("565.77"));
    try testing.expect(!isValidDriverVersion("invalid"));
    try testing.expect(!isValidDriverVersion(""));
    try testing.expect(!isValidDriverVersion("abc.def.ghi"));
}
