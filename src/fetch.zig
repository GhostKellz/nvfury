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
        // Try to open the directory to see if it exists
        const fd = std.posix.openat(std.posix.AT.FDCWD, version_path, .{ .DIRECTORY = true }, 0) catch null;
        if (fd) |f| {
            std.posix.close(f);
            return FetchResult{
                .source_path = version_path,
                .version = try allocator.dupe(u8, target_version),
                .from_cache = true,
            };
        }
    }

    // Create cache directory using mkdir -p via shell
    const io = std.Options.debug_io;
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "mkdir", "-p", cache_path },
    }) catch {};

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
    const io = std.Options.debug_io;
    const result = std.process.run(allocator, io, .{
        .argv = &.{
            "curl",
            "-s",
            "-H",
            "Accept: application/vnd.github+json",
            "-H",
            "User-Agent: nvfury/0.1.0",
            NVIDIA_RELEASES_API ++ "/latest",
        },
    }) catch return error.CurlFailed;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        return error.CurlFailed;
    }

    // Parse JSON to find tag_name
    return parseTagName(allocator, result.stdout);
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
    const io = std.Options.debug_io;
    const result = std.process.run(allocator, io, .{
        .argv = &.{
            "curl",
            "-s",
            "-H",
            "Accept: application/vnd.github+json",
            "-H",
            "User-Agent: nvfury/0.1.0",
            NVIDIA_RELEASES_API,
        },
    }) catch return error.CurlFailed;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        return error.CurlFailed;
    }

    // Parse all tag_name values from the JSON array
    try parseAllTagNames(allocator, result.stdout, versions);
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
    _ = allocator;
    const io = std.Options.debug_io;
    var child = std.process.spawn(io, .{
        .argv = &.{
            "git",
            "clone",
            "--depth",
            "1",
            "--branch",
            tag,
            repo_url,
            dest_path,
        },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch return error.GitCloneFailed;

    const term = child.wait(io) catch return error.GitCloneFailed;
    if (term != .exited or term.exited != 0) {
        return error.GitCloneFailed;
    }
}

/// Check if a specific version is cached
pub fn isCached(allocator: std.mem.Allocator, version: []const u8, cache_dir: []const u8) !bool {
    const cache_path = try config.expandPath(allocator, cache_dir);
    defer allocator.free(cache_path);

    const version_path = try std.fs.path.join(allocator, &.{ cache_path, version });
    defer allocator.free(version_path);

    // Try to open the directory to check if it exists
    const fd = std.posix.openat(std.posix.AT.FDCWD, version_path, .{ .DIRECTORY = true }, 0) catch return false;
    std.posix.close(fd);
    return true;
}

/// Static buffer for driver version (valid for lifetime of program)
var driver_version_buf: [64]u8 = undefined;
var driver_version_len: usize = 0;

/// Get detected driver version from system
pub fn getInstalledDriverVersion() ?[]const u8 {
    // Try to read from /sys/module/nvidia/version using posix
    const fd = std.posix.openat(std.posix.AT.FDCWD, "/sys/module/nvidia/version", .{}, 0) catch {
        return null;
    };
    defer std.posix.close(fd);

    driver_version_len = 0;

    // Read until buffer full or EOF
    while (driver_version_len < driver_version_buf.len) {
        const len = std.posix.read(fd, driver_version_buf[driver_version_len..]) catch return null;
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

/// Parse a version string into numeric components for comparison
/// Returns null if the version is invalid
pub fn parseVersion(version: []const u8) ?struct { major: u32, minor: u32, patch: u32 } {
    var parts: [3]u32 = .{ 0, 0, 0 };
    var part_idx: usize = 0;
    var current: u32 = 0;

    for (version) |c| {
        if (c == '.') {
            if (part_idx >= 2) return null;
            parts[part_idx] = current;
            part_idx += 1;
            current = 0;
        } else if (std.ascii.isDigit(c)) {
            current = current * 10 + (c - '0');
        } else {
            return null;
        }
    }
    parts[part_idx] = current;

    return .{
        .major = parts[0],
        .minor = parts[1],
        .patch = parts[2],
    };
}

/// Compare two version strings
/// Returns: -1 if a < b, 0 if a == b, 1 if a > b
pub fn compareVersions(a: []const u8, b: []const u8) i32 {
    const va = parseVersion(a) orelse return 0;
    const vb = parseVersion(b) orelse return 0;

    if (va.major < vb.major) return -1;
    if (va.major > vb.major) return 1;
    if (va.minor < vb.minor) return -1;
    if (va.minor > vb.minor) return 1;
    if (va.patch < vb.patch) return -1;
    if (va.patch > vb.patch) return 1;
    return 0;
}

/// Check if an update is available
pub const UpdateCheckResult = struct {
    update_available: bool,
    installed_version: ?[]const u8,
    latest_version: []const u8,
    is_newer: bool,
};

/// Check for available updates
pub fn checkForUpdate(allocator: std.mem.Allocator) !UpdateCheckResult {
    const installed = getInstalledDriverVersion();
    const latest = try getLatestVersion(allocator);

    const is_newer = if (installed) |inst|
        compareVersions(latest, inst) > 0
    else
        true;

    return UpdateCheckResult{
        .update_available = is_newer,
        .installed_version = installed,
        .latest_version = latest,
        .is_newer = is_newer,
    };
}

/// Get update info as formatted string (caller must free)
pub fn getUpdateInfo(allocator: std.mem.Allocator) ![]u8 {
    const result = try checkForUpdate(allocator);
    defer allocator.free(result.latest_version);

    if (result.installed_version) |installed| {
        if (result.update_available) {
            return std.fmt.allocPrint(allocator,
                \\Update available!
                \\  Installed: {s}
                \\  Latest:    {s}
                \\
                \\Run 'nvfury build --latest' to build the new version.
            , .{ installed, result.latest_version });
        } else {
            return std.fmt.allocPrint(allocator,
                \\You're up to date!
                \\  Installed: {s}
                \\  Latest:    {s}
            , .{ installed, result.latest_version });
        }
    } else {
        return std.fmt.allocPrint(allocator,
            \\No NVIDIA driver detected.
            \\  Latest available: {s}
            \\
            \\Run 'nvfury build --latest' to build the driver.
        , .{result.latest_version});
    }
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

test "version parsing" {
    const testing = std.testing;

    const v1 = parseVersion("590.48.01").?;
    try testing.expectEqual(@as(u32, 590), v1.major);
    try testing.expectEqual(@as(u32, 48), v1.minor);
    try testing.expectEqual(@as(u32, 1), v1.patch);

    const v2 = parseVersion("580.105.08").?;
    try testing.expectEqual(@as(u32, 580), v2.major);
    try testing.expectEqual(@as(u32, 105), v2.minor);
    try testing.expectEqual(@as(u32, 8), v2.patch);
}

test "version comparison" {
    const testing = std.testing;
    try testing.expectEqual(@as(i32, 1), compareVersions("590.48.01", "580.105.08"));
    try testing.expectEqual(@as(i32, -1), compareVersions("580.105.08", "590.48.01"));
    try testing.expectEqual(@as(i32, 0), compareVersions("590.48.01", "590.48.01"));
    try testing.expectEqual(@as(i32, 1), compareVersions("590.48.02", "590.48.01"));
}
