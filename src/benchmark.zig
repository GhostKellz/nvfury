//! nvfury/benchmark - Performance Benchmarking
//!
//! Measures NVIDIA driver performance and compares stock vs nvfury-built modules.
//! Tests module load time, memory throughput, and basic GPU operations.

const std = @import("std");
const config = @import("config.zig");
const fetch = @import("fetch.zig");

/// Benchmark result
pub const BenchmarkResult = struct {
    /// Test name
    name: []const u8,
    /// Value (lower is better for latency, higher for throughput)
    value: f64,
    /// Unit of measurement
    unit: []const u8,
    /// Whether higher is better
    higher_is_better: bool,
    /// Error message if test failed
    error_msg: ?[]const u8,
};

/// Complete benchmark report
pub const BenchmarkReport = struct {
    /// Driver version tested
    driver_version: []const u8,
    /// Kernel version
    kernel_version: []const u8,
    /// GPU name
    gpu_name: []const u8,
    /// Build type (stock/nvfury)
    build_type: []const u8,
    /// Timestamp
    timestamp: i64,
    /// Individual test results
    results: std.ArrayListUnmanaged(BenchmarkResult),

    pub fn deinit(self: *BenchmarkReport, allocator: std.mem.Allocator) void {
        self.results.deinit(allocator);
        self.* = undefined;
    }

    /// Export to JSON
    pub fn toJson(self: BenchmarkReport, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "{\n");
        try buf.appendSlice(allocator, "  \"driver_version\": \"");
        try buf.appendSlice(allocator, self.driver_version);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"kernel_version\": \"");
        try buf.appendSlice(allocator, self.kernel_version);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"gpu_name\": \"");
        try buf.appendSlice(allocator, self.gpu_name);
        try buf.appendSlice(allocator, "\",\n");

        try buf.appendSlice(allocator, "  \"build_type\": \"");
        try buf.appendSlice(allocator, self.build_type);
        try buf.appendSlice(allocator, "\",\n");

        var ts_buf: [32]u8 = undefined;
        const ts_str = std.fmt.bufPrint(&ts_buf, "  \"timestamp\": {d},\n", .{self.timestamp}) catch unreachable;
        try buf.appendSlice(allocator, ts_str);

        try buf.appendSlice(allocator, "  \"results\": [\n");
        for (self.results.items, 0..) |result, i| {
            try buf.appendSlice(allocator, "    {\n");
            try buf.appendSlice(allocator, "      \"name\": \"");
            try buf.appendSlice(allocator, result.name);
            try buf.appendSlice(allocator, "\",\n");

            var val_buf: [32]u8 = undefined;
            const val_str = std.fmt.bufPrint(&val_buf, "      \"value\": {d:.3},\n", .{result.value}) catch unreachable;
            try buf.appendSlice(allocator, val_str);

            try buf.appendSlice(allocator, "      \"unit\": \"");
            try buf.appendSlice(allocator, result.unit);
            try buf.appendSlice(allocator, "\",\n");

            try buf.appendSlice(allocator, "      \"higher_is_better\": ");
            try buf.appendSlice(allocator, if (result.higher_is_better) "true" else "false");
            try buf.appendSlice(allocator, "\n    }");

            if (i < self.results.items.len - 1) {
                try buf.appendSlice(allocator, ",");
            }
            try buf.appendSlice(allocator, "\n");
        }
        try buf.appendSlice(allocator, "  ]\n");
        try buf.appendSlice(allocator, "}\n");

        return buf.toOwnedSlice(allocator);
    }
};

