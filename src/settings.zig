//! nvfury/settings - Configuration Management
//!
//! Manages nvfury configuration including patches directory, pinned versions,
//! and other user preferences.

const std = @import("std");
const config = @import("config.zig");

/// Configuration file path
pub const config_path = "~/.config/nvfury/config.json";

/// Default patches directory
pub const default_patches_dir = "/usr/share/nvfury/patches";

/// User patches directory
pub const user_patches_dir = "~/.config/nvfury/patches";

/// Configuration settings
pub const Settings = struct {
    /// Patches directory (can be overridden)
    patches_dir: []const u8 = default_patches_dir,
    /// User patches directory
    user_patches_dir: []const u8 = user_patches_dir,
    /// Pinned driver version (null = use latest)
    pinned_version: ?[]const u8 = null,
    /// Auto-update check enabled
    auto_update_check: bool = true,
    /// Desktop notifications enabled
    notifications: bool = true,
    /// Default tune preset
    default_preset: []const u8 = "gaming",
    /// Sign modules for SecureBoot
    sign_modules: bool = false,
    /// DKMS enabled by default
    use_dkms: bool = true,
    /// Extra CFLAGS for builds
    extra_cflags: []const u8 = "",
    /// Custom compiler (null = auto-detect)
    compiler: ?[]const u8 = null,

    // Memory management
    allocator: ?std.mem.Allocator = null,
    owns_strings: bool = false,

    /// Load settings from file
    pub fn load(allocator: std.mem.Allocator) !Settings {
        const expanded_path = try config.expandPath(allocator, config_path);
        defer allocator.free(expanded_path);

        const fd = std.posix.openat(std.posix.AT.FDCWD, expanded_path, .{}, 0) catch {
            // Return defaults if no config file
            return Settings{
                .allocator = allocator,
                .owns_strings = false,
            };
        };
        defer _ = std.c.close(fd);

        // Get file size
        const size_i64 = std.c.lseek64(fd, 0, 2);
        if (size_i64 < 0 or size_i64 > 65536) return Settings{ .allocator = allocator };
        _ = std.c.lseek64(fd, 0, 0);
        const size: usize = @intCast(size_i64);

        const content = try allocator.alloc(u8, size);
        defer allocator.free(content);

        var total_read: usize = 0;
        while (total_read < size) {
            const n = std.posix.read(fd, content[total_read..]) catch return Settings{ .allocator = allocator };
            if (n == 0) break;
            total_read += n;
        }

        return try Settings.fromJson(allocator, content[0..total_read]);
    }

    /// Parse settings from JSON
    pub fn fromJson(allocator: std.mem.Allocator, json: []const u8) !Settings {
        var settings = Settings{
            .allocator = allocator,
            .owns_strings = true,
        };

        // Parse patches_dir
        if (parseJsonString(allocator, json, "\"patches_dir\"")) |pd| {
            settings.patches_dir = pd;
        } else |_| {
            settings.patches_dir = try allocator.dupe(u8, default_patches_dir);
        }

        // Parse user_patches_dir
        if (parseJsonString(allocator, json, "\"user_patches_dir\"")) |upd| {
            settings.user_patches_dir = upd;
        } else |_| {
            settings.user_patches_dir = try allocator.dupe(u8, user_patches_dir);
        }

        // Parse pinned_version
        if (parseJsonString(allocator, json, "\"pinned_version\"")) |pv| {
            if (pv.len > 0 and !std.mem.eql(u8, pv, "null")) {
                settings.pinned_version = pv;
            } else {
                allocator.free(pv);
            }
        } else |_| {}

        // Parse booleans
        settings.auto_update_check = parseJsonBool(json, "\"auto_update_check\"") orelse true;
        settings.notifications = parseJsonBool(json, "\"notifications\"") orelse true;
        settings.sign_modules = parseJsonBool(json, "\"sign_modules\"") orelse false;
        settings.use_dkms = parseJsonBool(json, "\"use_dkms\"") orelse true;

        // Parse default_preset
        if (parseJsonString(allocator, json, "\"default_preset\"")) |dp| {
            settings.default_preset = dp;
        } else |_| {
            settings.default_preset = try allocator.dupe(u8, "gaming");
        }

        // Parse extra_cflags
        if (parseJsonString(allocator, json, "\"extra_cflags\"")) |cf| {
            settings.extra_cflags = cf;
        } else |_| {
            settings.extra_cflags = try allocator.dupe(u8, "");
        }

        // Parse compiler
        if (parseJsonString(allocator, json, "\"compiler\"")) |cc| {
            if (cc.len > 0 and !std.mem.eql(u8, cc, "null")) {
                settings.compiler = cc;
            } else {
                allocator.free(cc);
            }
        } else |_| {}

        return settings;
    }

    /// Save settings to file
    pub fn save(self: Settings, allocator: std.mem.Allocator) !void {
        const json = try self.toJson(allocator);
        defer allocator.free(json);

        // Ensure directory exists
        const config_dir = try config.expandPath(allocator, "~/.config/nvfury");
        defer allocator.free(config_dir);

        const io = std.Options.debug_io;
        _ = std.process.run(allocator, io, .{
            .argv = &.{ "mkdir", "-p", config_dir },
        }) catch {};

        const expanded_path = try config.expandPath(allocator, config_path);
        defer allocator.free(expanded_path);

        const fd = try std.posix.openat(std.posix.AT.FDCWD, expanded_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        defer _ = std.c.close(fd);

        const write_result = std.c.write(fd, json.ptr, json.len);
        if (write_result < 0) return error.WriteError;
    }

    /// Export to JSON
    pub fn toJson(self: Settings, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "{\n");

        try buf.appendSlice(allocator, "  \"patches_dir\": \"");
        try buf.appendSlice(allocator, self.patches_dir);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"user_patches_dir\": \"");
        try buf.appendSlice(allocator, self.user_patches_dir);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"pinned_version\": ");
        if (self.pinned_version) |pv| {
            try buf.appendSlice(allocator, "\"");
            try buf.appendSlice(allocator, pv);
            try buf.appendSlice(allocator, "\"");
        } else {
            try buf.appendSlice(allocator, "null");
        }
        try buf.appendSlice(allocator, ",\n");

        try buf.appendSlice(allocator, "  \"auto_update_check\": ");
        try buf.appendSlice(allocator, if (self.auto_update_check) "true" else "false");
        try buf.appendSlice(allocator, ",\n");

        try buf.appendSlice(allocator, "  \"notifications\": ");
        try buf.appendSlice(allocator, if (self.notifications) "true" else "false");
        try buf.appendSlice(allocator, ",\n");

        try buf.appendSlice(allocator, "  \"sign_modules\": ");
        try buf.appendSlice(allocator, if (self.sign_modules) "true" else "false");
        try buf.appendSlice(allocator, ",\n");

        try buf.appendSlice(allocator, "  \"use_dkms\": ");
        try buf.appendSlice(allocator, if (self.use_dkms) "true" else "false");
        try buf.appendSlice(allocator, ",\n");

        try buf.appendSlice(allocator, "  \"default_preset\": \"");
        try buf.appendSlice(allocator, self.default_preset);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"extra_cflags\": \"");
        try buf.appendSlice(allocator, self.extra_cflags);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"compiler\": ");
        if (self.compiler) |cc| {
            try buf.appendSlice(allocator, "\"");
            try buf.appendSlice(allocator, cc);
            try buf.appendSlice(allocator, "\"");
        } else {
            try buf.appendSlice(allocator, "null");
        }
        try buf.appendSlice(allocator, "\n");

        try buf.appendSlice(allocator, "}\n");

        return buf.toOwnedSlice(allocator);
    }

    /// Free allocated strings
    pub fn deinit(self: *Settings) void {
        if (self.owns_strings) {
            if (self.allocator) |alloc| {
                alloc.free(self.patches_dir);
                alloc.free(self.user_patches_dir);
                if (self.pinned_version) |pv| alloc.free(pv);
                alloc.free(self.default_preset);
                alloc.free(self.extra_cflags);
                if (self.compiler) |cc| alloc.free(cc);
            }
        }
        self.* = undefined;
    }

    /// Get the effective patches directory (user override or default)
    pub fn getPatchesDir(self: Settings, allocator: std.mem.Allocator) ![]u8 {
        return config.expandPath(allocator, self.patches_dir);
    }
};

