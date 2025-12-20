//! nvfury/tune - Module Parameter Tuning
//!
//! Manages NVIDIA module parameters via modprobe.d configuration.

const std = @import("std");
const config = @import("config.zig");

/// Tuning result
pub const TuneResult = struct {
    success: bool,
    preset: config.TunePreset,
    config_path: []const u8,
    message: []const u8,
};

/// Current module parameters (from modprobe.d config)
pub const CurrentParams = struct {
    use_page_attribute_table: ?bool,
    enable_pcie_gen3: ?bool,
    enable_msi: ?bool,
    preserve_video_memory: ?bool,
    dynamic_power_management: ?u8,
    enable_gpu_firmware: ?bool,
    enable_resizable_bar: ?bool,
};

/// Apply a tuning preset
pub fn applyPreset(allocator: std.mem.Allocator, preset: config.TunePreset) !TuneResult {
    const params = config.ModuleParams.fromPreset(preset);
    const conf_content = try params.toModprobeConf(allocator);
    defer allocator.free(conf_content);

    const conf_path = "/etc/modprobe.d/nvfury.conf";

    // Write configuration file
    const file = std.fs.createFileAbsolute(conf_path, .{}) catch |err| {
        return TuneResult{
            .success = false,
            .preset = preset,
            .config_path = conf_path,
            .message = switch (err) {
                error.AccessDenied => "Permission denied - run with sudo",
                else => "Failed to write config file",
            },
        };
    };
    defer file.close();

    file.writeAll(conf_content) catch {
        return TuneResult{
            .success = false,
            .preset = preset,
            .config_path = conf_path,
            .message = "Failed to write config content",
        };
    };

    return TuneResult{
        .success = true,
        .preset = preset,
        .config_path = conf_path,
        .message = "Configuration applied. Reboot or reload nvidia module to take effect.",
    };
}

/// Read current module parameters from modprobe.d config
pub fn getCurrentParams() CurrentParams {
    var params = CurrentParams{
        .use_page_attribute_table = null,
        .enable_pcie_gen3 = null,
        .enable_msi = null,
        .preserve_video_memory = null,
        .dynamic_power_management = null,
        .enable_gpu_firmware = null,
        .enable_resizable_bar = null,
    };

    // Try to read nvfury.conf
    const conf_path = "/etc/modprobe.d/nvfury.conf";
    const file = std.fs.openFileAbsolute(conf_path, .{}) catch return params;
    defer file.close();

    var buf: [4096]u8 = undefined;
    var total: usize = 0;
    while (total < buf.len) {
        const n = file.read(buf[total..]) catch return params;
        if (n == 0) break;
        total += n;
    }
    const content = buf[0..total];

    // Parse parameters from config
    params.use_page_attribute_table = parseModprobeBool(content, "NVreg_UsePageAttributeTable");
    params.enable_pcie_gen3 = parseModprobeBool(content, "NVreg_EnablePCIeGen3");
    params.enable_msi = parseModprobeBool(content, "NVreg_EnableMSI");
    params.preserve_video_memory = parseModprobeBool(content, "NVreg_PreserveVideoMemoryAllocations");
    params.dynamic_power_management = parseModprobeByte(content, "NVreg_DynamicPowerManagement");
    params.enable_gpu_firmware = parseModprobeBool(content, "NVreg_EnableGpuFirmware");
    params.enable_resizable_bar = parseModprobeBool(content, "NVreg_EnableResizableBar");

    return params;
}

/// Parse a boolean parameter from modprobe config content
fn parseModprobeBool(content: []const u8, param: []const u8) ?bool {
    // Look for "param=1" or "param=0"
    var i: usize = 0;
    while (i < content.len) {
        if (std.mem.startsWith(u8, content[i..], param)) {
            const after_param = i + param.len;
            if (after_param < content.len and content[after_param] == '=') {
                const value_start = after_param + 1;
                if (value_start < content.len) {
                    if (content[value_start] == '1') return true;
                    if (content[value_start] == '0') return false;
                }
            }
        }
        i += 1;
    }
    return null;
}

