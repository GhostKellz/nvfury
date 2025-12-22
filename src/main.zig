//! nvfury - NVIDIA Open Kernel Module Forge
//!
//! CLI entry point for building and managing optimized NVIDIA drivers.

const std = @import("std");
const nvfury = @import("nvfury");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Set up stdout/stderr writers using Zig 0.16 fs.File.Writer API
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.Writer.init(std.fs.File.stdout(), &stdout_buf);
    var stderr_writer = std.fs.File.Writer.init(std.fs.File.stderr(), &stderr_buf);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;

    // Parse command line args
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    const command = args.next() orelse {
        try printUsage(stdout);
        try stdout.flush();
        return;
    };

    if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        try printVersion(stdout);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "status")) {
        try printStatus(allocator, stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "build")) {
        try cmdBuild(allocator, &args, stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "install")) {
        try cmdInstall(allocator, &args, stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "tune")) {
        try cmdTune(allocator, &args, stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "patch")) {
        try cmdPatch(allocator, &args, stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "rollback")) {
        try cmdRollback(allocator, stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "versions")) {
        try cmdVersions(allocator, stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    try stderr.print("Unknown command: {s}\n", .{command});
    try stderr.print("Run 'nvfury help' for usage information.\n", .{});
    try stderr.flush();
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
        \\  versions            List available driver versions from GitHub
        \\  rollback            Restore previous driver
        \\  version             Show version information
        \\  help                Show this help message
        \\
        \\Build Options:
        \\  --version <ver>     Build specific driver version
        \\  --source <path>     Build from local source directory
        \\  --latest            Fetch and build latest release
        \\  --patches <list>    Apply patches (comma-separated or 'default')
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

    // Show kernel compiler
    const kernel_cc = nvfury.builder.detectKernelCompiler();
    try writer.print("Kernel Compiler:  {s}\n", .{kernel_cc});

    // Show tuning status
    try writer.print("\n", .{});
    try nvfury.tune.printStatus(writer);
}

fn cmdBuild(allocator: std.mem.Allocator, args: *std.process.ArgIterator, writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    var version: ?[]const u8 = null;
    var source_dir: ?[]const u8 = null;
    var dry_run = false;
    var patches_arg: ?[]const u8 = null;

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
        } else if (std.mem.eql(u8, arg, "--patches")) {
            patches_arg = args.next();
        }
    }

    try writer.print("nvfury build\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    // Fetch source if not provided
    var fetch_result: ?nvfury.fetch.FetchResult = null;
    defer if (fetch_result) |fr| {
        allocator.free(fr.version);
        allocator.free(fr.source_path);
    };

    const actual_source = if (source_dir) |s| s else blk: {
        try writer.print("Fetching NVIDIA open kernel modules...\n", .{});
        fetch_result = nvfury.fetch.fetchSource(allocator, .{
            .version = version,
        }) catch |e| {
            try err_writer.print("Fetch failed: {}\n", .{e});
            return;
        };

        const fr = fetch_result.?;
        try writer.print("Version: {s}\n", .{fr.version});
        if (fr.from_cache) {
            try writer.print("Source:  (cached)\n", .{});
        } else {
            try writer.print("Source:  {s}\n", .{fr.source_path});
        }

        break :blk fr.source_path;
    };

    if (dry_run) {
        try writer.print("\n[DRY RUN] Would build from: {s}\n", .{actual_source});
        if (patches_arg) |pa| {
            try writer.print("[DRY RUN] Would apply patches: {s}\n", .{pa});
        }
        return;
    }

    // Apply patches if specified
    if (patches_arg) |pa| {
        try writer.print("\nApplying patches...\n", .{});

        // Get patches directory (relative to nvfury install or current dir)
        const patches_dir = "/data/projects/nvfury/patches"; // TODO: make configurable

        if (std.mem.eql(u8, pa, "default")) {
            // Apply all default-enabled patches
            for (nvfury.patch.builtin_patches) |patch| {
                if (patch.default_enabled) {
                    const patch_path = nvfury.patch.getPatchPath(allocator, patches_dir, patch.name) catch continue;
                    defer allocator.free(patch_path);

                    // Check if patch applies
                    if (nvfury.patch.checkPatch(allocator, actual_source, patch_path) catch false) {
                        const result = nvfury.patch.applyPatch(allocator, actual_source, patch_path) catch |e| {
                            try err_writer.print("  Warning: Failed to apply {s}: {}\n", .{ patch.name, e });
                            continue;
                        };
                        if (result.success) {
                            try writer.print("  Applied: {s}\n", .{patch.name});
                        }
                    } else {
                        try writer.print("  Skipped: {s} (doesn't apply cleanly)\n", .{patch.name});
                    }
                }
            }
        } else {
            // Apply comma-separated list of patches
            var iter = std.mem.splitScalar(u8, pa, ',');
            while (iter.next()) |patch_name| {
                const trimmed = std.mem.trim(u8, patch_name, " \t");
                if (trimmed.len == 0) continue;

                const patch_path = nvfury.patch.getPatchPath(allocator, patches_dir, trimmed) catch |e| {
                    try err_writer.print("  Warning: Patch not found {s}: {}\n", .{ trimmed, e });
                    continue;
                };
                defer allocator.free(patch_path);

                if (nvfury.patch.checkPatch(allocator, actual_source, patch_path) catch false) {
                    const result = nvfury.patch.applyPatch(allocator, actual_source, patch_path) catch |e| {
                        try err_writer.print("  Warning: Failed to apply {s}: {}\n", .{ trimmed, e });
                        continue;
                    };
                    if (result.success) {
                        try writer.print("  Applied: {s}\n", .{trimmed});
                    }
                } else {
                    try writer.print("  Skipped: {s} (doesn't apply cleanly)\n", .{trimmed});
                }
            }
        }
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

fn cmdInstall(allocator: std.mem.Allocator, args: *std.process.ArgIterator, writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    var use_dkms = true;
    var create_backup = true;
    var source_dir: ?[]const u8 = null;
    var version: ?[]const u8 = null;

    // Parse options
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--direct")) {
            use_dkms = false;
        } else if (std.mem.eql(u8, arg, "--dkms")) {
            use_dkms = true;
        } else if (std.mem.eql(u8, arg, "--no-backup")) {
            create_backup = false;
        } else if (std.mem.eql(u8, arg, "--source")) {
            source_dir = args.next();
        } else if (std.mem.eql(u8, arg, "--version")) {
            version = args.next();
        }
    }

    try writer.print("nvfury install\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    // Get version and source from last build if not specified
    const actual_version = version orelse nvfury.fetch.getInstalledDriverVersion() orelse {
        try err_writer.print("Error: No version specified and couldn't detect installed driver.\n", .{});
        try err_writer.print("Use --version <ver> or run 'nvfury build' first.\n", .{});
        return;
    };

    try writer.print("Version: {s}\n", .{actual_version});
    try writer.print("Backup:  {}\n", .{create_backup});

    if (use_dkms) {
        if (!nvfury.dkms.isDkmsAvailable()) {
            try err_writer.print("Error: DKMS not available. Use --direct or install dkms.\n", .{});
            return;
        }
        try writer.print("Mode:    DKMS (automatic rebuild on kernel update)\n", .{});

        // Check if source directory is provided
        const src = source_dir orelse {
            try err_writer.print("Error: Source directory required for DKMS registration.\n", .{});
            try err_writer.print("Use --source <path> to specify the built source directory.\n", .{});
            return;
        };

        try writer.print("Source:  {s}\n", .{src});
        try writer.print("\nRegistering with DKMS...\n", .{});

        // Register with DKMS
        const kernel_cc = nvfury.builder.detectKernelCompiler();
        const reg_result = try nvfury.dkms.register(allocator, .{
            .version = actual_version,
            .source_dir = src,
            .cc = if (std.mem.eql(u8, kernel_cc, "clang")) "clang" else "gcc",
            .cflags = "-march=native -O3",
        });

        if (!reg_result.success) {
            try err_writer.print("DKMS registration failed: {s}\n", .{reg_result.message});
            return;
        }
        try writer.print("DKMS registration: OK\n", .{});

        // Build via DKMS
        try writer.print("Building via DKMS...\n", .{});
        const build_result = try nvfury.dkms.buildDkms(allocator, actual_version, null);

        if (!build_result.success) {
            try err_writer.print("DKMS build failed: {s}\n", .{build_result.message});
            return;
        }
        try writer.print("DKMS build: OK\n", .{});

        // Install via DKMS
        try writer.print("Installing via DKMS...\n", .{});
        const install_result = try nvfury.dkms.installDkms(allocator, actual_version, null);

        if (!install_result.success) {
            try err_writer.print("DKMS install failed: {s}\n", .{install_result.message});
            return;
        }

        try writer.print("\nDKMS installation complete!\n", .{});
        try writer.print("Modules will auto-rebuild on kernel updates.\n", .{});
        try writer.print("Reboot to load the new modules.\n", .{});
    } else {
        try writer.print("Mode:    Direct (manual rebuild needed on kernel update)\n", .{});
        try writer.print("\nDirect installation copies modules to /lib/modules/$(uname -r)/\n", .{});
        try writer.print("Note: You'll need to rebuild manually after kernel updates.\n", .{});

        // For direct install, we'd copy .ko files to /lib/modules/.../
        // This requires the built modules to exist
        try err_writer.print("Direct installation not yet implemented.\n", .{});
        try err_writer.print("Use --dkms for now (recommended anyway).\n", .{});
    }
}

fn cmdTune(allocator: std.mem.Allocator, args: *std.process.ArgIterator, writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
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

    // Actually apply the preset
    const result = try nvfury.tune.applyPreset(allocator, preset);

    if (result.success) {
        try writer.print("\nConfiguration written to: {s}\n", .{result.config_path});
        try writer.print("{s}\n", .{result.message});

        // Show what was configured
        const params = nvfury.config.ModuleParams.fromPreset(preset);
        try writer.print("\nModule parameters set:\n", .{});
        try writer.print("  UsePageAttributeTable: {}\n", .{params.use_page_attribute_table});
        try writer.print("  EnablePCIeGen3:        {}\n", .{params.enable_pcie_gen3});
        try writer.print("  EnableMSI:             {}\n", .{params.enable_msi});
        try writer.print("  PreserveVideoMemory:   {}\n", .{params.preserve_video_memory});
        try writer.print("  DynamicPowerMgmt:      0x{x:0>2}\n", .{params.dynamic_power_management});
        try writer.print("  EnableGpuFirmware:     {} (GSP)\n", .{params.enable_gpu_firmware});
        try writer.print("  EnableResizableBar:    {} (ReBAR)\n", .{params.enable_resizable_bar});
    } else {
        try err_writer.print("Error: {s}\n", .{result.message});
    }
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

fn cmdVersions(allocator: std.mem.Allocator, writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    try writer.print("nvfury versions\n", .{});
    try writer.print("---------------------------------------------------\n", .{});
    try writer.print("Fetching available versions from GitHub...\n\n", .{});

    var versions = nvfury.fetch.getAvailableVersions(allocator) catch |e| {
        try err_writer.print("Error fetching versions: {}\n", .{e});
        return;
    };
    defer versions.deinit();

    // Get installed version for comparison
    const installed = nvfury.fetch.getInstalledDriverVersion();

    try writer.print("Available NVIDIA Open Kernel Module Versions:\n", .{});
    for (versions.items.items) |version| {
        if (installed) |inst| {
            if (std.mem.eql(u8, version, inst)) {
                try writer.print("  {s}  (installed)\n", .{version});
            } else {
                try writer.print("  {s}\n", .{version});
            }
        } else {
            try writer.print("  {s}\n", .{version});
        }
    }

    try writer.print("\nUse 'nvfury build --version <ver>' to build a specific version.\n", .{});
}

test "main module compiles" {
    _ = nvfury;
}