/// Get effective patches directory, checking multiple locations
pub fn findPatchesDir(allocator: std.mem.Allocator) ![]u8 {
    // Priority order:
    // 1. Config setting
    // 2. User directory (~/.config/nvfury/patches)
    // 3. System directory (/usr/share/nvfury/patches)
    // 4. Source directory (relative to binary)

    var settings = Settings.load(allocator) catch Settings{};
    defer if (settings.owns_strings) settings.deinit();

    // Try config setting first
    if (settings.getPatchesDir(allocator)) |dir| {
        if (std.posix.openat(std.posix.AT.FDCWD, dir, .{ .DIRECTORY = true }, 0)) |fd| {
            _ = std.c.close(fd);
            return dir;
        } else |_| {
            allocator.free(dir);
            // Continue to try other locations
        }
    } else |_| {
        // No config setting, continue
    }

    // Try user directory
    const user_dir = try config.expandPath(allocator, user_patches_dir);
    if (std.posix.openat(std.posix.AT.FDCWD, user_dir, .{ .DIRECTORY = true }, 0)) |fd| {
        _ = std.c.close(fd);
        return user_dir;
    } else |_| {
        allocator.free(user_dir);
        // Continue to try system directory
    }

    return trySystemPatches(allocator);
}

fn trySystemPatches(allocator: std.mem.Allocator) ![]u8 {
    // Try system directory
    const fd = std.posix.openat(std.posix.AT.FDCWD, default_patches_dir, .{ .DIRECTORY = true }, 0) catch {
        // Fall back to empty (no patches)
        return allocator.dupe(u8, "");
    };
    _ = std.c.close(fd);
    return allocator.dupe(u8, default_patches_dir);
}

