//! nvfury - NVIDIA Open Kernel Module Forge
//!
//! CLI entry point for building and managing optimized NVIDIA drivers.

const std = @import("std");
const nvfury = @import("nvfury");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);

    // Parse command line args
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    const command = args.next() orelse {
        try printUsage(&stdout.interface);
        try stdout.interface.flush();
        return;
    };

    if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        try printVersion(&stdout.interface);
        try stdout.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printUsage(&stdout.interface);
        try stdout.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "status")) {
        try printStatus(allocator, &stdout.interface, &stderr.interface);
        try stdout.interface.flush();
        try stderr.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "build")) {
        try cmdBuild(allocator, &args, &stdout.interface, &stderr.interface);
        try stdout.interface.flush();
        try stderr.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "install")) {
        try cmdInstall(allocator, &args, &stdout.interface, &stderr.interface);
        try stdout.interface.flush();
        try stderr.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "tune")) {
        try cmdTune(allocator, &args, &stdout.interface, &stderr.interface);
        try stdout.interface.flush();
        try stderr.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "patch")) {
        try cmdPatch(allocator, &args, &stdout.interface, &stderr.interface);
        try stdout.interface.flush();
        try stderr.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "rollback")) {
        try cmdRollback(allocator, &stdout.interface, &stderr.interface);
        try stdout.interface.flush();
        try stderr.interface.flush();
        return;
    }

    try stderr.interface.print("Unknown command: {s}\n", .{command});
    try stderr.interface.print("Run 'nvfury help' for usage information.\n", .{});
    try stderr.interface.flush();
}

fn printVersion(writer: *std.Io.Writer) !void {
    try writer.print("nvfury {s}\n", .{nvfury.version.string});
    try writer.print("NVIDIA Open Kernel Module Forge\n", .{});
}

fn printUsage(writer: *std.Io.Writer) !void {
    try writer.print(
        \\nvfury - NVIDIA Open Kernel Module Forge
        \\
        \\Performance-tuned NVIDIA open driver builder for Linux gaming.
        \\
        \\Usage: nvfury <command> [options]
        \\
        \\Commands:
        \\  build               Fetch and build optimized NVIDIA modules
        \\  install             Install built modules
        \\  tune <preset>       Apply module parameter preset
        \\  patch <subcommand>  Manage patches
        \\  status              Show current driver status
        \\  rollback            Restore previous driver
        \\  version             Show version information
        \\  help                Show this help message
        \\
        \\Build Options:
        \\  --version <ver>     Build specific driver version
        \\  --source <path>     Build from local source directory
        \\  --latest            Fetch and build latest release
        \\  --dry-run           Show what would be done
        \\
        \\Install Options:
        \\  --dkms              Install via DKMS (auto-rebuild on kernel update)
        \\  --direct            Install directly (manual rebuild needed)
        \\  --no-backup         Skip backup of existing modules
        \\
        \\Tune Presets:
        \\  gaming              Low latency, max performance (default)
        \\  balanced            Balance of performance and efficiency
        \\  quiet               Power saving, reduced heat/noise
        \\  benchmark           Maximum performance for testing
        \\
        \\Patch Subcommands:
        \\  patch list          List available patches
        \\  patch apply <name>  Apply a patch
        \\  patch status        Show applied patches
        \\
        \\Examples:
        \\  nvfury build                    # Build latest version
        \\  nvfury build --version 580.105.08
        \\  sudo nvfury install --dkms
        \\  sudo nvfury tune gaming
        \\  nvfury status
        \\
        \\For more information: https://github.com/GhostKellz/nvfury
        \\
    , .{});
}

fn printStatus(allocator: std.mem.Allocator, writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    try writer.print("nvfury {s}\n", .{nvfury.version.string});
    try writer.print("---------------------------------------------------\n", .{});

    // Get installed driver version
    if (nvfury.fetch.getInstalledDriverVersion()) |version| {
        try writer.print("Installed Driver: {s}\n", .{version});
    } else {
        try writer.print("Installed Driver: (not detected)\n", .{});
    }

    // Get kernel version
    const kernel_version = nvfury.builder.getKernelVersion(allocator) catch {
        try err_writer.print("Warning: Could not detect kernel version\n", .{});
        return;
    };
    defer allocator.free(kernel_version);

    try writer.print("Kernel Version:   {s}\n", .{kernel_version});

    // Check kernel headers
    if (nvfury.builder.hasKernelHeaders(kernel_version)) {
        try writer.print("Kernel Headers:   Available\n", .{});
    } else {
        try writer.print("Kernel Headers:   NOT FOUND\n", .{});
        try err_writer.print("Warning: Kernel headers not found. Install linux-headers.\n", .{});
    }

    // Check DKMS
    if (nvfury.dkms.isDkmsAvailable()) {
        try writer.print("DKMS:             Available\n", .{});
    } else {
        try writer.print("DKMS:             Not installed\n", .{});
    }

    // Show tuning status
    try writer.print("\n", .{});
    try nvfury.tune.printStatus(writer);
}

