//! nvfury/config - Configuration Management
//!
//! Handles configuration loading, presets, and settings persistence.

const std = @import("std");

/// Build configuration
pub const BuildConfig = struct {
    /// NVIDIA driver version to build
    version: []const u8 = "latest",
    /// Source directory (if building from local source)
    source_dir: ?[]const u8 = null,
    /// Enable benchmark instrumentation
    benchmark: bool = false,
    /// Custom compiler flags
    extra_cflags: []const u8 = "",
    /// Enable LTO
    lto: bool = true,
    /// Optimization level
    opt_level: OptLevel = .o3,

    pub const OptLevel = enum {
        o0,
        o1,
        o2,
        o3,
        os,
        oz,

        pub fn toFlag(self: OptLevel) []const u8 {
            return switch (self) {
                .o0 => "-O0",
                .o1 => "-O1",
                .o2 => "-O2",
                .o3 => "-O3",
                .os => "-Os",
                .oz => "-Oz",
            };
        }
    };
};

/// Module parameter preset
pub const TunePreset = enum {
    gaming,
    balanced,
    quiet,
    benchmark,

    pub fn description(self: TunePreset) []const u8 {
        return switch (self) {
            .gaming => "Maximum performance, low latency",
            .balanced => "Balance of performance and efficiency",
            .quiet => "Power saving, reduced heat/noise",
            .benchmark => "Maximum performance for testing",
        };
    }
};

/// Module parameters configuration
pub const ModuleParams = struct {
    use_page_attribute_table: bool = true,
    enable_pcie_gen3: bool = true,
    enable_msi: bool = true,
    preserve_video_memory: bool = true,
    dynamic_power_management: u8 = 0x02,
    temporary_file_path: []const u8 = "/tmp",
    init_system_memory_allocs: bool = false,
    enable_gpu_firmware: bool = true, // GSP firmware (590+)
    enable_resizable_bar: bool = true, // ReBAR support

    /// Generate modprobe.d configuration content
    pub fn toModprobeConf(self: ModuleParams, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "# nvfury generated configuration\n");
        try buf.appendSlice(allocator, "# Do not edit - regenerate with 'nvfury tune'\n\n");
        try buf.appendSlice(allocator, "options nvidia ");

        if (self.use_page_attribute_table) {
            try buf.appendSlice(allocator, "NVreg_UsePageAttributeTable=1 ");
        }
        if (self.enable_pcie_gen3) {
            try buf.appendSlice(allocator, "NVreg_EnablePCIeGen3=1 ");
        }
        if (self.enable_msi) {
            try buf.appendSlice(allocator, "NVreg_EnableMSI=1 ");
        }
        if (self.preserve_video_memory) {
            try buf.appendSlice(allocator, "NVreg_PreserveVideoMemoryAllocations=1 ");
        }

        // Format DynamicPowerManagement
        var dpm_buf: [64]u8 = undefined;
        const dpm_str = std.fmt.bufPrint(&dpm_buf, "NVreg_DynamicPowerManagement=0x{x:0>2} ", .{self.dynamic_power_management}) catch unreachable;
        try buf.appendSlice(allocator, dpm_str);

        // Format TemporaryFilePath
        try buf.appendSlice(allocator, "NVreg_TemporaryFilePath=");
        try buf.appendSlice(allocator, self.temporary_file_path);
        try buf.append(allocator, ' ');

        if (!self.init_system_memory_allocs) {
            try buf.appendSlice(allocator, "NVreg_InitializeSystemMemoryAllocations=0 ");
        }

        // GSP firmware (590+)
        if (self.enable_gpu_firmware) {
            try buf.appendSlice(allocator, "NVreg_EnableGpuFirmware=1 ");
        }

        // Resizable BAR
        if (self.enable_resizable_bar) {
            try buf.appendSlice(allocator, "NVreg_EnableResizableBar=1 ");
        }

        try buf.append(allocator, '\n');

        return buf.toOwnedSlice(allocator);
    }

    /// Get preset configuration
    pub fn fromPreset(preset: TunePreset) ModuleParams {
        return switch (preset) {
            .gaming => .{
                .use_page_attribute_table = true,
                .enable_pcie_gen3 = true,
                .enable_msi = true,
                .preserve_video_memory = true,
                .dynamic_power_management = 0x02, // Fine-grained power management
                .temporary_file_path = "/tmp",
                .init_system_memory_allocs = false,
                .enable_gpu_firmware = true, // GSP enabled for 590+
                .enable_resizable_bar = true, // ReBAR for RTX 40/50
            },
            .balanced => .{
                .use_page_attribute_table = true,
                .enable_pcie_gen3 = true,
                .enable_msi = true,
                .preserve_video_memory = true,
                .dynamic_power_management = 0x01, // Coarse-grained
                .temporary_file_path = "/tmp",
                .init_system_memory_allocs = false,
                .enable_gpu_firmware = true,
                .enable_resizable_bar = true,
            },
            .quiet => .{
                .use_page_attribute_table = true,
                .enable_pcie_gen3 = false, // Allow lower PCIe speeds
                .enable_msi = true,
                .preserve_video_memory = false,
                .dynamic_power_management = 0x02,
                .temporary_file_path = "/tmp",
                .init_system_memory_allocs = true,
                .enable_gpu_firmware = true,
                .enable_resizable_bar = false, // Power saving
            },
            .benchmark => .{
                .use_page_attribute_table = true,
                .enable_pcie_gen3 = true,
                .enable_msi = true,
                .preserve_video_memory = true,
                .dynamic_power_management = 0x00, // Disabled for max perf
                .temporary_file_path = "/dev/shm", // RAM disk
                .init_system_memory_allocs = false,
                .enable_gpu_firmware = true,
                .enable_resizable_bar = true,
            },
        };
    }
};

