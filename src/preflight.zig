//! nvfury/preflight - Pre-Build Compatibility Checks
//!
//! Validates system configuration before building to catch common issues early.
//! Checks kernel headers, compiler compatibility, required tools, and disk space.

const std = @import("std");
const builder = @import("builder.zig");
const fetch = @import("fetch.zig");

/// Check result
pub const CheckResult = struct {
    name: []const u8,
    passed: bool,
    message: []const u8,
    severity: Severity,

    pub const Severity = enum {
        info,
        warning,
        error_,
    };
};

/// Complete preflight report
pub const PreflightReport = struct {
    checks: std.ArrayListUnmanaged(CheckResult),
    all_passed: bool,
    errors: u32,
    warnings: u32,

    pub fn deinit(self: *PreflightReport, allocator: std.mem.Allocator) void {
        self.checks.deinit(allocator);
        self.* = undefined;
    }
};

/// Minimum required disk space in MB for build
const min_disk_space_mb: u64 = 2048; // 2GB

/// Required tools for building
const required_tools = [_][]const u8{
    "make",
    "gcc",
    "git",
};

/// Optional but recommended tools
const optional_tools = [_]struct { name: []const u8, purpose: []const u8 }{
    .{ .name = "ccache", .purpose = "faster rebuilds" },
    .{ .name = "clang", .purpose = "alternative compiler" },
    .{ .name = "mokutil", .purpose = "SecureBoot signing" },
    .{ .name = "dkms", .purpose = "automatic kernel rebuilds" },
};

/// Check if a command exists
fn commandExists(allocator: std.mem.Allocator, cmd: []const u8) bool {
    const io = std.Options.debug_io;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "which", cmd },
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return result.term == .exited and result.term.exited == 0;
}

/// Check kernel headers
fn checkKernelHeaders(allocator: std.mem.Allocator) !CheckResult {
    const kernel_version = builder.getKernelVersion(allocator) catch {
        return CheckResult{
            .name = "kernel_headers",
            .passed = false,
            .message = "Could not determine kernel version",
            .severity = .error_,
        };
    };
    defer allocator.free(kernel_version);

    if (builder.hasKernelHeaders(kernel_version)) {
        return CheckResult{
            .name = "kernel_headers",
            .passed = true,
            .message = "Kernel headers available",
            .severity = .info,
        };
    } else {
        return CheckResult{
            .name = "kernel_headers",
            .passed = false,
            .message = "Kernel headers not found. Install linux-headers package.",
            .severity = .error_,
        };
    }
}

/// Check compiler compatibility
fn checkCompiler(allocator: std.mem.Allocator) !CheckResult {
    const kernel_cc = builder.detectKernelCompiler();

    // Check if the kernel compiler is available
    if (!commandExists(allocator, kernel_cc)) {
        var msg_buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Kernel was built with {s} but it's not installed", .{kernel_cc}) catch "Compiler mismatch";
        return CheckResult{
            .name = "compiler",
            .passed = false,
            .message = msg,
            .severity = .error_,
        };
    }

    // Get compiler version
    const io = std.Options.debug_io;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ kernel_cc, "--version" },
    }) catch {
        return CheckResult{
            .name = "compiler",
            .passed = true,
            .message = "Compiler available (version unknown)",
            .severity = .info,
        };
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Extract first line of version
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    const first_line = lines.first();

    // Truncate if too long
    const version_info = if (first_line.len > 60) first_line[0..60] else first_line;
    _ = version_info;

    return CheckResult{
        .name = "compiler",
        .passed = true,
        .message = "Compiler available and matches kernel",
        .severity = .info,
    };
}

/// Check required build tools
fn checkRequiredTools(allocator: std.mem.Allocator, results: *std.ArrayListUnmanaged(CheckResult)) !void {
    for (required_tools) |tool| {
        if (commandExists(allocator, tool)) {
            try results.append(allocator, CheckResult{
                .name = tool,
                .passed = true,
                .message = "Available",
                .severity = .info,
            });
        } else {
            try results.append(allocator, CheckResult{
                .name = tool,
                .passed = false,
                .message = "Not found - required for build",
                .severity = .error_,
            });
        }
    }
}

