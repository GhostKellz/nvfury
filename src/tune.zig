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

/// Current module parameters (from loaded module)
pub const CurrentParams = struct {
    use_page_attribute_table: ?bool,
    enable_pcie_gen3: ?bool,
    enable_msi: ?bool,
    preserve_video_memory: ?bool,
    dynamic_power_management: ?u8,
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

/// Read current module parameters from sysfs
pub fn getCurrentParams() CurrentParams {
    return CurrentParams{
        .use_page_attribute_table = readSysfsParam("UsePageAttributeTable"),
        .enable_pcie_gen3 = readSysfsParam("EnablePCIeGen3"),
        .enable_msi = readSysfsParam("EnableMSI"),
        .preserve_video_memory = readSysfsParam("PreserveVideoMemoryAllocations"),
        .dynamic_power_management = readSysfsByte("DynamicPowerManagement"),
    };
}

/// Read a boolean parameter from sysfs
fn readSysfsParam(comptime param: []const u8) ?bool {
    const path = "/sys/module/nvidia/parameters/" ++ param;
    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    var buf: [8]u8 = undefined;
    const len = file.read(&buf) catch return null;
    if (len == 0) return null;

    const value = std.mem.trim(u8, buf[0..len], &[_]u8{ '\n', '\r', ' ' });
    if (value.len == 0) return null;

    if (std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "Y")) {
        return true;
    } else if (std.mem.eql(u8, value, "0") or std.mem.eql(u8, value, "N")) {
        return false;
    }
    return null;
}

/// Read a byte parameter from sysfs
fn readSysfsByte(comptime param: []const u8) ?u8 {
    const path = "/sys/module/nvidia/parameters/" ++ param;
    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    var buf: [16]u8 = undefined;
    const len = file.read(&buf) catch return null;
    if (len == 0) return null;

    const value = std.mem.trim(u8, buf[0..len], &[_]u8{ '\n', '\r', ' ' });

    // Handle hex format (0x02)
    if (value.len > 2 and value[0] == '0' and value[1] == 'x') {
        return std.fmt.parseInt(u8, value[2..], 16) catch null;
    }

    return std.fmt.parseInt(u8, value, 10) catch null;
}

/// Get the currently active preset based on parameters
pub fn detectCurrentPreset() ?config.TunePreset {
    const current = getCurrentParams();

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
        try writer.print("Active Preset: custom / unknown\n", .{});
    }

    try writer.print("\nModule Parameters:\n", .{});

    if (current.use_page_attribute_table) |pat| {
        try writer.print("  UsePageAttributeTable: {}\n", .{pat});
    } else {
        try writer.print("  UsePageAttributeTable: (not available)\n", .{});
    }

    if (current.enable_pcie_gen3) |gen3| {
        try writer.print("  EnablePCIeGen3: {}\n", .{gen3});
    } else {
        try writer.print("  EnablePCIeGen3: (not available)\n", .{});
    }

    if (current.enable_msi) |msi| {
        try writer.print("  EnableMSI: {}\n", .{msi});
    } else {
        try writer.print("  EnableMSI: (not available)\n", .{});
    }

    if (current.preserve_video_memory) |pvm| {
        try writer.print("  PreserveVideoMemory: {}\n", .{pvm});
    } else {
        try writer.print("  PreserveVideoMemory: (not available)\n", .{});
    }

    if (current.dynamic_power_management) |dpm| {
        try writer.print("  DynamicPowerManagement: 0x{x:0>2}\n", .{dpm});
    } else {
        try writer.print("  DynamicPowerManagement: (not available)\n", .{});
    }
}

test "tune preset" {
    const params = config.ModuleParams.fromPreset(.gaming);
    try std.testing.expect(params.use_page_attribute_table);
    try std.testing.expect(params.enable_msi);
}