fn cmdBuild(allocator: std.mem.Allocator, args: *std.process.ArgIterator, writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    var version: ?[]const u8 = null;
    var source_dir: ?[]const u8 = null;
    var dry_run = false;

    // Parse options
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--version")) {
            version = args.next();
        } else if (std.mem.eql(u8, arg, "--source")) {
            source_dir = args.next();
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--latest")) {
            version = null; // Fetch latest
        }
    }

    try writer.print("nvfury build\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    // Fetch source if not provided
    const actual_source = if (source_dir) |s| s else blk: {
        try writer.print("Fetching NVIDIA open kernel modules...\n", .{});
        const fetch_result = nvfury.fetch.fetchSource(allocator, .{
            .version = version,
        }) catch |e| {
            try err_writer.print("Fetch failed: {}\n", .{e});
            return;
        };

        try writer.print("Version: {s}\n", .{fetch_result.version});
        if (fetch_result.from_cache) {
            try writer.print("Source:  (cached)\n", .{});
        } else {
            try writer.print("Source:  {s}\n", .{fetch_result.source_path});
        }

        break :blk fetch_result.source_path;
    };

    if (dry_run) {
        try writer.print("\n[DRY RUN] Would build from: {s}\n", .{actual_source});
        return;
    }

    // Build
    try writer.print("\nBuilding modules...\n", .{});

    const build_result = nvfury.builder.build(allocator, .{
        .source_dir = actual_source,
        .output_dir = actual_source,
        .dry_run = dry_run,
    }) catch |e| {
        try err_writer.print("Build failed: {}\n", .{e});
        return;
    };

    if (build_result.success) {
        const duration_s = @as(f64, @floatFromInt(build_result.duration_ns)) / 1_000_000_000.0;
        try writer.print("Build completed in {d:.1}s\n", .{duration_s});
        try writer.print("Output: {s}\n", .{build_result.output_path});
        try writer.print("\nRun 'sudo nvfury install' to install the built modules.\n", .{});
    } else {
        try err_writer.print("Build failed: {s}\n", .{build_result.error_message orelse "unknown error"});
    }
}

fn cmdInstall(_: std.mem.Allocator, args: *std.process.ArgIterator, writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    _ = err_writer;
    var use_dkms = true;
    var create_backup = true;

    // Parse options
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--direct")) {
            use_dkms = false;
        } else if (std.mem.eql(u8, arg, "--dkms")) {
            use_dkms = true;
        } else if (std.mem.eql(u8, arg, "--no-backup")) {
            create_backup = false;
        }
    }

    try writer.print("nvfury install\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    if (use_dkms) {
        if (!nvfury.dkms.isDkmsAvailable()) {
            try writer.print("Error: DKMS not available. Use --direct or install dkms.\n", .{});
            return;
        }
        try writer.print("Mode: DKMS (automatic rebuild on kernel update)\n", .{});
    } else {
        try writer.print("Mode: Direct (manual rebuild needed on kernel update)\n", .{});
    }

    try writer.print("Backup: {}\n", .{create_backup});
    try writer.print("\nNote: Full installation requires built modules.\n", .{});
    try writer.print("Run 'nvfury build' first if you haven't already.\n", .{});
}

fn cmdTune(allocator: std.mem.Allocator, args: *std.process.ArgIterator, writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    _ = allocator;

    const subcommand = args.next() orelse "status";

    if (std.mem.eql(u8, subcommand, "status")) {
        try nvfury.tune.printStatus(writer);
        return;
    }

    // Parse preset name
    const preset: nvfury.config.TunePreset = if (std.mem.eql(u8, subcommand, "gaming"))
        .gaming
    else if (std.mem.eql(u8, subcommand, "balanced"))
        .balanced
    else if (std.mem.eql(u8, subcommand, "quiet"))
        .quiet
    else if (std.mem.eql(u8, subcommand, "benchmark"))
        .benchmark
    else {
        try err_writer.print("Unknown preset: {s}\n", .{subcommand});
        try err_writer.print("Available: gaming, balanced, quiet, benchmark\n", .{});
        return;
    };

    try writer.print("Applying preset: {s}\n", .{@tagName(preset)});
    try writer.print("Description: {s}\n", .{preset.description()});
    try writer.print("\nNote: Run with sudo to apply changes.\n", .{});
}

fn cmdPatch(allocator: std.mem.Allocator, args: *std.process.ArgIterator, writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    _ = allocator;
    _ = err_writer;

    const subcommand = args.next() orelse "list";

    if (std.mem.eql(u8, subcommand, "list")) {
        try writer.print("Available Patches:\n", .{});
        try writer.print("---------------------------------------------------\n", .{});

        for (nvfury.patch.builtin_patches) |p| {
            try writer.print("{s}\n", .{p.name});
            try writer.print("  {s}\n", .{p.description});
            try writer.print("  Category: {s} | Default: {}\n\n", .{ @tagName(p.category), p.default_enabled });
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "apply")) {
        const patch_name = args.next() orelse {
            try writer.print("Usage: nvfury patch apply <patch-name>\n", .{});
            return;
        };
        try writer.print("Applying patch: {s}\n", .{patch_name});
        try writer.print("Note: Requires source directory from build.\n", .{});
        return;
    }

    try writer.print("Unknown patch subcommand: {s}\n", .{subcommand});
}

fn cmdRollback(allocator: std.mem.Allocator, writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    _ = allocator;
    _ = err_writer;

    try writer.print("nvfury rollback\n", .{});
    try writer.print("---------------------------------------------------\n", .{});
    try writer.print("Looking for available backups...\n", .{});
    try writer.print("\nNote: Rollback functionality requires a previous backup.\n", .{});
    try writer.print("Backups are created during 'nvfury install'.\n", .{});
}

test "main module compiles" {
    _ = nvfury;
}
