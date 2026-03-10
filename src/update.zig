//! nvfury/update - Automatic Update Checking
//!
//! Monitors NVIDIA GitHub releases and notifies when updates are available.
//! Supports systemd timer integration and desktop notifications.

const std = @import("std");
const fetch = @import("fetch.zig");
const config = @import("config.zig");

/// Update check result stored in cache
pub const UpdateCache = struct {
    /// Last check timestamp (unix seconds)
    last_check: i64,
    /// Latest version found
    latest_version: []const u8,
    /// Installed version at time of check
    installed_version: []const u8,
    /// Whether update was available
    update_available: bool,

    /// Serialize to JSON for caching
    pub fn toJson(self: UpdateCache, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "{\n");
        try buf.appendSlice(allocator, "  \"last_check\": ");
        var num_buf: [32]u8 = undefined;
        const ts_str = std.fmt.bufPrint(&num_buf, "{d}", .{self.last_check}) catch unreachable;
        try buf.appendSlice(allocator, ts_str);
        try buf.appendSlice(allocator, ",\n");

        try buf.appendSlice(allocator, "  \"latest_version\": \"");
        try buf.appendSlice(allocator, self.latest_version);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"installed_version\": \"");
        try buf.appendSlice(allocator, self.installed_version);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"update_available\": ");
        try buf.appendSlice(allocator, if (self.update_available) "true" else "false");
        try buf.appendSlice(allocator, "\n}\n");

        return buf.toOwnedSlice(allocator);
    }

    /// Parse from JSON
    pub fn fromJson(allocator: std.mem.Allocator, json: []const u8) !UpdateCache {
        const latest = try parseJsonString(allocator, json, "\"latest_version\"");
        errdefer allocator.free(latest);

        const installed = try parseJsonString(allocator, json, "\"installed_version\"");
        errdefer allocator.free(installed);

        return UpdateCache{
            .last_check = @intCast(parseJsonInt(json, "\"last_check\"") orelse 0),
            .latest_version = latest,
            .installed_version = installed,
            .update_available = parseJsonBool(json, "\"update_available\"") orelse false,
        };
    }

    pub fn deinit(self: *UpdateCache, allocator: std.mem.Allocator) void {
        allocator.free(self.latest_version);
        allocator.free(self.installed_version);
        self.* = undefined;
    }
};

/// Path to the update check cache file
pub const cache_file = "~/.cache/nvfury/update-check.json";

/// Path to the last notification timestamp
pub const notify_file = "~/.cache/nvfury/last-notify";

/// Default check interval in seconds (12 hours)
pub const default_check_interval: i64 = 12 * 60 * 60;

/// Read cached update check result
pub fn readCache(allocator: std.mem.Allocator) !?UpdateCache {
    const expanded_path = try config.expandPath(allocator, cache_file);
    defer allocator.free(expanded_path);

    const fd = std.posix.openat(std.posix.AT.FDCWD, expanded_path, .{}, 0) catch return null;
    defer _ = std.c.close(fd);

    // Get file size
    const size_i64 = std.c.lseek64(fd, 0, 2); // SEEK_END
    if (size_i64 < 0 or size_i64 > 8192) return null;
    _ = std.c.lseek64(fd, 0, 0); // SEEK_SET
    const size: usize = @intCast(size_i64);

    const content = try allocator.alloc(u8, size);
    defer allocator.free(content);

    var total_read: usize = 0;
    while (total_read < size) {
        const n = std.posix.read(fd, content[total_read..]) catch return null;
        if (n == 0) break;
        total_read += n;
    }

    return try UpdateCache.fromJson(allocator, content[0..total_read]);
}

/// Write update check result to cache
pub fn writeCache(allocator: std.mem.Allocator, cache: UpdateCache) !void {
    const expanded_path = try config.expandPath(allocator, cache_file);
    defer allocator.free(expanded_path);

    // Ensure directory exists
    const cache_dir = try config.expandPath(allocator, "~/.cache/nvfury");
    defer allocator.free(cache_dir);

    const io = std.Options.debug_io;
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "mkdir", "-p", cache_dir },
    }) catch {};

    const json = try cache.toJson(allocator);
    defer allocator.free(json);

    const fd = try std.posix.openat(std.posix.AT.FDCWD, expanded_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer _ = std.c.close(fd);

    const write_result = std.c.write(fd, json.ptr, json.len);
    if (write_result < 0) return error.WriteError;
}