/// Parse a byte parameter from modprobe config content
fn parseModprobeByte(content: []const u8, param: []const u8) ?u8 {
    var i: usize = 0;
    while (i < content.len) {
        if (std.mem.startsWith(u8, content[i..], param)) {
            const after_param = i + param.len;
            if (after_param < content.len and content[after_param] == '=') {
                const value_start = after_param + 1;
                // Check for hex format 0x...
                if (value_start + 2 < content.len and content[value_start] == '0' and content[value_start + 1] == 'x') {
                    // Parse hex
                    var end = value_start + 2;
                    while (end < content.len and std.ascii.isHex(content[end])) {
                        end += 1;
                    }
                    return std.fmt.parseInt(u8, content[value_start + 2 .. end], 16) catch null;
                } else {
                    // Parse decimal
                    var end = value_start;
                    while (end < content.len and std.ascii.isDigit(content[end])) {
                        end += 1;
                    }
                    return std.fmt.parseInt(u8, content[value_start..end], 10) catch null;
                }
            }
        }
        i += 1;
    }
    return null;
}


/// Get the currently active preset based on parameters
pub fn detectCurrentPreset() ?config.TunePreset {
    const current = getCurrentParams();

    // If no config file exists (all null), return null
    const has_any_param = current.use_page_attribute_table != null or
        current.enable_pcie_gen3 != null or
        current.enable_msi != null or
        current.dynamic_power_management != null or
        current.enable_gpu_firmware != null or
        current.enable_resizable_bar != null;

    if (!has_any_param) return null;

    // Check against known presets
    inline for (@typeInfo(config.TunePreset).@"enum".fields) |field| {
        const preset: config.TunePreset = @enumFromInt(field.value);
        const expected = config.ModuleParams.fromPreset(preset);

        var matches = true;

        if (current.use_page_attribute_table) |pat| {
            if (pat != expected.use_page_attribute_table) matches = false;
        }
        if (current.enable_pcie_gen3) |gen3| {
            if (gen3 != expected.enable_pcie_gen3) matches = false;
        }
        if (current.enable_msi) |msi| {
            if (msi != expected.enable_msi) matches = false;
        }
        if (current.dynamic_power_management) |dpm| {
            if (dpm != expected.dynamic_power_management) matches = false;
        }
        if (current.enable_gpu_firmware) |gsp| {
            if (gsp != expected.enable_gpu_firmware) matches = false;
        }
        if (current.enable_resizable_bar) |rebar| {
            if (rebar != expected.enable_resizable_bar) matches = false;
        }

        if (matches) return preset;
    }

    return null;
}

/// Print current tuning status
pub fn printStatus(writer: anytype) !void {
    const current = getCurrentParams();
    const preset = detectCurrentPreset();

    try writer.print("nvfury Tuning Status\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    if (preset) |p| {
        try writer.print("Active Preset: {s}\n", .{@tagName(p)});
        try writer.print("Description:   {s}\n", .{p.description()});
    } else {
        try writer.print("Active Preset: (no nvfury config found)\n", .{});
        try writer.print("Run 'sudo nvfury tune gaming' to apply settings.\n", .{});
    }

    try writer.print("\nModule Parameters (from /etc/modprobe.d/nvfury.conf):\n", .{});

    if (current.use_page_attribute_table) |pat| {
        try writer.print("  UsePageAttributeTable: {}\n", .{pat});
    } else {
        try writer.print("  UsePageAttributeTable: (not set)\n", .{});
    }

    if (current.enable_pcie_gen3) |gen3| {
        try writer.print("  EnablePCIeGen3:        {}\n", .{gen3});
    } else {
        try writer.print("  EnablePCIeGen3:        (not set)\n", .{});
    }

    if (current.enable_msi) |msi| {
        try writer.print("  EnableMSI:             {}\n", .{msi});
    } else {
        try writer.print("  EnableMSI:             (not set)\n", .{});
    }

    if (current.preserve_video_memory) |pvm| {
        try writer.print("  PreserveVideoMemory:   {}\n", .{pvm});
    } else {
        try writer.print("  PreserveVideoMemory:   (not set)\n", .{});
    }

    if (current.dynamic_power_management) |dpm| {
        try writer.print("  DynamicPowerMgmt:      0x{x:0>2}\n", .{dpm});
    } else {
        try writer.print("  DynamicPowerMgmt:      (not set)\n", .{});
    }

    if (current.enable_gpu_firmware) |gsp| {
        try writer.print("  EnableGpuFirmware:     {} (GSP)\n", .{gsp});
    } else {
        try writer.print("  EnableGpuFirmware:     (not set)\n", .{});
    }

    if (current.enable_resizable_bar) |rebar| {
        try writer.print("  EnableResizableBar:    {} (ReBAR)\n", .{rebar});
    } else {
        try writer.print("  EnableResizableBar:    (not set)\n", .{});
    }
}

test "tune preset" {
    const params = config.ModuleParams.fromPreset(.gaming);
    try std.testing.expect(params.use_page_attribute_table);
    try std.testing.expect(params.enable_msi);
}