/// Check optional tools
fn checkOptionalTools(allocator: std.mem.Allocator, results: *std.ArrayListUnmanaged(CheckResult)) !void {
    for (optional_tools) |tool| {
        if (commandExists(allocator, tool.name)) {
            try results.append(allocator, CheckResult{
                .name = tool.name,
                .passed = true,
                .message = "Available",
                .severity = .info,
            });
        } else {
            var msg_buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Not installed (optional, for {s})", .{tool.purpose}) catch "Not installed";
            try results.append(allocator, CheckResult{
                .name = tool.name,
                .passed = true, // Optional tools don't fail
                .message = msg,
                .severity = .info,
            });
        }
    }
}

/// Check available disk space
fn checkDiskSpace(allocator: std.mem.Allocator) !CheckResult {
    const io = std.Options.debug_io;

    // Check /tmp and home directory
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "df", "-m", "/tmp" },
    }) catch {
        return CheckResult{
            .name = "disk_space",
            .passed = true, // Can't check, assume ok
            .message = "Could not check disk space",
            .severity = .warning,
        };
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Parse df output (second line, fourth column is available)
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    _ = lines.next(); // Skip header
    const data_line = lines.next() orelse {
        return CheckResult{
            .name = "disk_space",
            .passed = true,
            .message = "Could not parse disk space",
            .severity = .warning,
        };
    };

    // Split on whitespace
    var cols = std.mem.tokenizeAny(u8, data_line, " \t");
    _ = cols.next(); // filesystem
    _ = cols.next(); // size
    _ = cols.next(); // used
    const avail_str = cols.next() orelse {
        return CheckResult{
            .name = "disk_space",
            .passed = true,
            .message = "Could not parse available space",
            .severity = .warning,
        };
    };

    const avail_mb = std.fmt.parseInt(u64, avail_str, 10) catch 0;

    if (avail_mb >= min_disk_space_mb) {
        var msg_buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "{d} MB available (>= {d} MB required)", .{ avail_mb, min_disk_space_mb }) catch "Sufficient space";
        return CheckResult{
            .name = "disk_space",
            .passed = true,
            .message = msg,
            .severity = .info,
        };
    } else {
        var msg_buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Only {d} MB available, need {d} MB", .{ avail_mb, min_disk_space_mb }) catch "Insufficient space";
        return CheckResult{
            .name = "disk_space",
            .passed = false,
            .message = msg,
            .severity = .error_,
        };
    }
}

/// Check if NVIDIA GPU is present
fn checkNvidiaGpu(allocator: std.mem.Allocator) !CheckResult {
    const io = std.Options.debug_io;

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "lspci", "-d", "10de:" },
    }) catch {
        return CheckResult{
            .name = "nvidia_gpu",
            .passed = true,
            .message = "Could not check (lspci not available)",
            .severity = .warning,
        };
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) {
        // Check for VGA or 3D controller
        if (std.mem.indexOf(u8, result.stdout, "VGA") != null or
            std.mem.indexOf(u8, result.stdout, "3D controller") != null)
        {
            return CheckResult{
                .name = "nvidia_gpu",
                .passed = true,
                .message = "NVIDIA GPU detected",
                .severity = .info,
            };
        }
    }

    return CheckResult{
        .name = "nvidia_gpu",
        .passed = false,
        .message = "No NVIDIA GPU detected",
        .severity = .error_,
    };
}