/// Installation configuration
pub const InstallConfig = struct {
    /// Use DKMS for automatic rebuilds
    use_dkms: bool = true,
    /// Create backup before install
    create_backup: bool = true,
    /// Verify module loads after install
    verify_load: bool = true,
    /// Sign modules for Secure Boot
    sign_modules: bool = false,
    /// Signing key path (if sign_modules is true)
    signing_key: ?[]const u8 = null,
};

/// Expand ~ to home directory
pub fn expandPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return allocator.dupe(u8, path);

    if (path[0] == '~') {
        // Use C library getenv since we link libc
        const home_ptr = std.c.getenv("HOME");
        const home = if (home_ptr) |ptr| std.mem.sliceTo(ptr, 0) else "/root";
        const total_len = home.len + path.len - 1;
        const result = try allocator.alloc(u8, total_len);
        @memcpy(result[0..home.len], home);
        if (path.len > 1) {
            @memcpy(result[home.len..], path[1..]);
        }
        return result;
    }

    return allocator.dupe(u8, path);
}

/// Full profile for export/import
pub const Profile = struct {
    /// Profile name
    name: []const u8,
    /// Description
    description: []const u8 = "",
    /// Profile version for compatibility
    version: u32 = 1,
    /// Module parameters
    params: ModuleParams = .{},
    /// Recommended patches
    patches: []const []const u8 = &.{},
    /// Created timestamp
    created: i64 = 0,
    /// Whether strings were allocated (for cleanup)
    owns_strings: bool = false,
    /// Allocator used (for cleanup)
    allocator: ?std.mem.Allocator = null,

    /// Free allocated memory
    pub fn deinit(self: *Profile) void {
        if (self.owns_strings) {
            if (self.allocator) |alloc| {
                alloc.free(self.name);
                alloc.free(self.description);
                // Free temporary_file_path if it was allocated (from JSON import)
                // Check if the pointer is within the allocator's memory (not a static string)
                // Static strings from ModuleParams.fromPreset point to compile-time data
                const temp_path = self.params.temporary_file_path;
                if (temp_path.len > 0) {
                    // Only free if it's not one of the compile-time static strings
                    // We detect this by checking if it was created from JSON (owns_strings = true)
                    // and the pointer is heap-allocated (not pointing to static data)
                    alloc.free(temp_path);
                }
            }
        }
        self.* = undefined;
    }

    /// Export profile to JSON string (caller must free)
    pub fn toJson(self: Profile, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "{\n");
        try buf.appendSlice(allocator, "  \"name\": \"");
        try buf.appendSlice(allocator, self.name);
        try buf.appendSlice(allocator, "\",\n");
        try buf.appendSlice(allocator, "  \"description\": \"");
        try buf.appendSlice(allocator, self.description);
        try buf.appendSlice(allocator, "\",\n");

        var version_buf: [32]u8 = undefined;
        const version_str = std.fmt.bufPrint(&version_buf, "  \"version\": {d},\n", .{self.version}) catch unreachable;
        try buf.appendSlice(allocator, version_str);

        try buf.appendSlice(allocator, "  \"params\": {\n");
        try buf.appendSlice(allocator, if (self.params.use_page_attribute_table) "    \"use_page_attribute_table\": true,\n" else "    \"use_page_attribute_table\": false,\n");
        try buf.appendSlice(allocator, if (self.params.enable_pcie_gen3) "    \"enable_pcie_gen3\": true,\n" else "    \"enable_pcie_gen3\": false,\n");
        try buf.appendSlice(allocator, if (self.params.enable_msi) "    \"enable_msi\": true,\n" else "    \"enable_msi\": false,\n");
        try buf.appendSlice(allocator, if (self.params.preserve_video_memory) "    \"preserve_video_memory\": true,\n" else "    \"preserve_video_memory\": false,\n");

        var dpm_buf: [64]u8 = undefined;
        const dpm_str = std.fmt.bufPrint(&dpm_buf, "    \"dynamic_power_management\": {d},\n", .{self.params.dynamic_power_management}) catch unreachable;
        try buf.appendSlice(allocator, dpm_str);

        try buf.appendSlice(allocator, "    \"temporary_file_path\": \"");
        try buf.appendSlice(allocator, self.params.temporary_file_path);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, if (self.params.init_system_memory_allocs) "    \"init_system_memory_allocs\": true,\n" else "    \"init_system_memory_allocs\": false,\n");
        try buf.appendSlice(allocator, if (self.params.enable_gpu_firmware) "    \"enable_gpu_firmware\": true,\n" else "    \"enable_gpu_firmware\": false,\n");
        try buf.appendSlice(allocator, if (self.params.enable_resizable_bar) "    \"enable_resizable_bar\": true\n" else "    \"enable_resizable_bar\": false\n");

        try buf.appendSlice(allocator, "  },\n");

        // Patches array
        try buf.appendSlice(allocator, "  \"patches\": [");
        for (self.patches, 0..) |patch, i| {
            if (i > 0) try buf.appendSlice(allocator, ", ");
            try buf.append(allocator, '"');
            try buf.appendSlice(allocator, patch);
            try buf.append(allocator, '"');
        }
        try buf.appendSlice(allocator, "],\n");

        var timestamp_buf: [32]u8 = undefined;
        const timestamp_str = std.fmt.bufPrint(&timestamp_buf, "  \"created\": {d}\n", .{self.created}) catch unreachable;
        try buf.appendSlice(allocator, timestamp_str);

        try buf.appendSlice(allocator, "}\n");

        return buf.toOwnedSlice(allocator);
    }

    /// Parse profile from JSON string
    pub fn fromJson(alloc: std.mem.Allocator, json: []const u8) !Profile {
        // Parse all strings first
        const name = try parseJsonString(alloc, json, "\"name\"");
        errdefer alloc.free(name);

        const description = try parseJsonString(alloc, json, "\"description\"");
        errdefer alloc.free(description);

        const temp_path = try parseJsonString(alloc, json, "\"temporary_file_path\"");
        errdefer alloc.free(temp_path);

        return Profile{
            .name = name,
            .description = description,
            .version = parseJsonInt(json, "\"version\"") orelse 1,
            .created = @intCast(parseJsonInt(json, "\"created\"") orelse 0),
            .params = .{
                .use_page_attribute_table = parseJsonBool(json, "\"use_page_attribute_table\"") orelse true,
                .enable_pcie_gen3 = parseJsonBool(json, "\"enable_pcie_gen3\"") orelse true,
                .enable_msi = parseJsonBool(json, "\"enable_msi\"") orelse true,
                .preserve_video_memory = parseJsonBool(json, "\"preserve_video_memory\"") orelse true,
                .dynamic_power_management = @intCast(parseJsonInt(json, "\"dynamic_power_management\"") orelse 0x02),
                .temporary_file_path = temp_path,
                .init_system_memory_allocs = parseJsonBool(json, "\"init_system_memory_allocs\"") orelse false,
                .enable_gpu_firmware = parseJsonBool(json, "\"enable_gpu_firmware\"") orelse true,
                .enable_resizable_bar = parseJsonBool(json, "\"enable_resizable_bar\"") orelse true,
            },
            .owns_strings = true,
            .allocator = alloc,
        };
    }

    /// Create profile from preset
    pub fn fromPreset(preset: TunePreset, alloc: std.mem.Allocator) !Profile {
        // Get current time as unix timestamp (seconds since epoch)
        var ts: std.os.linux.timespec = .{ .sec = 0, .nsec = 0 };
        _ = std.os.linux.clock_gettime(.REALTIME, &ts);
        const now: i64 = ts.sec;

        const name = try alloc.dupe(u8, @tagName(preset));
        errdefer alloc.free(name);

        const description = try alloc.dupe(u8, preset.description());
        errdefer alloc.free(description);

        var params = ModuleParams.fromPreset(preset);
        // Allocate temp_path so deinit can free it consistently
        const temp_path = try alloc.dupe(u8, params.temporary_file_path);
        params.temporary_file_path = temp_path;

        return Profile{
            .name = name,
            .description = description,
            .version = 1,
            .params = params,
            .patches = &.{},
            .created = now,
            .owns_strings = true,
            .allocator = alloc,
        };
    }
};

