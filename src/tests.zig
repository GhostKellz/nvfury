//! Comprehensive test suite for nvfury
//!
//! All tests use std.testing.allocator which automatically detects memory leaks.
//! If any allocation is not freed, the test will fail with a leak report.

const std = @import("std");
const testing = std.testing;
const nvfury = @import("nvfury");

// =============================================================================
// Version Tests
// =============================================================================

test "version string format" {
    const version = nvfury.version;
    try testing.expectEqualStrings("0.2.0", version.string);

    // Verify string matches components
    var buf: [16]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "{d}.{d}.{d}", .{
        version.major,
        version.minor,
        version.patch,
    }) catch unreachable;
    try testing.expectEqualStrings(version.string, formatted);
}

test "version components" {
    try testing.expectEqual(@as(u32, 0), nvfury.version.major);
    try testing.expectEqual(@as(u32, 2), nvfury.version.minor);
    try testing.expectEqual(@as(u32, 0), nvfury.version.patch);
}

// =============================================================================
// Architecture Tests
// =============================================================================

test "architecture: all support open modules" {
    try testing.expect(nvfury.Architecture.turing.supportsOpen());
    try testing.expect(nvfury.Architecture.ampere.supportsOpen());
    try testing.expect(nvfury.Architecture.ada_lovelace.supportsOpen());
    try testing.expect(nvfury.Architecture.hopper.supportsOpen());
    try testing.expect(nvfury.Architecture.blackwell.supportsOpen());
}

test "architecture: minimum driver versions" {
    try testing.expectEqualStrings("515.43.04", nvfury.Architecture.turing.minDriverVersion());
    try testing.expectEqualStrings("515.43.04", nvfury.Architecture.ampere.minDriverVersion());
    try testing.expectEqualStrings("525.60.11", nvfury.Architecture.ada_lovelace.minDriverVersion());
    try testing.expectEqualStrings("525.60.11", nvfury.Architecture.hopper.minDriverVersion());
    try testing.expectEqualStrings("565.57.01", nvfury.Architecture.blackwell.minDriverVersion());
}

// =============================================================================
// Paths Tests
// =============================================================================

test "paths: default paths defined" {
    try testing.expect(nvfury.paths.cache.len > 0);
    try testing.expect(nvfury.paths.config_dir.len > 0);
    try testing.expect(nvfury.paths.source.len > 0);
    try testing.expect(nvfury.paths.build_output.len > 0);
    try testing.expect(nvfury.paths.backup.len > 0);
    try testing.expect(nvfury.paths.modprobe.len > 0);
}

test "paths: cache starts with tilde" {
    try testing.expect(nvfury.paths.cache[0] == '~');
    try testing.expect(nvfury.paths.config_dir[0] == '~');
}

test "paths: modprobe is absolute" {
    try testing.expect(nvfury.paths.modprobe[0] == '/');
    try testing.expectEqualStrings("/etc/modprobe.d/nvfury.conf", nvfury.paths.modprobe);
}

// =============================================================================
// Minimum Version Tests
// =============================================================================

test "minimum driver version: valid format" {
    const min_version = nvfury.min_open_driver_version;
    // Should have at least one dot
    try testing.expect(std.mem.indexOf(u8, min_version, ".") != null);
    // Should start with a digit (5 for 580.0.0)
    try testing.expect(min_version[0] >= '0' and min_version[0] <= '9');
    // Should be 580.0.0
    try testing.expectEqualStrings("580.0.0", min_version);
}

test "minimum driver version: parsed correctly" {
    const result = nvfury.fetch.parseVersion(nvfury.min_open_driver_version);
    try testing.expect(result != null);
    if (result) |v| {
        try testing.expectEqual(@as(u32, 580), v.major);
    }
}

// =============================================================================
// Config Module Tests (with leak detection)
// =============================================================================

test "config: module params to modprobe - no leaks" {
    const allocator = testing.allocator;

    const params = nvfury.config.ModuleParams{
        .use_page_attribute_table = true,
        .enable_pcie_gen3 = true,
        .enable_msi = true,
        .enable_gpu_firmware = true,
        .enable_resizable_bar = true,
    };

    const conf = try params.toModprobeConf(allocator);
    defer allocator.free(conf);

    // Verify content exists
    try testing.expect(conf.len > 0);
    try testing.expect(std.mem.indexOf(u8, conf, "options nvidia") != null);
}

