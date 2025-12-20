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

    // Create cache directory
    std.fs.makeDirAbsolute(cache_path) catch |err| switch (err) {
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
    // For now, return the known latest stable version with GSP support
    // TODO: Actually query GitHub API
    return allocator.dupe(u8, "590.48.01");
}

/// Get list of available versions
pub fn getAvailableVersions(allocator: std.mem.Allocator) ![][]const u8 {
    // TODO: Query GitHub API for releases
    _ = allocator;
    return &[_][]const u8{
        "580.105.08",
        "575.51.02",
        "570.86.16",
        "565.77",
        "560.35.03",
    };
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

    _ = try child.spawnAndWait();
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