/// Perform an update check and cache the result
pub fn checkAndCache(allocator: std.mem.Allocator) !UpdateCache {
    const result = try fetch.checkForUpdate(allocator);

    // Get current timestamp
    var ts: std.os.linux.timespec = .{ .sec = 0, .nsec = 0 };
    _ = std.os.linux.clock_gettime(.REALTIME, &ts);

    const cache = UpdateCache{
        .last_check = ts.sec,
        .latest_version = result.latest_version,
        .installed_version = try allocator.dupe(u8, result.installed_version orelse "none"),
        .update_available = result.update_available,
    };

    try writeCache(allocator, cache);

    return cache;
}

/// Check if enough time has passed since last check
pub fn shouldCheck(allocator: std.mem.Allocator, interval: i64) !bool {
    const cached = try readCache(allocator);
    if (cached == null) return true;

    var c = cached.?;
    defer c.deinit(allocator);

    var ts: std.os.linux.timespec = undefined;
    if (std.os.linux.clock_gettime(.REALTIME, &ts) != 0) return true;
    const now = ts.sec;

    return (now - c.last_check) >= interval;
}

/// Send desktop notification using notify-send
pub fn sendNotification(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !void {
    const io = std.Options.debug_io;
    _ = std.process.run(allocator, io, .{
        .argv = &.{
            "notify-send",
            "--app-name=nvfury",
            "--urgency=normal",
            "--icon=nvidia-settings",
            title,
            message,
        },
    }) catch return error.NotificationFailed;
}

/// Check for updates and optionally notify
pub fn checkWithNotify(allocator: std.mem.Allocator, force: bool) !UpdateCache {
    // Check if we should run
    if (!force) {
        const should = try shouldCheck(allocator, default_check_interval);
        if (!should) {
            // Return cached result
            if (try readCache(allocator)) |c| {
                return c;
            }
        }
    }

    // Perform the check
    var cache = try checkAndCache(allocator);

    // Send notification if update available
    if (cache.update_available) {
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "New driver available: {s}\nInstalled: {s}\nRun 'nvfury build --latest' to update.", .{
            cache.latest_version,
            cache.installed_version,
        }) catch "New driver version available!";

        sendNotification(allocator, "NVIDIA Driver Update", msg) catch {
            // Notification failed, but update check succeeded
        };
    }

    return cache;
}

/// Systemd service unit content
pub const systemd_service =
    \\[Unit]
    \\Description=nvfury NVIDIA driver update checker
    \\Documentation=https://github.com/GhostKellz/nvfury
    \\After=network-online.target
    \\Wants=network-online.target
    \\
    \\[Service]
    \\Type=oneshot
    \\ExecStart=/usr/bin/nvfury check-update --notify
    \\User=%i
    \\
    \\[Install]
    \\WantedBy=default.target
    \\
;

/// Systemd timer unit content
pub const systemd_timer =
    \\[Unit]
    \\Description=Check for NVIDIA driver updates every 12 hours
    \\Documentation=https://github.com/GhostKellz/nvfury
    \\
    \\[Timer]
    \\OnBootSec=5min
    \\OnUnitActiveSec=12h
    \\Persistent=true
    \\RandomizedDelaySec=30min
    \\
    \\[Install]
    \\WantedBy=timers.target
    \\
;

/// Install systemd timer for automatic update checks
pub fn installTimer(allocator: std.mem.Allocator, writer: *std.Io.Writer) !bool {
    const io = std.Options.debug_io;

    // Get user's systemd directory
    const user_systemd_dir = try config.expandPath(allocator, "~/.config/systemd/user");
    defer allocator.free(user_systemd_dir);

    // Create directory
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "mkdir", "-p", user_systemd_dir },
    }) catch {};

    // Write service file
    const service_path = try std.fmt.allocPrint(allocator, "{s}/nvfury-update.service", .{user_systemd_dir});
    defer allocator.free(service_path);

    const service_fd = std.posix.openat(std.posix.AT.FDCWD, service_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return false;
    _ = std.c.write(service_fd, systemd_service.ptr, systemd_service.len);
    _ = std.c.close(service_fd);

    // Write timer file
    const timer_path = try std.fmt.allocPrint(allocator, "{s}/nvfury-update.timer", .{user_systemd_dir});
    defer allocator.free(timer_path);

    const timer_fd = std.posix.openat(std.posix.AT.FDCWD, timer_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return false;
    _ = std.c.write(timer_fd, systemd_timer.ptr, systemd_timer.len);
    _ = std.c.close(timer_fd);

    try writer.print("Created: {s}\n", .{service_path});
    try writer.print("Created: {s}\n", .{timer_path});

    // Reload systemd
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "systemctl", "--user", "daemon-reload" },
    }) catch {};

    // Enable and start timer
    const enable_result = std.process.run(allocator, io, .{
        .argv = &.{ "systemctl", "--user", "enable", "--now", "nvfury-update.timer" },
    }) catch return false;
    allocator.free(enable_result.stdout);
    allocator.free(enable_result.stderr);

    return enable_result.term == .exited and enable_result.term.exited == 0;
}

