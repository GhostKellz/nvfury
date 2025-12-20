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
        var dpm_buf: [32]u8 = undefined;
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
        const home = std.posix.getenv("HOME") orelse "/root";
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

test "module params to modprobe conf" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const params = ModuleParams.fromPreset(.gaming);
    const conf = try params.toModprobeConf(allocator);
    try std.testing.expect(std.mem.indexOf(u8, conf, "NVreg_UsePageAttributeTable=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, conf, "NVreg_EnableMSI=1") != null);
}