/// Measure module load time
fn benchModuleLoadTime(allocator: std.mem.Allocator) !BenchmarkResult {
    const io = std.Options.debug_io;

    // First, unload NVIDIA modules if possible (requires root)
    const can_unload = std.c.geteuid() == 0;
    if (!can_unload) {
        return BenchmarkResult{
            .name = "module_load_time",
            .value = 0,
            .unit = "ms",
            .higher_is_better = false,
            .error_msg = "Requires root to unload/reload modules",
        };
    }

    // Check if nvidia module is in use
    const lsmod = std.process.run(allocator, io, .{
        .argv = &.{ "lsmod" },
    }) catch return BenchmarkResult{
        .name = "module_load_time",
        .value = 0,
        .unit = "ms",
        .higher_is_better = false,
        .error_msg = "lsmod failed",
    };
    defer allocator.free(lsmod.stdout);
    defer allocator.free(lsmod.stderr);

    // Look for nvidia in use count
    if (std.mem.indexOf(u8, lsmod.stdout, "nvidia") != null) {
        // Check if GPU is in use
        if (std.mem.indexOf(u8, lsmod.stdout, "nvidia_drm") != null) {
            return BenchmarkResult{
                .name = "module_load_time",
                .value = 0,
                .unit = "ms",
                .higher_is_better = false,
                .error_msg = "GPU in use (display attached), cannot unload",
            };
        }
    }

    // Try to unload and time the reload
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "rmmod", "nvidia_uvm" },
    }) catch {};

    var timer = std.time.Timer.start() catch return BenchmarkResult{
        .name = "module_load_time",
        .value = 0,
        .unit = "ms",
        .higher_is_better = false,
        .error_msg = "Timer not supported",
    };

    _ = std.process.run(allocator, io, .{
        .argv = &.{ "modprobe", "nvidia_uvm" },
    }) catch return BenchmarkResult{
        .name = "module_load_time",
        .value = 0,
        .unit = "ms",
        .higher_is_better = false,
        .error_msg = "Failed to reload module",
    };

    const elapsed_ns = timer.read();
    const duration_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

    return BenchmarkResult{
        .name = "module_load_time",
        .value = duration_ms,
        .unit = "ms",
        .higher_is_better = false,
        .error_msg = null,
    };
}

/// Measure NVML query latency
fn benchNvmlQueryLatency(allocator: std.mem.Allocator) !BenchmarkResult {
    const io = std.Options.debug_io;
    const iterations = 100;

    var timer = std.time.Timer.start() catch return BenchmarkResult{
        .name = "nvml_query_latency",
        .value = 0,
        .unit = "us",
        .higher_is_better = false,
        .error_msg = "Timer not supported",
    };

    // Use nvidia-smi as NVML proxy
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const result = std.process.run(allocator, io, .{
            .argv = &.{ "nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits" },
        }) catch return BenchmarkResult{
            .name = "nvml_query_latency",
            .value = 0,
            .unit = "us",
            .higher_is_better = false,
            .error_msg = "nvidia-smi not found",
        };
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    const elapsed_ns = timer.read();
    const avg_us = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iterations)) / 1000.0;

    return BenchmarkResult{
        .name = "nvml_query_latency",
        .value = avg_us,
        .unit = "us",
        .higher_is_better = false,
        .error_msg = null,
    };
}

/// Measure GPU memory bandwidth using nvidia-smi or CUDA
fn benchMemoryBandwidth(allocator: std.mem.Allocator) !BenchmarkResult {
    const io = std.Options.debug_io;

    // Try to get memory clock and calculate theoretical bandwidth
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "nvidia-smi", "--query-gpu=memory.total,clocks.mem,memory.bus_width", "--format=csv,noheader,nounits" },
    }) catch return BenchmarkResult{
        .name = "memory_bandwidth",
        .value = 0,
        .unit = "GB/s",
        .higher_is_better = true,
        .error_msg = "nvidia-smi query failed",
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Parse: "24576, 10501, 384" (MiB, MHz, bits)
    var parts = std.mem.splitScalar(u8, std.mem.trim(u8, result.stdout, " \t\n\r"), ',');

    _ = parts.next(); // Skip total memory

    const mem_clock_str = std.mem.trim(u8, parts.next() orelse return error.ParseError, " ");
    const bus_width_str = std.mem.trim(u8, parts.next() orelse return error.ParseError, " ");

    const mem_clock = std.fmt.parseFloat(f64, mem_clock_str) catch 0;
    const bus_width = std.fmt.parseFloat(f64, bus_width_str) catch 0;

    // Theoretical bandwidth: Clock * 2 (DDR) * bus_width / 8 (bits to bytes) / 1000 (MHz to GHz)
    const bandwidth = (mem_clock * 2.0 * bus_width) / 8.0 / 1000.0;

    return BenchmarkResult{
        .name = "memory_bandwidth_theoretical",
        .value = bandwidth,
        .unit = "GB/s",
        .higher_is_better = true,
        .error_msg = null,
    };
}