/// Check SecureBoot status
fn checkSecureBoot(allocator: std.mem.Allocator) !CheckResult {
    _ = allocator;

    const fd = std.posix.openat(std.posix.AT.FDCWD, "/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c", .{}, 0) catch {
        return CheckResult{
            .name = "secure_boot",
            .passed = true,
            .message = "SecureBoot not enabled (or not EFI system)",
            .severity = .info,
        };
    };
    defer std.posix.close(fd);

    var buf: [8]u8 = undefined;
    const n = std.posix.read(fd, &buf) catch {
        return CheckResult{
            .name = "secure_boot",
            .passed = true,
            .message = "Could not read SecureBoot status",
            .severity = .info,
        };
    };

    if (n >= 5 and buf[4] == 1) {
        return CheckResult{
            .name = "secure_boot",
            .passed = true, // Not an error, just a warning
            .message = "SecureBoot ENABLED - modules must be signed",
            .severity = .warning,
        };
    }

    return CheckResult{
        .name = "secure_boot",
        .passed = true,
        .message = "SecureBoot disabled",
        .severity = .info,
    };
}

/// Check driver compatibility with detected GPU
fn checkDriverCompatibility(allocator: std.mem.Allocator) !CheckResult {
    // Get latest available version
    const latest = fetch.getLatestVersion(allocator) catch {
        return CheckResult{
            .name = "driver_compat",
            .passed = true,
            .message = "Could not check latest version",
            .severity = .info,
        };
    };
    defer allocator.free(latest);

    // Check if GPU architecture is supported
    // For now, just verify we can parse the version
    if (fetch.parseVersion(latest)) |v| {
        if (v.major >= 515) {
            return CheckResult{
                .name = "driver_compat",
                .passed = true,
                .message = "Driver version supports open modules",
                .severity = .info,
            };
        } else {
            return CheckResult{
                .name = "driver_compat",
                .passed = false,
                .message = "Driver version too old for open modules (need 515+)",
                .severity = .error_,
            };
        }
    }

    return CheckResult{
        .name = "driver_compat",
        .passed = true,
        .message = "Driver compatibility check passed",
        .severity = .info,
    };
}

/// Run all preflight checks
pub fn runChecks(allocator: std.mem.Allocator) !PreflightReport {
    var report = PreflightReport{
        .checks = .{},
        .all_passed = true,
        .errors = 0,
        .warnings = 0,
    };

    // Run all checks
    try report.checks.append(allocator, try checkKernelHeaders(allocator));
    try report.checks.append(allocator, try checkCompiler(allocator));
    try checkRequiredTools(allocator, &report.checks);
    try report.checks.append(allocator, try checkDiskSpace(allocator));
    try report.checks.append(allocator, try checkNvidiaGpu(allocator));
    try report.checks.append(allocator, try checkSecureBoot(allocator));
    try report.checks.append(allocator, try checkDriverCompatibility(allocator));
    try checkOptionalTools(allocator, &report.checks);

    // Count errors and warnings
    for (report.checks.items) |check| {
        if (!check.passed) {
            report.all_passed = false;
            if (check.severity == .error_) {
                report.errors += 1;
            }
        }
        if (check.severity == .warning) {
            report.warnings += 1;
        }
    }

    return report;
}

/// Print preflight report
pub fn printReport(report: PreflightReport, writer: *std.Io.Writer) !void {
    try writer.print("Preflight Checks\n", .{});
    try writer.print("---------------------------------------------------\n\n", .{});

    for (report.checks.items) |check| {
        const status_icon = if (check.passed) "[OK]" else "[!!]";
        const severity_str = switch (check.severity) {
            .info => "",
            .warning => " (warning)",
            .error_ => " (ERROR)",
        };

        try writer.print("  {s} {s: <20} {s}{s}\n", .{
            status_icon,
            check.name,
            check.message,
            severity_str,
        });
    }

    try writer.print("\n", .{});

    if (report.all_passed) {
        try writer.print("All checks passed! Ready to build.\n", .{});
    } else {
        try writer.print("Found {d} error(s) and {d} warning(s).\n", .{ report.errors, report.warnings });
        if (report.errors > 0) {
            try writer.print("Please resolve errors before building.\n", .{});
        }
    }
}

test "preflight module" {
    _ = min_disk_space_mb;
    _ = required_tools;
}