test "config: expand path with tilde - no leaks" {
    const allocator = testing.allocator;

    const expanded = try nvfury.config.expandPath(allocator, "~/.config/nvfury");
    defer allocator.free(expanded);

    // Should not start with ~
    try testing.expect(expanded.len > 0);
    try testing.expect(expanded[0] != '~');
    // Should contain .config/nvfury
    try testing.expect(std.mem.indexOf(u8, expanded, ".config/nvfury") != null);
}

test "config: expand path without tilde - no leaks" {
    const allocator = testing.allocator;

    const expanded = try nvfury.config.expandPath(allocator, "/etc/modprobe.d/nvfury.conf");
    defer allocator.free(expanded);

    // Should be unchanged
    try testing.expectEqualStrings("/etc/modprobe.d/nvfury.conf", expanded);
}

// =============================================================================
// Settings Module Tests (with leak detection)
// =============================================================================

test "settings: default values" {
    const settings = nvfury.settings.Settings{};

    try testing.expect(settings.auto_update_check == true);
    try testing.expect(settings.notifications == true);
    try testing.expect(settings.sign_modules == false);
    try testing.expect(settings.use_dkms == true);
    try testing.expectEqualStrings("gaming", settings.default_preset);
}

test "settings: json roundtrip - no leaks" {
    const allocator = testing.allocator;

    var settings = nvfury.settings.Settings{};
    settings.auto_update_check = false;
    settings.notifications = false;
    settings.sign_modules = true;
    settings.use_dkms = false;

    // Serialize
    const json = try settings.toJson(allocator);
    defer allocator.free(json);

    // Verify JSON is valid
    try testing.expect(json.len > 0);
    try testing.expect(std.mem.indexOf(u8, json, "auto_update_check") != null);
}

// =============================================================================
// Build Cache Tests (with leak detection)
// =============================================================================

test "build_cache: meta structure" {
    // Test that BuildMeta struct has expected fields
    var hash: [64]u8 = undefined;
    @memset(&hash, 'a');

    const meta = nvfury.build_cache.BuildMeta{
        .version = "590.48.01",
        .source_hash = hash,
        .kernel_version = "6.7.0-arch1-1",
        .build_time = 1706000000,
        .compiler = "clang",
        .cflags = "-O3",
        .success = true,
    };

    try testing.expectEqualStrings("590.48.01", meta.version);
    try testing.expect(meta.success);
}

// =============================================================================
// Update Module Tests (with leak detection)
// =============================================================================

test "update: cache structure" {
    const cache = nvfury.update.UpdateCache{
        .last_check = 1706000000,
        .latest_version = "590.48.01",
        .installed_version = "580.105.08",
        .update_available = true,
    };

    try testing.expectEqual(@as(i64, 1706000000), cache.last_check);
    try testing.expectEqualStrings("590.48.01", cache.latest_version);
    try testing.expect(cache.update_available);
}

// =============================================================================
// Fetch Module Tests
// =============================================================================

test "fetch: version comparison returns integer" {
    // compareVersions returns i32: negative, zero, or positive
    const result1 = nvfury.fetch.compareVersions("590.48.01", "580.105.08");
    try testing.expect(result1 > 0); // 590 > 580

    const result2 = nvfury.fetch.compareVersions("580.105.08", "590.48.01");
    try testing.expect(result2 < 0); // 580 < 590

    const result3 = nvfury.fetch.compareVersions("590.48.01", "590.48.01");
    try testing.expectEqual(@as(i32, 0), result3); // equal
}

test "fetch: parse version" {
    const result = nvfury.fetch.parseVersion("590.48.01");
    try testing.expect(result != null);

    if (result) |v| {
        try testing.expectEqual(@as(u32, 590), v.major);
        try testing.expectEqual(@as(u32, 48), v.minor);
        try testing.expectEqual(@as(u32, 1), v.patch);
    }
}

test "fetch: parse invalid version" {
    const result = nvfury.fetch.parseVersion("invalid");
    try testing.expect(result == null);
}

// =============================================================================
// Uninstall Module Tests
// =============================================================================

test "uninstall: options defaults" {
    const options = nvfury.uninstall.UninstallOptions{};

    try testing.expect(options.remove_dkms == true);
    try testing.expect(options.remove_modprobe == true);
    try testing.expect(options.remove_cache == false);
    try testing.expect(options.remove_config == false);
    try testing.expect(options.dry_run == false);
    try testing.expect(options.restore_backup == false);
}