/// Print current settings
pub fn printSettings(allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    var settings = try Settings.load(allocator);
    defer if (settings.owns_strings) settings.deinit();

    try writer.print("nvfury Configuration\n\n", .{});

    const expanded_path = try config.expandPath(allocator, config_path);
    defer allocator.free(expanded_path);
    try writer.print("Config file: {s}\n\n", .{expanded_path});

    try writer.print("  patches_dir:       {s}\n", .{settings.patches_dir});
    try writer.print("  user_patches_dir:  {s}\n", .{settings.user_patches_dir});
    try writer.print("  pinned_version:    {s}\n", .{settings.pinned_version orelse "(none - use latest)"});
    try writer.print("  auto_update_check: {}\n", .{settings.auto_update_check});
    try writer.print("  notifications:     {}\n", .{settings.notifications});
    try writer.print("  sign_modules:      {}\n", .{settings.sign_modules});
    try writer.print("  use_dkms:          {}\n", .{settings.use_dkms});
    try writer.print("  default_preset:    {s}\n", .{settings.default_preset});
    try writer.print("  extra_cflags:      {s}\n", .{if (settings.extra_cflags.len > 0) settings.extra_cflags else "(none)"});
    try writer.print("  compiler:          {s}\n", .{settings.compiler orelse "(auto-detect)"});
}