/// Get GPU power draw
fn benchPowerDraw(allocator: std.mem.Allocator) !BenchmarkResult {
    const io = std.Options.debug_io;

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "nvidia-smi", "--query-gpu=power.draw", "--format=csv,noheader,nounits" },
    }) catch return BenchmarkResult{
        .name = "idle_power",
        .value = 0,
        .unit = "W",
        .higher_is_better = false,
        .error_msg = "nvidia-smi query failed",
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const power_str = std.mem.trim(u8, result.stdout, " \t\n\r");
    const power = std.fmt.parseFloat(f64, power_str) catch 0;

    return BenchmarkResult{
        .name = "idle_power",
        .value = power,
        .unit = "W",
        .higher_is_better = false,
        .error_msg = null,
    };
}

/// Get driver version info
fn getDriverInfo(allocator: std.mem.Allocator) !struct { version: []const u8, gpu: []const u8 } {
    const io = std.Options.debug_io;

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "nvidia-smi", "--query-gpu=driver_version,name", "--format=csv,noheader" },
    }) catch return .{ .version = "unknown", .gpu = "unknown" };
    defer allocator.free(result.stderr);

    var parts = std.mem.splitScalar(u8, std.mem.trim(u8, result.stdout, " \t\n\r"), ',');
    const version = std.mem.trim(u8, parts.next() orelse "unknown", " ");
    const gpu = std.mem.trim(u8, parts.next() orelse "unknown", " ");

    // Keep stdout allocated for the strings we return
    return .{
        .version = if (version.len > 0) version else "unknown",
        .gpu = if (gpu.len > 0) gpu else "unknown",
    };
}

/// Run full benchmark suite
pub fn runBenchmarks(allocator: std.mem.Allocator, writer: *std.Io.Writer) !BenchmarkReport {
    try writer.print("Running nvfury benchmarks...\n\n", .{});

    // Get system info
    const driver_info = try getDriverInfo(allocator);

    const io = std.Options.debug_io;
    const kernel_result = std.process.run(allocator, io, .{
        .argv = &.{ "uname", "-r" },
    }) catch null;

    var kernel_version: []const u8 = "unknown";
    if (kernel_result) |kr| {
        kernel_version = std.mem.trim(u8, kr.stdout, " \t\n\r");
        allocator.free(kr.stderr);
    }

    // Get timestamp
    const ts = std.posix.clock_gettime(.REALTIME) catch std.posix.timespec{ .sec = 0, .nsec = 0 };

    // Detect if this is nvfury build or stock
    const build_type = if (fetch.getInstalledDriverVersion() != null) blk: {
        // Check for nvfury modprobe config
        const fd = std.posix.openat(std.posix.AT.FDCWD, "/etc/modprobe.d/nvfury.conf", .{}, 0) catch {
            break :blk "stock";
        };
        std.posix.close(fd);
        break :blk "nvfury";
    } else "unknown";

    var report = BenchmarkReport{
        .driver_version = driver_info.version,
        .kernel_version = kernel_version,
        .gpu_name = driver_info.gpu,
        .build_type = build_type,
        .timestamp = ts.sec,
        .results = .{},
    };

    try writer.print("System Information:\n", .{});
    try writer.print("  Driver:  {s}\n", .{report.driver_version});
    try writer.print("  Kernel:  {s}\n", .{report.kernel_version});
    try writer.print("  GPU:     {s}\n", .{report.gpu_name});
    try writer.print("  Build:   {s}\n\n", .{report.build_type});

    // Run benchmarks
    try writer.print("Running tests...\n\n", .{});

    // 1. Module load time
    try writer.print("  [1/4] Module load time...", .{});
    const load_result = try benchModuleLoadTime(allocator);
    try report.results.append(allocator, load_result);
    if (load_result.error_msg) |err| {
        try writer.print(" SKIP ({s})\n", .{err});
    } else {
        try writer.print(" {d:.1} {s}\n", .{ load_result.value, load_result.unit });
    }

    // 2. NVML query latency
    try writer.print("  [2/4] NVML query latency...", .{});
    const nvml_result = try benchNvmlQueryLatency(allocator);
    try report.results.append(allocator, nvml_result);
    if (nvml_result.error_msg) |err| {
        try writer.print(" SKIP ({s})\n", .{err});
    } else {
        try writer.print(" {d:.1} {s}\n", .{ nvml_result.value, nvml_result.unit });
    }

    // 3. Memory bandwidth
    try writer.print("  [3/4] Memory bandwidth...", .{});
    const mem_result = try benchMemoryBandwidth(allocator);
    try report.results.append(allocator, mem_result);
    if (mem_result.error_msg) |err| {
        try writer.print(" SKIP ({s})\n", .{err});
    } else {
        try writer.print(" {d:.1} {s}\n", .{ mem_result.value, mem_result.unit });
    }

    // 4. Idle power
    try writer.print("  [4/4] Idle power draw...", .{});
    const power_result = try benchPowerDraw(allocator);
    try report.results.append(allocator, power_result);
    if (power_result.error_msg) |err| {
        try writer.print(" SKIP ({s})\n", .{err});
    } else {
        try writer.print(" {d:.1} {s}\n", .{ power_result.value, power_result.unit });
    }

    try writer.print("\nBenchmark complete.\n", .{});

    return report;
}

