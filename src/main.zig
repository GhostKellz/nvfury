//! nvfury - NVIDIA Open Kernel Module Forge
//!
//! CLI entry point for building and managing optimized NVIDIA drivers.

const std = @import("std");
const Io = std.Io;
const nvfury = @import("nvfury");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    // Set up stdout/stderr writers using Zig 0.16 Io.File.Writer API
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buf);
    var stderr_writer = Io.File.stderr().writer(io, &stderr_buf);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;

    // Parse command line args using Zig 0.16 API
    const args = try init.minimal.args.toSlice(allocator);

    // Skip program name
    if (args.len < 2) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }

    const command = args[1];

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
        try cmdBuild(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "install")) {
        try cmdInstall(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "tune")) {
        try cmdTune(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "patch")) {
        try cmdPatch(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "rollback")) {
        try cmdRollback(allocator, args[2..], stdout, stderr);
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

    if (std.mem.eql(u8, command, "recommend")) {
        try cmdRecommend(stdout);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "check-update") or std.mem.eql(u8, command, "update-check")) {
        try cmdCheckUpdate(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "update-daemon") or std.mem.eql(u8, command, "daemon")) {
        try cmdUpdateDaemon(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "build-cache")) {
        try cmdBuildCache(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "prime")) {
        try cmdPrime(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "sign")) {
        try cmdSign(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "benchmark")) {
        try cmdBenchmark(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "config")) {
        try cmdConfig(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "preflight") or std.mem.eql(u8, command, "check")) {
        try cmdPreflight(allocator, stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "cache")) {
        try cmdCache(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "profile")) {
        try cmdProfile(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "gpus")) {
        try cmdGpus(stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    if (std.mem.eql(u8, command, "uninstall")) {
        try cmdUninstall(allocator, args[2..], stdout, stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    try stderr.print("Unknown command: {s}\n", .{command});
    try stderr.print("Run 'nvfury help' for usage information.\n", .{});
    try stderr.flush();
}

fn printVersion(writer: *Io.Writer) !void {
    try writer.print("nvfury {s}\n", .{nvfury.version.string});
    try writer.print("NVIDIA Open Kernel Module Forge\n", .{});
}

fn printUsage(writer: *Io.Writer) !void {
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
        \\  profile <subcommand> Export/import tuning profiles (JSON)
        \\  gpus                Detect and list all GPUs (multi-GPU support)
        \\  recommend           Show recommended patches for your GPU
        \\  status              Show current driver status
        \\  versions            List available driver versions from GitHub
        \\  rollback            Restore previous driver
        \\  uninstall           Remove nvfury-installed drivers
        \\  check-update        Check for available driver updates
        \\  update-daemon       Manage automatic update checking (systemd timer)
        \\  prime <subcommand>  Manage hybrid graphics (PRIME offload)
        \\  sign <subcommand>   SecureBoot module signing
        \\  benchmark <subcmd>  Performance benchmarking
        \\  config <subcommand> Configuration management
        \\  preflight           Pre-build compatibility checks
        \\  cache               Manage ccache for compilation
        \\  build-cache         Manage source hash cache (skip redundant rebuilds)
        \\  version             Show version information
        \\  help                Show this help message
        \\
        \\Profile Subcommands:
        \\  profile list              List available presets
        \\  profile show <preset>     Show preset parameters
        \\  profile export <preset> <file>  Export preset to JSON
        \\  profile import <file>     Import and preview profile
        \\  profile import <file> --apply   Import and apply profile
        \\
        \\Cache Subcommands (ccache):
        \\  cache status        Show ccache statistics
        \\  cache clear         Clear ccache
        \\
        \\Build Cache Subcommands (source hash):
        \\  build-cache status  Show cached builds and source hashes
        \\  build-cache clear   Clear all cached build metadata
        \\
        \\Update Daemon Subcommands:
        \\  update-daemon enable   Install systemd timer for auto-checking
        \\  update-daemon disable  Remove systemd timer
        \\  update-daemon status   Show timer status and last check
        \\
        \\PRIME (Hybrid Graphics) Subcommands:
        \\  prime status        Show current graphics mode
        \\  prime offload <cmd> Run application on NVIDIA GPU
        \\  prime setup         Configure PRIME (X11/modprobe/udev)
        \\
        \\SecureBoot Signing Subcommands:
        \\  sign status         Show signing key status
        \\  sign setup          Generate MOK signing key
        \\  sign enroll         Enroll MOK certificate (requires reboot)
        \\
        \\Benchmark Subcommands:
        \\  benchmark run       Run performance benchmark suite
        \\  benchmark export <file>  Export results to JSON
        \\
        \\Config Subcommands:
        \\  config show         Show current configuration
        \\  config set <k> <v>  Set configuration value
        \\  config reset        Reset to defaults
        \\
        \\Build Options:
        \\  --version <ver>     Build specific driver version
        \\  --source <path>     Build from local source directory
        \\  --latest            Fetch and build latest release
        \\  --patches <list>    Apply patches (comma-separated or 'default')
        \\  --force, -f         Force rebuild even if source unchanged
        \\  --dry-run           Show what would be done
        \\
        \\Check-Update Options:
        \\  --notify            Send desktop notification if update available
        \\  --force, -f         Check even if recently checked
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

fn printStatus(allocator: std.mem.Allocator, writer: *Io.Writer, err_writer: *Io.Writer) !void {
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

fn cmdBuild(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    var version: ?[]const u8 = null;
    var source_dir: ?[]const u8 = null;
    var dry_run = false;
    var patches_arg: ?[]const u8 = null;
    var force_rebuild = false;

    // Parse options
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--version")) {
            i += 1;
            if (i < args.len) version = args[i];
        } else if (std.mem.eql(u8, arg, "--source")) {
            i += 1;
            if (i < args.len) source_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--latest")) {
            version = null; // Fetch latest
        } else if (std.mem.eql(u8, arg, "--patches")) {
            i += 1;
            if (i < args.len) patches_arg = args[i];
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            force_rebuild = true;
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

    // Get version for cache lookup
    const build_version = if (fetch_result) |fr| fr.version else version orelse "unknown";

    // Get kernel version for cache comparison
    const kernel_version = nvfury.builder.getKernelVersion(allocator) catch "unknown";
    defer if (!std.mem.eql(u8, kernel_version, "unknown")) allocator.free(kernel_version);

    // Check build cache (skip if force rebuild)
    if (!force_rebuild and !dry_run) {
        try writer.print("\nChecking build cache...\n", .{});

        var cache_check = nvfury.build_cache.checkCache(allocator, build_version, actual_source, kernel_version) catch null;
        if (cache_check) |*check| {
            defer check.deinit(allocator);

            if (!check.needs_rebuild) {
                // Verify modules still exist
                if (nvfury.build_cache.hasBuiltModules(allocator, actual_source)) {
                    try writer.print("Cache HIT: Source unchanged, modules already built.\n", .{});
                    try writer.print("  Version: {s}\n", .{build_version});
                    try writer.print("  Kernel:  {s}\n", .{kernel_version});
                    if (check.cached_meta) |meta| {
                        try writer.print("  Hash:    {s}...\n", .{meta.source_hash[0..16]});
                    }
                    try writer.print("\nSkipping rebuild. Use --force to rebuild anyway.\n", .{});
                    try writer.print("Run 'sudo nvfury install' to install the cached modules.\n", .{});
                    return;
                } else {
                    try writer.print("Cache valid but modules missing, rebuilding...\n", .{});
                }
            } else {
                const reason_str = switch (check.reason) {
                    .no_cache => "no cached build exists",
                    .source_changed => "source files changed",
                    .kernel_changed => "kernel version changed",
                    .build_failed => "previous build failed",
                    .cache_valid => "cache valid",
                };
                try writer.print("Rebuild needed: {s}\n", .{reason_str});
            }
        } else {
            try writer.print("No cache entry found, building...\n", .{});
        }
    }

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

        // Get patches directory from settings (configurable)
        const patches_dir = nvfury.settings.findPatchesDir(allocator) catch "/usr/share/nvfury/patches";
        defer if (!std.mem.eql(u8, patches_dir, "/usr/share/nvfury/patches")) allocator.free(patches_dir);

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

    // Get kernel version for cache (if not already fetched)
    const cache_kernel_version = if (std.mem.eql(u8, kernel_version, "unknown"))
        nvfury.builder.getKernelVersion(allocator) catch "unknown"
    else
        kernel_version;

    // Compute source hash for caching
    const source_hash = nvfury.build_cache.computeSourceHash(allocator, actual_source) catch [_]u8{'0'} ** 64;

    // Get current timestamp
    var ts: std.os.linux.timespec = .{ .sec = 0, .nsec = 0 };
    _ = std.os.linux.clock_gettime(.REALTIME, &ts);

    // Determine compiler used
    const kernel_cc = nvfury.builder.detectKernelCompiler();
    const use_ccache = nvfury.builder.isCcacheAvailable();
    const compiler_str = if (use_ccache)
        (if (std.mem.eql(u8, kernel_cc, "clang")) "ccache clang" else "ccache gcc")
    else
        kernel_cc;

    if (build_result.success) {
        const duration_s = @as(f64, @floatFromInt(build_result.duration_ns)) / 1_000_000_000.0;
        try writer.print("Build completed in {d:.1}s\n", .{duration_s});
        try writer.print("Output: {s}\n", .{build_result.output_path});

        // Save build metadata to cache
        const build_meta = nvfury.build_cache.BuildMeta{
            .version = build_version,
            .source_hash = source_hash,
            .kernel_version = cache_kernel_version,
            .build_time = ts.sec,
            .compiler = compiler_str,
            .cflags = "-march=native -O3",
            .success = true,
        };

        nvfury.build_cache.writeBuildMeta(allocator, build_meta) catch |e| {
            try err_writer.print("Warning: Failed to cache build metadata: {}\n", .{e});
        };

        try writer.print("\nBuild cached. Future builds with same source will be skipped.\n", .{});
        try writer.print("Run 'sudo nvfury install' to install the built modules.\n", .{});
    } else {
        // Cache the failed build so we know to retry
        const build_meta = nvfury.build_cache.BuildMeta{
            .version = build_version,
            .source_hash = source_hash,
            .kernel_version = cache_kernel_version,
            .build_time = ts.sec,
            .compiler = compiler_str,
            .cflags = "-march=native -O3",
            .success = false,
        };

        nvfury.build_cache.writeBuildMeta(allocator, build_meta) catch {};

        try err_writer.print("Build failed: {s}\n", .{build_result.error_message orelse "unknown error"});
    }
}

fn cmdInstall(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    var use_dkms = true;
    var create_backup = true;
    var source_dir: ?[]const u8 = null;
    var version: ?[]const u8 = null;

    // Parse options
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--direct")) {
            use_dkms = false;
        } else if (std.mem.eql(u8, arg, "--dkms")) {
            use_dkms = true;
        } else if (std.mem.eql(u8, arg, "--no-backup")) {
            create_backup = false;
        } else if (std.mem.eql(u8, arg, "--source")) {
            i += 1;
            if (i < args.len) source_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--version")) {
            i += 1;
            if (i < args.len) version = args[i];
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

        // Check if source directory is provided
        const src = source_dir orelse {
            try err_writer.print("Error: Source directory required for direct installation.\n", .{});
            try err_writer.print("Use --source <path> to specify the built source directory.\n", .{});
            return;
        };

        try writer.print("Source:  {s}\n", .{src});
        try writer.print("\nInstalling modules directly...\n", .{});

        const install_result = nvfury.install.install(allocator, .{
            .source_path = src,
            .create_backup = create_backup,
            .verify = true,
        }) catch |err| {
            try err_writer.print("Installation failed: {}\n", .{err});
            if (err == error.AccessDenied) {
                try err_writer.print("Note: Module installation requires root privileges.\n", .{});
                try err_writer.print("Try: sudo nvfury install --direct --source {s}\n", .{src});
            }
            return;
        };

        if (!install_result.success) {
            try err_writer.print("Installation failed: {s}\n", .{install_result.error_message orelse "Unknown error"});
            if (install_result.backup_path) |backup| {
                try err_writer.print("Backup available at: {s}\n", .{backup});
                try err_writer.print("Run 'nvfury rollback --backup {s}' to restore.\n", .{backup});
            }
            return;
        }

        try writer.print("Installation: OK\n", .{});
        if (install_result.backup_path) |backup| {
            try writer.print("Backup:  {s}\n", .{backup});
        }
        try writer.print("\nDirect installation complete!\n", .{});
        try writer.print("Note: You'll need to rebuild manually after kernel updates.\n", .{});
        try writer.print("Reboot to load the new modules.\n", .{});
    }
}

fn cmdTune(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    const subcommand = if (args.len > 0) args[0] else "status";

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

fn cmdPatch(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    _ = allocator;
    _ = err_writer;

    const subcommand = if (args.len > 0) args[0] else "list";

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
        if (args.len < 2) {
            try writer.print("Usage: nvfury patch apply <patch-name>\n", .{});
            return;
        }
        const patch_name = args[1];
        try writer.print("Applying patch: {s}\n", .{patch_name});
        try writer.print("Note: Requires source directory from build.\n", .{});
        return;
    }

    try writer.print("Unknown patch subcommand: {s}\n", .{subcommand});
}

fn cmdRollback(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    var backup_path: ?[]const u8 = null;

    // Parse options
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--backup")) {
            i += 1;
            if (i < args.len) backup_path = args[i];
        }
    }

    try writer.print("nvfury rollback\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    const backup = backup_path orelse {
        // List available backups
        try writer.print("Looking for available backups...\n", .{});

        const backup_dir = nvfury.paths.backup;
        const dir_io = std.Options.debug_io;
        var dir = Io.Dir.openDirAbsolute(dir_io, backup_dir, .{ .iterate = true }) catch {
            try writer.print("\nNo backups found at {s}\n", .{backup_dir});
            try writer.print("Backups are created during 'nvfury install'.\n", .{});
            return;
        };
        defer dir.close(dir_io);

        var count: u32 = 0;
        var iter = dir.iterate();
        try writer.print("\nAvailable backups:\n", .{});
        while (try iter.next(dir_io)) |entry| {
            if (entry.kind == .directory) {
                try writer.print("  {s}/{s}\n", .{ backup_dir, entry.name });
                count += 1;
            }
        }

        if (count == 0) {
            try writer.print("  (none)\n", .{});
        } else {
            try writer.print("\nUse 'nvfury rollback --backup <path>' to restore.\n", .{});
        }
        return;
    };

    try writer.print("Backup:  {s}\n", .{backup});

    // Get kernel version
    const kernel_version = nvfury.builder.getKernelVersion(allocator) catch {
        try err_writer.print("Error: Could not determine kernel version.\n", .{});
        return;
    };
    defer allocator.free(kernel_version);

    try writer.print("Kernel:  {s}\n", .{kernel_version});
    try writer.print("\nRestoring modules from backup...\n", .{});

    nvfury.install.restore(allocator, backup, kernel_version) catch |e| {
        try err_writer.print("Rollback failed: {}\n", .{e});
        return;
    };

    try writer.print("Rollback complete!\n", .{});
    try writer.print("Reboot to load the restored modules.\n", .{});
}

fn cmdVersions(allocator: std.mem.Allocator, writer: *Io.Writer, err_writer: *Io.Writer) !void {
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

fn cmdRecommend(writer: *Io.Writer) !void {
    try nvfury.patch.printRecommendations(writer);
}

fn cmdCheckUpdate(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    var notify = false;
    var force = false;

    // Parse options
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--notify")) {
            notify = true;
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            force = true;
        }
    }

    try writer.print("nvfury check-update\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    // Check cached result first (unless forced)
    if (!force) {
        if (nvfury.update.readCache(allocator) catch null) |cached| {
            var c = cached;
            defer c.deinit(allocator);

            // Get current time
            var ts: std.os.linux.timespec = .{ .sec = 0, .nsec = 0 };
            _ = std.os.linux.clock_gettime(.REALTIME, &ts);
            const age = ts.sec - c.last_check;

            // If checked recently (within interval), show cached result
            if (age < nvfury.update.default_check_interval) {
                var dur_buf: [64]u8 = undefined;
                const age_str = nvfury.update.formatDuration(age, &dur_buf);

                try writer.print("Last checked: {s}\n\n", .{age_str});

                if (c.update_available) {
                    try writer.print("Update available!\n", .{});
                    try writer.print("  Installed: {s}\n", .{c.installed_version});
                    try writer.print("  Latest:    {s}\n\n", .{c.latest_version});
                    try writer.print("Run 'nvfury build --latest' to build the new version.\n", .{});
                } else {
                    try writer.print("You're up to date!\n", .{});
                    try writer.print("  Installed: {s}\n", .{c.installed_version});
                    try writer.print("  Latest:    {s}\n", .{c.latest_version});
                }

                try writer.print("\nUse --force to check again.\n", .{});
                return;
            }
        }
    }

    try writer.print("Checking for updates from GitHub...\n\n", .{});

    if (notify) {
        // Use the notification-enabled check
        var cache = nvfury.update.checkWithNotify(allocator, force) catch |e| {
            try err_writer.print("Error checking for updates: {}\n", .{e});
            return;
        };
        defer cache.deinit(allocator);

        if (cache.update_available) {
            try writer.print("Update available!\n", .{});
            try writer.print("  Installed: {s}\n", .{cache.installed_version});
            try writer.print("  Latest:    {s}\n\n", .{cache.latest_version});
            try writer.print("Run 'nvfury build --latest' to build the new version.\n", .{});
            try writer.print("\nDesktop notification sent.\n", .{});
        } else {
            try writer.print("You're up to date!\n", .{});
            try writer.print("  Installed: {s}\n", .{cache.installed_version});
            try writer.print("  Latest:    {s}\n", .{cache.latest_version});
        }
    } else {
        const info = nvfury.fetch.getUpdateInfo(allocator) catch |e| {
            try err_writer.print("Error checking for updates: {}\n", .{e});
            return;
        };
        defer allocator.free(info);

        // Cache the result
        _ = nvfury.update.checkAndCache(allocator) catch {};

        try writer.print("{s}\n", .{info});
    }
}

fn cmdUpdateDaemon(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    const subcommand = if (args.len > 0) args[0] else "status";

    try writer.print("nvfury update-daemon\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    if (std.mem.eql(u8, subcommand, "enable") or std.mem.eql(u8, subcommand, "start")) {
        try writer.print("Installing systemd timer for automatic update checks...\n\n", .{});

        const success = try nvfury.update.installTimer(allocator, writer);

        if (success) {
            try writer.print("\nTimer installed and started!\n", .{});
            try writer.print("nvfury will check for updates every 12 hours.\n", .{});
            try writer.print("You'll receive desktop notifications when updates are available.\n", .{});
        } else {
            try err_writer.print("\nFailed to install timer.\n", .{});
            try err_writer.print("Make sure systemd --user is available.\n", .{});
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "disable") or std.mem.eql(u8, subcommand, "stop")) {
        try writer.print("Removing systemd timer...\n\n", .{});

        const success = try nvfury.update.removeTimer(allocator, writer);

        if (success) {
            try writer.print("\nTimer removed.\n", .{});
            try writer.print("Automatic update checking is now disabled.\n", .{});
        } else {
            try err_writer.print("\nFailed to remove timer.\n", .{});
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "status")) {
        var status = try nvfury.update.getTimerStatus(allocator);
        defer status.deinit(allocator);

        try writer.print("Timer Status\n\n", .{});
        try writer.print("  Enabled: {}\n", .{status.enabled});
        try writer.print("  Active:  {}\n", .{status.active});

        if (status.next_run) |next| {
            try writer.print("  Next:    {s}\n", .{next});
        }

        // Show last check info
        if (nvfury.update.readCache(allocator) catch null) |cached| {
            var c = cached;
            defer c.deinit(allocator);

            var ts: std.os.linux.timespec = .{ .sec = 0, .nsec = 0 };
            _ = std.os.linux.clock_gettime(.REALTIME, &ts);
            const age = ts.sec - c.last_check;

            var dur_buf: [64]u8 = undefined;
            const age_str = nvfury.update.formatDuration(age, &dur_buf);

            try writer.print("\nLast Check\n\n", .{});
            try writer.print("  Checked:   {s}\n", .{age_str});
            try writer.print("  Installed: {s}\n", .{c.installed_version});
            try writer.print("  Latest:    {s}\n", .{c.latest_version});
            try writer.print("  Update:    {}\n", .{c.update_available});
        } else {
            try writer.print("\nNo update check has been performed yet.\n", .{});
            try writer.print("Run 'nvfury check-update' to check now.\n", .{});
        }

        if (!status.enabled) {
            try writer.print("\nTo enable automatic checking:\n", .{});
            try writer.print("  nvfury update-daemon enable\n", .{});
        }
        return;
    }

    try err_writer.print("Unknown subcommand: {s}\n", .{subcommand});
    try err_writer.print("Available: enable, disable, status\n", .{});
}

fn cmdBuildCache(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    const subcommand = if (args.len > 0) args[0] else "status";

    try writer.print("nvfury build-cache\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    if (std.mem.eql(u8, subcommand, "status")) {
        try writer.print("Build Cache Status (source hash tracking)\n\n", .{});

        var status = nvfury.build_cache.getCacheStatus(allocator) catch {
            try writer.print("No cached builds found.\n", .{});
            try writer.print("\nBuild cache tracks source hashes to skip redundant rebuilds.\n", .{});
            try writer.print("Run 'nvfury build' to create a cached build.\n", .{});
            return;
        };
        defer status.deinit(allocator);

        if (status.entries == 0) {
            try writer.print("No cached builds found.\n", .{});
            try writer.print("\nBuild cache tracks source hashes to skip redundant rebuilds.\n", .{});
            try writer.print("Run 'nvfury build' to create a cached build.\n", .{});
            return;
        }

        try writer.print("Cached builds: {d}\n\n", .{status.entries});

        for (status.versions.items) |version| {
            if (nvfury.build_cache.readBuildMeta(allocator, version) catch null) |meta_opt| {
                var meta = meta_opt;
                defer meta.deinit(allocator);

                try writer.print("  {s}\n", .{version});
                try writer.print("    Kernel:   {s}\n", .{meta.kernel_version});
                try writer.print("    Compiler: {s}\n", .{meta.compiler});
                try writer.print("    Hash:     {s}...\n", .{meta.source_hash[0..16]});
                try writer.print("    Success:  {}\n\n", .{meta.success});
            } else {
                try writer.print("  {s} (metadata unavailable)\n", .{version});
            }
        }

        try writer.print("Build cache will skip rebuilds when source is unchanged.\n", .{});
        try writer.print("Use 'nvfury build --force' to rebuild anyway.\n", .{});
        return;
    }

    if (std.mem.eql(u8, subcommand, "clear")) {
        try writer.print("Clearing build cache...\n", .{});

        nvfury.build_cache.clearCache(allocator) catch |e| {
            try err_writer.print("Error clearing cache: {}\n", .{e});
            return;
        };

        try writer.print("Build cache cleared.\n", .{});
        try writer.print("Next build will perform a full rebuild.\n", .{});
        return;
    }

    try err_writer.print("Unknown subcommand: {s}\n", .{subcommand});
    try err_writer.print("Available: status, clear\n", .{});
}

fn cmdCache(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    const subcommand = if (args.len > 0) args[0] else "status";

    try writer.print("nvfury cache\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    // Check if ccache is available
    if (!nvfury.builder.isCcacheAvailable()) {
        try err_writer.print("ccache is not installed.\n", .{});
        try err_writer.print("Install with: pacman -S ccache (or apt install ccache)\n", .{});
        try err_writer.print("\nBuild cache speeds up incremental builds significantly.\n", .{});
        return;
    }

    if (std.mem.eql(u8, subcommand, "status")) {
        try writer.print("Build Cache Status (ccache)\n\n", .{});

        const stats = nvfury.builder.getCcacheStats(allocator) catch |e| {
            try err_writer.print("Error getting cache stats: {}\n", .{e});
            return;
        };
        defer allocator.free(stats.cache_size);
        defer allocator.free(stats.max_size);

        try writer.print("  Cache Hits:    {d}\n", .{stats.cache_hits});
        try writer.print("  Cache Misses:  {d}\n", .{stats.cache_misses});
        try writer.print("  Hit Rate:      {d:.1}%\n", .{stats.hit_rate});
        try writer.print("  Cache Size:    {s}\n", .{stats.cache_size});
        try writer.print("  Max Size:      {s}\n", .{stats.max_size});
        try writer.print("\nccache will automatically cache compilation results.\n", .{});
        try writer.print("Subsequent builds of the same version will be faster.\n", .{});
        return;
    }

    if (std.mem.eql(u8, subcommand, "clear")) {
        try writer.print("Clearing build cache...\n", .{});

        nvfury.builder.clearCcache(allocator) catch |e| {
            try err_writer.print("Error clearing cache: {}\n", .{e});
            return;
        };

        try writer.print("Build cache cleared.\n", .{});
        return;
    }

    try err_writer.print("Unknown cache subcommand: {s}\n", .{subcommand});
    try err_writer.print("Available: status, clear\n", .{});
}

fn cmdProfile(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    const subcommand = if (args.len > 0) args[0] else "list";

    try writer.print("nvfury profile\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    if (std.mem.eql(u8, subcommand, "list")) {
        try writer.print("Available presets for export:\n\n", .{});
        inline for (@typeInfo(nvfury.config.TunePreset).@"enum".fields) |field| {
            const preset: nvfury.config.TunePreset = @enumFromInt(field.value);
            try writer.print("  {s: <12} - {s}\n", .{ field.name, preset.description() });
        }
        try writer.print("\nExport a preset:  nvfury profile export <preset> <file.json>\n", .{});
        try writer.print("Import a profile: nvfury profile import <file.json>\n", .{});
        return;
    }

    if (std.mem.eql(u8, subcommand, "export")) {
        if (args.len < 2) {
            try err_writer.print("Usage: nvfury profile export <preset> <output.json>\n", .{});
            try err_writer.print("Presets: gaming, balanced, quiet, benchmark\n", .{});
            return;
        }
        const preset_name = args[1];

        if (args.len < 3) {
            try err_writer.print("Usage: nvfury profile export <preset> <output.json>\n", .{});
            try err_writer.print("Please specify output file path.\n", .{});
            return;
        }
        const output_path = args[2];

        // Parse preset name
        const preset: nvfury.config.TunePreset = if (std.mem.eql(u8, preset_name, "gaming"))
            .gaming
        else if (std.mem.eql(u8, preset_name, "balanced"))
            .balanced
        else if (std.mem.eql(u8, preset_name, "quiet"))
            .quiet
        else if (std.mem.eql(u8, preset_name, "benchmark"))
            .benchmark
        else {
            try err_writer.print("Unknown preset: {s}\n", .{preset_name});
            try err_writer.print("Available: gaming, balanced, quiet, benchmark\n", .{});
            return;
        };

        try writer.print("Exporting preset: {s}\n", .{@tagName(preset)});
        try writer.print("Output file:      {s}\n\n", .{output_path});

        // Create profile from preset and export
        var profile = nvfury.config.Profile.fromPreset(preset, allocator) catch |e| {
            try err_writer.print("Error creating profile: {}\n", .{e});
            return;
        };
        defer profile.deinit();

        nvfury.config.exportProfile(allocator, profile, output_path) catch |e| {
            try err_writer.print("Error exporting profile: {}\n", .{e});
            return;
        };

        try writer.print("Profile exported successfully!\n", .{});
        try writer.print("Share this file with others or use 'nvfury profile import' to apply.\n", .{});
        return;
    }

    if (std.mem.eql(u8, subcommand, "import")) {
        if (args.len < 2) {
            try err_writer.print("Usage: nvfury profile import <input.json>\n", .{});
            return;
        }
        const input_path = args[1];

        try writer.print("Importing profile: {s}\n\n", .{input_path});

        var profile = nvfury.config.importProfile(allocator, input_path) catch |e| {
            try err_writer.print("Error importing profile: {}\n", .{e});
            if (e == error.FileNotFound) {
                try err_writer.print("File not found: {s}\n", .{input_path});
            }
            return;
        };
        defer profile.deinit();

        try writer.print("Profile Name:    {s}\n", .{profile.name});
        try writer.print("Description:     {s}\n", .{profile.description});
        try writer.print("Version:         {d}\n\n", .{profile.version});

        try writer.print("Module Parameters:\n", .{});
        try writer.print("  UsePageAttributeTable:   {}\n", .{profile.params.use_page_attribute_table});
        try writer.print("  EnablePCIeGen3:          {}\n", .{profile.params.enable_pcie_gen3});
        try writer.print("  EnableMSI:               {}\n", .{profile.params.enable_msi});
        try writer.print("  PreserveVideoMemory:     {}\n", .{profile.params.preserve_video_memory});
        try writer.print("  DynamicPowerMgmt:        0x{x:0>2}\n", .{profile.params.dynamic_power_management});
        try writer.print("  TempFilePath:            {s}\n", .{profile.params.temporary_file_path});
        try writer.print("  EnableGpuFirmware:       {} (GSP)\n", .{profile.params.enable_gpu_firmware});
        try writer.print("  EnableResizableBar:      {} (ReBAR)\n", .{profile.params.enable_resizable_bar});

        // Check if --apply flag is provided
        var apply = false;
        for (args) |arg| {
            if (std.mem.eql(u8, arg, "--apply")) {
                apply = true;
            }
        }

        if (apply) {
            try writer.print("\nApplying imported profile...\n", .{});

            // Generate modprobe config and write it
            const conf = profile.params.toModprobeConf(allocator) catch |e| {
                try err_writer.print("Error generating config: {}\n", .{e});
                return;
            };
            defer allocator.free(conf);

            // Write to modprobe.d
            const config_path = "/etc/modprobe.d/nvidia-nvfury.conf";
            const fd = std.posix.openat(std.posix.AT.FDCWD, config_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch |e| {
                try err_writer.print("Error writing config: {}\n", .{e});
                if (e == error.AccessDenied) {
                    try err_writer.print("Note: Run with sudo to apply profile.\n", .{});
                }
                return;
            };
            defer _ = std.c.close(fd);

            const write_result = std.c.write(fd, conf.ptr, conf.len);
            if (write_result < 0) {
                try err_writer.print("Error writing config content\n", .{});
                return;
            }

            try writer.print("Configuration written to: {s}\n", .{config_path});
            try writer.print("Reload modules or reboot to apply changes.\n", .{});
        } else {
            try writer.print("\nTo apply this profile, run:\n", .{});
            try writer.print("  sudo nvfury profile import {s} --apply\n", .{input_path});
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "show")) {
        if (args.len < 2) {
            try err_writer.print("Usage: nvfury profile show <preset>\n", .{});
            try err_writer.print("Presets: gaming, balanced, quiet, benchmark\n", .{});
            return;
        }
        const preset_name = args[1];

        // Parse preset name
        const preset: nvfury.config.TunePreset = if (std.mem.eql(u8, preset_name, "gaming"))
            .gaming
        else if (std.mem.eql(u8, preset_name, "balanced"))
            .balanced
        else if (std.mem.eql(u8, preset_name, "quiet"))
            .quiet
        else if (std.mem.eql(u8, preset_name, "benchmark"))
            .benchmark
        else {
            try err_writer.print("Unknown preset: {s}\n", .{preset_name});
            try err_writer.print("Available: gaming, balanced, quiet, benchmark\n", .{});
            return;
        };

        try writer.print("Preset: {s}\n", .{@tagName(preset)});
        try writer.print("Description: {s}\n\n", .{preset.description()});

        const params = nvfury.config.ModuleParams.fromPreset(preset);
        try writer.print("Module Parameters:\n", .{});
        try writer.print("  UsePageAttributeTable:   {}\n", .{params.use_page_attribute_table});
        try writer.print("  EnablePCIeGen3:          {}\n", .{params.enable_pcie_gen3});
        try writer.print("  EnableMSI:               {}\n", .{params.enable_msi});
        try writer.print("  PreserveVideoMemory:     {}\n", .{params.preserve_video_memory});
        try writer.print("  DynamicPowerMgmt:        0x{x:0>2}\n", .{params.dynamic_power_management});
        try writer.print("  TempFilePath:            {s}\n", .{params.temporary_file_path});
        try writer.print("  EnableGpuFirmware:       {} (GSP)\n", .{params.enable_gpu_firmware});
        try writer.print("  EnableResizableBar:      {} (ReBAR)\n", .{params.enable_resizable_bar});
        return;
    }

    try err_writer.print("Unknown profile subcommand: {s}\n", .{subcommand});
    try err_writer.print("Available: list, export, import, show\n", .{});
}

fn cmdGpus(writer: *Io.Writer, err_writer: *Io.Writer) !void {
    _ = err_writer;

    try writer.print("nvfury gpus\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    const info = nvfury.gpu.detectAllGpus();
    try nvfury.gpu.printMultiGpuStatus(&info, writer);

    // Recommendations for multi-GPU setups
    if (info.nvidia_count > 1) {
        try writer.print("Multi-NVIDIA Setup Notes:\n", .{});
        try writer.print("  - Use CUDA_VISIBLE_DEVICES to select specific GPU\n", .{});
        try writer.print("  - Consider SLI/NVLink if supported by your GPUs\n", .{});
        try writer.print("  - nvfury builds will apply to all NVIDIA GPUs\n", .{});
    }

    if (info.nvidia_count == 0) {
        try writer.print("No NVIDIA GPUs detected.\n", .{});
        try writer.print("Ensure NVIDIA drivers are installed and GPU is recognized.\n", .{});
    }
}

fn cmdPrime(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    const subcommand = if (args.len > 0) args[0] else "status";

    if (std.mem.eql(u8, subcommand, "status")) {
        try nvfury.prime.printStatus(allocator, writer);
        return;
    }

    if (std.mem.eql(u8, subcommand, "offload")) {
        if (args.len < 2) {
            try err_writer.print("Usage: nvfury prime offload <command> [args...]\n", .{});
            try err_writer.print("Example: nvfury prime offload ./my_game\n", .{});
            return;
        }

        // Print environment and hint
        try writer.print("Running on NVIDIA GPU with PRIME offload...\n\n", .{});
        try writer.print("Environment:\n", .{});
        try writer.print("  __NV_PRIME_RENDER_OFFLOAD=1\n", .{});
        try writer.print("  __GLX_VENDOR_LIBRARY_NAME=nvidia\n\n", .{});

        // Execute the command with PRIME environment using shell wrapper
        // Build the command string with environment variables
        var cmd_buf: [4096]u8 = undefined;
        var cmd_len: usize = 0;

        // Start with environment exports
        const env_prefix = "export __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only && exec ";
        @memcpy(cmd_buf[0..env_prefix.len], env_prefix);
        cmd_len = env_prefix.len;

        // Append the user's command arguments
        for (args[1..]) |arg| {
            if (cmd_len + arg.len + 3 >= cmd_buf.len) {
                try err_writer.print("Command too long\n", .{});
                return;
            }
            // Quote each argument for safety
            cmd_buf[cmd_len] = '\'';
            cmd_len += 1;
            @memcpy(cmd_buf[cmd_len .. cmd_len + arg.len], arg);
            cmd_len += arg.len;
            cmd_buf[cmd_len] = '\'';
            cmd_len += 1;
            cmd_buf[cmd_len] = ' ';
            cmd_len += 1;
        }

        const shell_cmd = cmd_buf[0..cmd_len];
        const shell_cmd_z = allocator.dupeZ(u8, shell_cmd) catch {
            try err_writer.print("Memory allocation failed\n", .{});
            return;
        };
        defer allocator.free(shell_cmd_z);

        const shell_argv = [_][]const u8{ "/bin/sh", "-c", shell_cmd_z };

        const debug_io = std.Options.debug_io;
        var child = std.process.spawn(debug_io, .{
            .argv = &shell_argv,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        }) catch {
            try err_writer.print("Failed to execute command\n", .{});
            return;
        };

        _ = child.wait(debug_io) catch {};
        return;
    }

    if (std.mem.eql(u8, subcommand, "setup")) {
        try writer.print("nvfury prime setup\n", .{});
        try writer.print("---------------------------------------------------\n", .{});
        try writer.print("Configuring PRIME hybrid graphics...\n\n", .{});

        const success = try nvfury.prime.writeConfigs(allocator, writer);
        if (success) {
            try writer.print("\nPRIME configuration complete!\n", .{});
            try writer.print("Log out and back in (or reboot) to apply changes.\n", .{});
        }
        return;
    }

    try err_writer.print("Unknown prime subcommand: {s}\n", .{subcommand});
    try err_writer.print("Available: status, offload, setup\n", .{});
}

fn cmdSign(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    const subcommand = if (args.len > 0) args[0] else "status";

    if (std.mem.eql(u8, subcommand, "status")) {
        try nvfury.sign.printStatus(allocator, writer);
        return;
    }

    if (std.mem.eql(u8, subcommand, "setup")) {
        try writer.print("nvfury sign setup\n", .{});
        try writer.print("---------------------------------------------------\n", .{});

        const success = try nvfury.sign.generateKeys(allocator, writer);
        if (success) {
            try writer.print("\nNext step: Run 'sudo nvfury sign enroll' to enroll the MOK.\n", .{});
        }
        return;
    }

    if (std.mem.eql(u8, subcommand, "enroll")) {
        try writer.print("nvfury sign enroll\n", .{});
        try writer.print("---------------------------------------------------\n", .{});

        _ = try nvfury.sign.enrollMok(allocator, writer);
        return;
    }

    if (std.mem.eql(u8, subcommand, "sign")) {
        if (args.len < 2) {
            try err_writer.print("Usage: nvfury sign sign <module_path>\n", .{});
            try err_writer.print("Example: nvfury sign sign ./nvidia.ko\n", .{});
            return;
        }
        const module_path = args[1];

        try writer.print("Signing module: {s}\n", .{module_path});

        if (nvfury.sign.signModule(allocator, module_path)) |_| {
            try writer.print("Module signed successfully.\n", .{});
        } else |err| {
            try err_writer.print("Signing failed: {s}\n", .{@errorName(err)});
        }
        return;
    }

    try err_writer.print("Unknown sign subcommand: {s}\n", .{subcommand});
    try err_writer.print("Available: status, setup, enroll, sign\n", .{});
}

fn cmdBenchmark(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    const subcommand = if (args.len > 0) args[0] else "run";

    if (std.mem.eql(u8, subcommand, "run")) {
        try writer.print("nvfury benchmark\n", .{});
        try writer.print("---------------------------------------------------\n", .{});

        var report = try nvfury.benchmark.runBenchmarks(allocator, writer);
        defer report.deinit(allocator);

        // Offer to export
        try writer.print("\nTo export results: nvfury benchmark export <file.json>\n", .{});
        return;
    }

    if (std.mem.eql(u8, subcommand, "export")) {
        if (args.len < 2) {
            try err_writer.print("Usage: nvfury benchmark export <output.json>\n", .{});
            return;
        }
        const output_path = args[1];

        try writer.print("Running benchmark and exporting to {s}...\n\n", .{output_path});

        var report = try nvfury.benchmark.runBenchmarks(allocator, writer);
        defer report.deinit(allocator);

        try nvfury.benchmark.exportReport(allocator, report, output_path);
        try writer.print("\nResults exported to: {s}\n", .{output_path});
        return;
    }

    try err_writer.print("Unknown benchmark subcommand: {s}\n", .{subcommand});
    try err_writer.print("Available: run, export\n", .{});
}

fn cmdConfig(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    const subcommand = if (args.len > 0) args[0] else "show";

    if (std.mem.eql(u8, subcommand, "show")) {
        try nvfury.settings.printSettings(allocator, writer);
        return;
    }

    if (std.mem.eql(u8, subcommand, "set")) {
        if (args.len < 3) {
            try err_writer.print("Usage: nvfury config set <key> <value>\n", .{});
            try err_writer.print("Example: nvfury config set patches_dir /path/to/patches\n", .{});
            try err_writer.print("Example: nvfury config set pinned_version 590.48.01\n", .{});
            return;
        }
        const key = args[1];
        const value = args[2];

        _ = try nvfury.settings.setValue(allocator, key, value, writer);
        return;
    }

    if (std.mem.eql(u8, subcommand, "reset")) {
        try nvfury.settings.resetSettings(allocator, writer);
        return;
    }

    if (std.mem.eql(u8, subcommand, "path")) {
        const expanded = try nvfury.config.expandPath(allocator, nvfury.settings.config_path);
        defer allocator.free(expanded);
        try writer.print("Config file: {s}\n", .{expanded});
        return;
    }

    try err_writer.print("Unknown config subcommand: {s}\n", .{subcommand});
    try err_writer.print("Available: show, set, reset, path\n", .{});
}

fn cmdPreflight(allocator: std.mem.Allocator, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    _ = err_writer;

    try writer.print("nvfury preflight\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    var report = try nvfury.preflight.runChecks(allocator);
    defer report.deinit(allocator);

    try nvfury.preflight.printReport(report, writer);
}

fn cmdUninstall(allocator: std.mem.Allocator, args: []const [:0]const u8, writer: *Io.Writer, err_writer: *Io.Writer) !void {
    // Parse arguments
    var options = nvfury.uninstall.UninstallOptions{};

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "status")) {
            try nvfury.uninstall.printStatus(allocator, writer);
            return;
        } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            options.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--all")) {
            options.remove_cache = true;
            options.remove_config = true;
        } else if (std.mem.eql(u8, arg, "--keep-dkms")) {
            options.remove_dkms = false;
        } else if (std.mem.eql(u8, arg, "--keep-config")) {
            options.remove_modprobe = false;
        } else if (std.mem.eql(u8, arg, "--remove-cache")) {
            options.remove_cache = true;
        } else if (std.mem.eql(u8, arg, "--remove-config")) {
            options.remove_config = true;
        } else if (std.mem.eql(u8, arg, "--restore")) {
            options.restore_backup = true;
        } else if (std.mem.eql(u8, arg, "--backup")) {
            i += 1;
            if (i < args.len) {
                options.backup_path = args[i];
                options.restore_backup = true;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try writer.print(
                \\nvfury uninstall - Remove nvfury-installed NVIDIA drivers
                \\
                \\Usage: nvfury uninstall [options]
                \\       nvfury uninstall status
                \\
                \\Options:
                \\  status            Show what would be removed
                \\  --dry-run, -n     Show what would be done without doing it
                \\  --all             Also remove cache and config directories
                \\  --keep-dkms       Don't remove DKMS entries
                \\  --keep-config     Don't remove modprobe configuration
                \\  --remove-cache    Remove ~/.cache/nvfury
                \\  --remove-config   Remove ~/.config/nvfury
                \\  --restore         Restore modules from backup after removal
                \\  --backup <path>   Specify backup path to restore from
                \\
                \\Examples:
                \\  nvfury uninstall status       # See what's installed
                \\  nvfury uninstall --dry-run    # Preview uninstall
                \\  sudo nvfury uninstall         # Remove drivers
                \\  sudo nvfury uninstall --all   # Remove everything
                \\  sudo nvfury uninstall --restore  # Remove and restore backup
                \\
            , .{});
            return;
        }
    }

    if (options.dry_run) {
        try writer.print("nvfury uninstall (dry run)\n", .{});
    } else {
        try writer.print("nvfury uninstall\n", .{});
    }
    try writer.print("---------------------------------------------------\n\n", .{});

    const result = try nvfury.uninstall.uninstall(allocator, options);

    // Report results
    if (options.dry_run) {
        try writer.print("Would perform the following actions:\n\n", .{});
    }

    if (result.modules_removed > 0) {
        try writer.print("  Modules unloaded: {d}\n", .{result.modules_removed});
    }
    if (result.dkms_removed) {
        try writer.print("  DKMS entries: removed\n", .{});
    }
    if (result.modprobe_removed) {
        try writer.print("  Modprobe config: removed\n", .{});
    }
    if (result.cache_removed) {
        try writer.print("  Cache directory: removed\n", .{});
    }
    if (result.config_removed) {
        try writer.print("  Config directory: removed\n", .{});
    }
    if (result.backup_restored) {
        try writer.print("  Backup: restored\n", .{});
    }

    // Print error message if any
    if (result.error_msg) |err| {
        try err_writer.print("\nError: {s}\n", .{err});
    }

    if (result.success and !options.dry_run) {
        try writer.print("\nUninstall complete.\n", .{});
        if (!result.backup_restored) {
            try writer.print("Reboot to complete driver removal.\n", .{});
        }
    } else if (result.success and options.dry_run) {
        try writer.print("\nRun without --dry-run to perform these actions.\n", .{});
    }
}

test "main module compiles" {
    _ = nvfury;
}