/// Parse a JSON string value
fn parseJsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const key_pos = std.mem.indexOf(u8, json, key) orelse return allocator.dupe(u8, "");
    const after_key = json[key_pos + key.len ..];

    // Find colon
    const colon_pos = std.mem.indexOfScalar(u8, after_key, ':') orelse return allocator.dupe(u8, "");
    const after_colon = after_key[colon_pos + 1 ..];

    // Find opening quote
    const quote_start = std.mem.indexOfScalar(u8, after_colon, '"') orelse return allocator.dupe(u8, "");
    const value_start = after_colon[quote_start + 1 ..];

    // Find closing quote
    const quote_end = std.mem.indexOfScalar(u8, value_start, '"') orelse return allocator.dupe(u8, "");

    return allocator.dupe(u8, value_start[0..quote_end]);
}

/// Parse a JSON integer value
fn parseJsonInt(json: []const u8, key: []const u8) ?u32 {
    const key_pos = std.mem.indexOf(u8, json, key) orelse return null;
    const after_key = json[key_pos + key.len ..];

    // Find colon
    const colon_pos = std.mem.indexOfScalar(u8, after_key, ':') orelse return null;
    const after_colon = std.mem.trim(u8, after_key[colon_pos + 1 ..], " \t\n\r");

    // Parse number
    var num: u32 = 0;
    for (after_colon) |c| {
        if (std.ascii.isDigit(c)) {
            num = num * 10 + (c - '0');
        } else if (c != ' ' and c != '\t') {
            break;
        }
    }

    return num;
}