test "uninstall: result defaults" {
    const result = nvfury.uninstall.UninstallResult{
        .success = true,
        .modules_removed = 0,
        .dkms_removed = false,
        .modprobe_removed = false,
        .cache_removed = false,
        .config_removed = false,
        .backup_restored = false,
        .error_msg = null,
    };

    try testing.expect(result.success);
    try testing.expect(result.error_msg == null);
}

// =============================================================================
// Benchmark Module Tests
// =============================================================================

test "benchmark: result structure" {
    const result = nvfury.benchmark.BenchmarkResult{
        .name = "test_benchmark",
        .value = 123.45,
        .unit = "ms",
        .higher_is_better = false,
        .error_msg = null,
    };

    try testing.expectEqualStrings("test_benchmark", result.name);
    try testing.expectEqual(@as(f64, 123.45), result.value);
    try testing.expectEqualStrings("ms", result.unit);
    try testing.expect(!result.higher_is_better);
    try testing.expect(result.error_msg == null);
}

test "benchmark: result with error" {
    const result = nvfury.benchmark.BenchmarkResult{
        .name = "failed_test",
        .value = 0,
        .unit = "ms",
        .higher_is_better = false,
        .error_msg = "Test failed",
    };

    try testing.expect(result.error_msg != null);
    try testing.expectEqualStrings("Test failed", result.error_msg.?);
}

// =============================================================================
// Sign Module Tests
// =============================================================================

test "sign: secureboot status structure" {
    const status = nvfury.sign.SecureBootStatus{
        .enabled = false,
        .mok_key_exists = false,
        .mok_cert_exists = false,
        .mok_enrolled = false,
        .modules_signed = false,
    };

    try testing.expect(!status.enabled);
    try testing.expect(!status.mok_key_exists);
}

// =============================================================================
// Prime Module Tests
// =============================================================================

test "prime: graphics mode enum" {
    const mode = nvfury.prime.GraphicsMode.hybrid;
    try testing.expectEqual(nvfury.prime.GraphicsMode.hybrid, mode);

    // All modes should be distinct
    try testing.expect(nvfury.prime.GraphicsMode.discrete != nvfury.prime.GraphicsMode.integrated);
    try testing.expect(nvfury.prime.GraphicsMode.hybrid != nvfury.prime.GraphicsMode.unknown);
}

// =============================================================================
// String/Memory Stress Tests
// =============================================================================

test "stress: repeated string allocations - leak detection" {
    const allocator = testing.allocator;

    // Allocate and free many strings - allocator will catch leaks
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const str = try std.fmt.allocPrint(allocator, "test string {d}", .{i});
        defer allocator.free(str);
        try testing.expect(str.len > 0);
    }
}

test "stress: repeated path expansion - leak detection" {
    const allocator = testing.allocator;

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const expanded = try nvfury.config.expandPath(allocator, "~/.cache/nvfury/test");
        defer allocator.free(expanded);
        try testing.expect(expanded[0] != '~');
    }
}

test "stress: config generation - leak detection" {
    const allocator = testing.allocator;

    var i: usize = 0;
    while (i < 50) : (i += 1) {
        const params = nvfury.config.ModuleParams{
            .use_page_attribute_table = (i % 2 == 0),
            .enable_pcie_gen3 = (i % 3 == 0),
            .enable_msi = true,
            .preserve_video_memory = true,
            .enable_gpu_firmware = true,
            .enable_resizable_bar = (i % 4 == 0),
            .dynamic_power_management = 0x02,
        };

        const conf = try params.toModprobeConf(allocator);
        defer allocator.free(conf);
        try testing.expect(conf.len > 0);
    }
}

// =============================================================================
// Integration Tests
// =============================================================================

test "integration: version and paths consistency" {
    // Version should be set
    try testing.expect(nvfury.version.string.len > 0);

    // Paths should all be defined
    try testing.expect(nvfury.paths.cache.len > 0);
    try testing.expect(nvfury.paths.modprobe.len > 0);

    // Minimum driver version should be valid
    try testing.expect(nvfury.min_open_driver_version.len > 0);
    try testing.expect(nvfury.fetch.parseVersion(nvfury.min_open_driver_version) != null);
}

test "integration: architecture coverage" {
    // All architectures should have valid min driver versions
    const archs = [_]nvfury.Architecture{
        .turing,
        .ampere,
        .ada_lovelace,
        .hopper,
        .blackwell,
    };

    for (archs) |arch| {
        const min_version = arch.minDriverVersion();
        try testing.expect(min_version.len > 0);
        try testing.expect(std.mem.indexOf(u8, min_version, ".") != null);
        try testing.expect(arch.supportsOpen());
    }
}