/// Set a configuration value
pub fn setValue(allocator: std.mem.Allocator, key: []const u8, value: []const u8, writer: *std.Io.Writer) !bool {
    var settings = try Settings.load(allocator);

    // Update the appropriate field
    if (std.mem.eql(u8, key, "patches_dir")) {
        if (settings.owns_strings) allocator.free(settings.patches_dir);
        settings.patches_dir = try allocator.dupe(u8, value);
        settings.owns_strings = true;
    } else if (std.mem.eql(u8, key, "pinned_version")) {
        if (settings.owns_strings and settings.pinned_version != null) {
            allocator.free(settings.pinned_version.?);
        }
        if (std.mem.eql(u8, value, "none") or std.mem.eql(u8, value, "null") or value.len == 0) {
            settings.pinned_version = null;
        } else {
            settings.pinned_version = try allocator.dupe(u8, value);
        }
        settings.owns_strings = true;
    } else if (std.mem.eql(u8, key, "auto_update_check")) {
        settings.auto_update_check = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
    } else if (std.mem.eql(u8, key, "notifications")) {
        settings.notifications = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
    } else if (std.mem.eql(u8, key, "sign_modules")) {
        settings.sign_modules = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
    } else if (std.mem.eql(u8, key, "use_dkms")) {
        settings.use_dkms = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
    } else if (std.mem.eql(u8, key, "default_preset")) {
        if (settings.owns_strings) allocator.free(settings.default_preset);
        settings.default_preset = try allocator.dupe(u8, value);
        settings.owns_strings = true;
    } else if (std.mem.eql(u8, key, "extra_cflags")) {
        if (settings.owns_strings) allocator.free(settings.extra_cflags);
        settings.extra_cflags = try allocator.dupe(u8, value);
        settings.owns_strings = true;
    } else if (std.mem.eql(u8, key, "compiler")) {
        if (settings.owns_strings and settings.compiler != null) {
            allocator.free(settings.compiler.?);
        }
        if (std.mem.eql(u8, value, "auto") or value.len == 0) {
            settings.compiler = null;
        } else {
            settings.compiler = try allocator.dupe(u8, value);
        }
        settings.owns_strings = true;
    } else {
        try writer.print("Unknown setting: {s}\n", .{key});
        try writer.print("Available: patches_dir, pinned_version, auto_update_check, notifications,\n", .{});
        try writer.print("           sign_modules, use_dkms, default_preset, extra_cflags, compiler\n", .{});
        return false;
    }

    try settings.save(allocator);
    try writer.print("Set {s} = {s}\n", .{ key, value });

    return true;
}

/// Reset settings to defaults
pub fn resetSettings(allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    const settings = Settings{};
    try settings.save(allocator);
    try writer.print("Settings reset to defaults.\n", .{});
}

// JSON parsing helpers
fn parseJsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const key_pos = std.mem.indexOf(u8, json, key) orelse return error.KeyNotFound;
    const after_key = json[key_pos + key.len ..];

    const colon_pos = std.mem.indexOfScalar(u8, after_key, ':') orelse return error.InvalidJson;
    const after_colon = std.mem.trim(u8, after_key[colon_pos + 1 ..], " \t\n\r");

    if (std.mem.startsWith(u8, after_colon, "null")) {
        return allocator.dupe(u8, "");
    }

    const quote_start = std.mem.indexOfScalar(u8, after_colon, '"') orelse return error.InvalidJson;
    const value_start = after_colon[quote_start + 1 ..];

    const quote_end = std.mem.indexOfScalar(u8, value_start, '"') orelse return error.InvalidJson;

    return allocator.dupe(u8, value_start[0..quote_end]);
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

test "settings json roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const settings = Settings{
        .patches_dir = "/custom/patches",
        .pinned_version = "590.48.01",
        .auto_update_check = false,
    };

    const json = try settings.toJson(allocator);
    var parsed = try Settings.fromJson(allocator, json);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("/custom/patches", parsed.patches_dir);
    try std.testing.expectEqualStrings("590.48.01", parsed.pinned_version.?);
    try std.testing.expect(!parsed.auto_update_check);
}