/// Parse a JSON boolean value
fn parseJsonBool(json: []const u8, key: []const u8) ?bool {
    const key_pos = std.mem.indexOf(u8, json, key) orelse return null;
    const after_key = json[key_pos + key.len ..];

    // Find colon
    const colon_pos = std.mem.indexOfScalar(u8, after_key, ':') orelse return null;
    const after_colon = std.mem.trim(u8, after_key[colon_pos + 1 ..], " \t\n\r");

    if (std.mem.startsWith(u8, after_colon, "true")) return true;
    if (std.mem.startsWith(u8, after_colon, "false")) return false;

    return null;
}

/// Export profile to file
pub fn exportProfile(allocator: std.mem.Allocator, profile: Profile, path: []const u8) !void {
    const json = try profile.toJson(allocator);
    defer allocator.free(json);

    const expanded_path = try expandPath(allocator, path);
    defer allocator.free(expanded_path);

    const fd = try std.posix.openat(std.posix.AT.FDCWD, expanded_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer _ = std.c.close(fd);

    const write_result = std.c.write(fd, json.ptr, json.len);
    if (write_result < 0) return error.WriteError;
}

/// Import profile from file
pub fn importProfile(allocator: std.mem.Allocator, path: []const u8) !Profile {
    const expanded_path = try expandPath(allocator, path);
    defer allocator.free(expanded_path);

    const fd = try std.posix.openat(std.posix.AT.FDCWD, expanded_path, .{}, 0);
    defer _ = std.c.close(fd);

    // Get file size using lseek
    const size_i64 = std.c.lseek64(fd, 0, 2); // SEEK_END = 2
    if (size_i64 < 0) return error.SeekError;
    _ = std.c.lseek64(fd, 0, 0); // SEEK_SET = 0, reset to beginning
    const size: usize = @intCast(size_i64);
    if (size > 1024 * 1024) return error.FileTooLarge; // 1MB max

    const content = try allocator.alloc(u8, size);
    defer allocator.free(content);

    // Read file using posix
    var total_read: usize = 0;
    while (total_read < size) {
        const n = std.posix.read(fd, content[total_read..]) catch return error.ReadError;
        if (n == 0) break;
        total_read += n;
    }
    if (total_read != size) return error.UnexpectedEof;

    return Profile.fromJson(allocator, content);
}

test "module params to modprobe conf" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const params = ModuleParams.fromPreset(.gaming);
    const conf = try params.toModprobeConf(allocator);
    try std.testing.expect(std.mem.indexOf(u8, conf, "NVreg_UsePageAttributeTable=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, conf, "NVreg_EnableMSI=1") != null);
}

test "profile json roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const profile = try Profile.fromPreset(.gaming, allocator);
    const json = try profile.toJson(allocator);
    const imported = try Profile.fromJson(allocator, json);

    try std.testing.expectEqualStrings("gaming", imported.name);
    try std.testing.expectEqual(profile.params.dynamic_power_management, imported.params.dynamic_power_management);
}