/// Compare two benchmark reports
pub fn compareReports(report_a: BenchmarkReport, report_b: BenchmarkReport, writer: *std.Io.Writer) !void {
    try writer.print("Benchmark Comparison\n", .{});
    try writer.print("---------------------------------------------------\n\n", .{});

    try writer.print("  {s: <20} {s: <15} {s: <15} {s}\n", .{ "Metric", report_a.build_type, report_b.build_type, "Diff" });
    try writer.print("  {s: <20} {s: <15} {s: <15} {s}\n", .{ "------", "-----", "-----", "----" });

    for (report_a.results.items) |result_a| {
        // Find matching result in report_b
        for (report_b.results.items) |result_b| {
            if (std.mem.eql(u8, result_a.name, result_b.name)) {
                if (result_a.error_msg != null or result_b.error_msg != null) {
                    continue;
                }

                const diff_pct = if (result_a.value != 0)
                    ((result_b.value - result_a.value) / result_a.value) * 100.0
                else
                    0;

                const better = if (result_a.higher_is_better)
                    diff_pct > 0
                else
                    diff_pct < 0;

                var diff_buf: [32]u8 = undefined;
                const diff_str = std.fmt.bufPrint(&diff_buf, "{s}{d:.1}%", .{
                    if (diff_pct >= 0) "+" else "",
                    diff_pct,
                }) catch "?";

                var val_a_buf: [16]u8 = undefined;
                var val_b_buf: [16]u8 = undefined;
                const val_a_str = std.fmt.bufPrint(&val_a_buf, "{d:.1}", .{result_a.value}) catch "?";
                const val_b_str = std.fmt.bufPrint(&val_b_buf, "{d:.1}", .{result_b.value}) catch "?";

                try writer.print("  {s: <20} {s: <15} {s: <15} {s} {s}\n", .{
                    result_a.name,
                    val_a_str,
                    val_b_str,
                    diff_str,
                    if (better) "(better)" else "",
                });
                break;
            }
        }
    }
}

/// Export report to file
pub fn exportReport(allocator: std.mem.Allocator, report: BenchmarkReport, output_path: []const u8) !void {
    const json = try report.toJson(allocator);
    defer allocator.free(json);

    const expanded_path = try config.expandPath(allocator, output_path);
    defer allocator.free(expanded_path);

    const fd = try std.posix.openat(std.posix.AT.FDCWD, expanded_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer std.posix.close(fd);

    const write_result = std.c.write(fd, json.ptr, json.len);
    if (write_result < 0) return error.WriteError;
}

test "benchmark module" {
    const result = BenchmarkResult{
        .name = "test",
        .value = 1.0,
        .unit = "ms",
        .higher_is_better = false,
        .error_msg = null,
    };
    _ = result;
}