/// Remove systemd timer
pub fn removeTimer(allocator: std.mem.Allocator, writer: *std.Io.Writer) !bool {
    const io = std.Options.debug_io;

    // Stop and disable timer
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "systemctl", "--user", "disable", "--now", "nvfury-update.timer" },
    }) catch {};

    // Get user's systemd directory
    const user_systemd_dir = try config.expandPath(allocator, "~/.config/systemd/user");
    defer allocator.free(user_systemd_dir);

    // Remove files
    const service_path = try std.fmt.allocPrint(allocator, "{s}/nvfury-update.service", .{user_systemd_dir});
    defer allocator.free(service_path);

    const timer_path = try std.fmt.allocPrint(allocator, "{s}/nvfury-update.timer", .{user_systemd_dir});
    defer allocator.free(timer_path);

    _ = std.process.run(allocator, io, .{
        .argv = &.{ "rm", "-f", service_path, timer_path },
    }) catch {};

    try writer.print("Removed: {s}\n", .{service_path});
    try writer.print("Removed: {s}\n", .{timer_path});

    // Reload systemd
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "systemctl", "--user", "daemon-reload" },
    }) catch {};

    return true;
}

/// Get timer status
pub fn getTimerStatus(allocator: std.mem.Allocator) !TimerStatus {
    const io = std.Options.debug_io;

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "systemctl", "--user", "is-active", "nvfury-update.timer" },
    }) catch return TimerStatus{ .enabled = false, .active = false, .next_run = null };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const is_active = result.term == .exited and result.term.exited == 0;

    // Get next run time
    var next_run: ?[]u8 = null;
    if (is_active) {
        const status_result = std.process.run(allocator, io, .{
            .argv = &.{ "systemctl", "--user", "show", "nvfury-update.timer", "--property=NextElapseUSecRealtime", "--value" },
        }) catch null;

        if (status_result) |sr| {
            defer allocator.free(sr.stderr);
            if (sr.term == .exited and sr.term.exited == 0 and sr.stdout.len > 0) {
                // Parse and format the timestamp
                var end = sr.stdout.len;
                while (end > 0 and (sr.stdout[end - 1] == '\n' or sr.stdout[end - 1] == '\r')) {
                    end -= 1;
                }
                if (end > 0) {
                    next_run = try allocator.dupe(u8, sr.stdout[0..end]);
                }
            } else {
                allocator.free(sr.stdout);
            }
        }
    }

    return TimerStatus{
        .enabled = is_active,
        .active = is_active,
        .next_run = next_run,
    };
}

pub const TimerStatus = struct {
    enabled: bool,
    active: bool,
    next_run: ?[]u8,

    pub fn deinit(self: *TimerStatus, allocator: std.mem.Allocator) void {
        if (self.next_run) |nr| allocator.free(nr);
        self.* = undefined;
    }
};

/// Format a duration in human-readable form
pub fn formatDuration(seconds: i64, buf: []u8) []const u8 {
    if (seconds < 60) {
        return std.fmt.bufPrint(buf, "{d} seconds ago", .{seconds}) catch "just now";
    } else if (seconds < 3600) {
        return std.fmt.bufPrint(buf, "{d} minutes ago", .{@divTrunc(seconds, 60)}) catch "minutes ago";
    } else if (seconds < 86400) {
        return std.fmt.bufPrint(buf, "{d} hours ago", .{@divTrunc(seconds, 3600)}) catch "hours ago";
    } else {
        return std.fmt.bufPrint(buf, "{d} days ago", .{@divTrunc(seconds, 86400)}) catch "days ago";
    }
}

// JSON parsing helpers (duplicated from config.zig to avoid circular deps)
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

test "update cache json roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cache = UpdateCache{
        .last_check = 1706200000,
        .latest_version = try allocator.dupe(u8, "590.48.01"),
        .installed_version = try allocator.dupe(u8, "585.143.02"),
        .update_available = true,
    };

    const json = try cache.toJson(allocator);
    var parsed = try UpdateCache.fromJson(allocator, json);
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("590.48.01", parsed.latest_version);
    try std.testing.expectEqualStrings("585.143.02", parsed.installed_version);
    try std.testing.expect(parsed.update_available);
}
