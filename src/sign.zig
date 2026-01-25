//! nvfury/sign - SecureBoot Module Signing
//!
//! Manages MOK (Machine Owner Key) generation and kernel module signing
//! for SecureBoot-enabled systems.

const std = @import("std");
const config = @import("config.zig");
const builder = @import("builder.zig");

/// Default paths for signing keys
pub const paths = struct {
    /// MOK private key
    pub const mok_key = "/var/lib/nvfury/mok/MOK.priv";
    /// MOK certificate
    pub const mok_cert = "/var/lib/nvfury/mok/MOK.der";
    /// MOK PEM certificate (for display)
    pub const mok_pem = "/var/lib/nvfury/mok/MOK.pem";
    /// Key directory
    pub const mok_dir = "/var/lib/nvfury/mok";
};

/// NVIDIA module names to sign
pub const nvidia_modules = [_][]const u8{
    "nvidia.ko",
    "nvidia-modeset.ko",
    "nvidia-uvm.ko",
    "nvidia-drm.ko",
};

/// SecureBoot status
pub const SecureBootStatus = struct {
    enabled: bool,
    mok_key_exists: bool,
    mok_cert_exists: bool,
    mok_enrolled: bool,
    modules_signed: bool,
};

/// Check if SecureBoot is enabled
pub fn isSecureBootEnabled() bool {
    // Check /sys/firmware/efi/efivars/SecureBoot-*
    const fd = std.posix.openat(std.posix.AT.FDCWD, "/sys/firmware/efi/efivars", .{ .DIRECTORY = true }, 0) catch return false;
    std.posix.close(fd);

    // Try to read SecureBoot variable
    const sb_fd = std.posix.openat(std.posix.AT.FDCWD, "/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c", .{}, 0) catch return false;
    defer std.posix.close(sb_fd);

    var buf: [8]u8 = undefined;
    const n = std.posix.read(sb_fd, &buf) catch return false;

    // SecureBoot variable format: 4 bytes attributes + 1 byte value
    // Value of 1 means enabled
    if (n >= 5) {
        return buf[4] == 1;
    }

    return false;
}

/// Check if file exists
fn fileExists(path: []const u8) bool {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0) catch return false;
    std.posix.close(fd);
    return true;
}

/// Get SecureBoot status
pub fn getStatus(allocator: std.mem.Allocator) !SecureBootStatus {
    const sb_enabled = isSecureBootEnabled();
    const key_exists = fileExists(paths.mok_key);
    const cert_exists = fileExists(paths.mok_cert);

    // Check if MOK is enrolled by looking at mokutil output
    var mok_enrolled = false;
    if (cert_exists) {
        const io = std.Options.debug_io;
        const result = std.process.run(allocator, io, .{
            .argv = &.{ "mokutil", "--test-key", paths.mok_cert },
        }) catch null;

        if (result) |r| {
            defer allocator.free(r.stdout);
            defer allocator.free(r.stderr);
            // Exit code 0 means key is enrolled
            mok_enrolled = r.term == .exited and r.term.exited == 0;
        }
    }

    // Check if modules are signed
    var modules_signed = false;
    if (sb_enabled) {
        // Check if any nvidia module has a signature
        const kernel_version = builder.getKernelVersion(allocator) catch null;
        if (kernel_version) |kv| {
            defer allocator.free(kv);

            var path_buf: [256]u8 = undefined;
            const module_path = std.fmt.bufPrint(&path_buf, "/lib/modules/{s}/updates/nvidia.ko", .{kv}) catch null;
            if (module_path) |mp| {
                if (fileExists(mp)) {
                    // Try to verify signature
                    const debug_io = std.Options.debug_io;
                    const verify_result = std.process.run(allocator, debug_io, .{
                        .argv = &.{ "modinfo", "-F", "sig_id", mp },
                    }) catch null;

                    if (verify_result) |vr| {
                        defer allocator.free(vr.stdout);
                        defer allocator.free(vr.stderr);
                        modules_signed = vr.stdout.len > 0;
                    }
                }
            }
        }
    }

    return SecureBootStatus{
        .enabled = sb_enabled,
        .mok_key_exists = key_exists,
        .mok_cert_exists = cert_exists,
        .mok_enrolled = mok_enrolled,
        .modules_signed = modules_signed,
    };
}

/// OpenSSL configuration for MOK generation
const openssl_conf =
    \\[ req ]
    \\default_bits = 4096
    \\distinguished_name = req_distinguished_name
    \\prompt = no
    \\x509_extensions = v3_ca
    \\
    \\[ req_distinguished_name ]
    \\CN = nvfury MOK Signing Key
    \\O = nvfury
    \\
    \\[ v3_ca ]
    \\subjectKeyIdentifier = hash
    \\authorityKeyIdentifier = keyid:always,issuer
    \\basicConstraints = critical,CA:FALSE
    \\keyUsage = critical,digitalSignature,cRLSign
    \\extendedKeyUsage = codeSigning
    \\
;

/// Generate MOK signing key pair
pub fn generateKeys(allocator: std.mem.Allocator, writer: *std.Io.Writer) !bool {
    const io = std.Options.debug_io;

    // Check root
    if (std.c.geteuid() != 0) {
        try writer.print("Error: Key generation requires root privileges.\n", .{});
        try writer.print("Run: sudo nvfury sign setup\n", .{});
        return false;
    }

    // Check if keys already exist
    if (fileExists(paths.mok_key)) {
        try writer.print("Warning: MOK keys already exist at {s}\n", .{paths.mok_dir});
        try writer.print("To regenerate, first remove the existing keys.\n", .{});
        return false;
    }

    // Create directory
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "mkdir", "-p", paths.mok_dir },
    }) catch {};

    // Set secure permissions
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "chmod", "700", paths.mok_dir },
    }) catch {};

    // Write OpenSSL config
    const conf_path = "/var/lib/nvfury/mok/openssl.cnf";
    const conf_fd = std.posix.openat(std.posix.AT.FDCWD, conf_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o600) catch {
        try writer.print("Error: Could not write OpenSSL config\n", .{});
        return false;
    };
    _ = std.c.write(conf_fd, openssl_conf.ptr, openssl_conf.len);
    std.posix.close(conf_fd);

    try writer.print("Generating 4096-bit RSA key pair...\n", .{});

    // Generate key pair using OpenSSL
    const gen_result = std.process.run(allocator, io, .{
        .argv = &.{
            "openssl", "req", "-new", "-x509",
            "-newkey",    "rsa:4096",
            "-keyout",    paths.mok_key,
            "-out",       paths.mok_pem,
            "-nodes",
            "-days",      "36500", // 100 years
            "-config",    conf_path,
        },
    }) catch {
        try writer.print("Error: OpenSSL not found. Install openssl package.\n", .{});
        return false;
    };
    defer allocator.free(gen_result.stdout);
    defer allocator.free(gen_result.stderr);

    if (gen_result.term != .exited or gen_result.term.exited != 0) {
        try writer.print("Error: Key generation failed\n", .{});
        try writer.print("{s}\n", .{gen_result.stderr});
        return false;
    }

    // Convert PEM to DER for MOK enrollment
    const der_result = std.process.run(allocator, io, .{
        .argv = &.{
            "openssl", "x509",
            "-in",      paths.mok_pem,
            "-out",     paths.mok_cert,
            "-outform", "DER",
        },
    }) catch {
        try writer.print("Error: Failed to convert certificate to DER format\n", .{});
        return false;
    };
    defer allocator.free(der_result.stdout);
    defer allocator.free(der_result.stderr);

    if (der_result.term != .exited or der_result.term.exited != 0) {
        try writer.print("Error: DER conversion failed\n", .{});
        return false;
    }

    // Set secure permissions on key
    _ = std.process.run(allocator, io, .{
        .argv = &.{ "chmod", "600", paths.mok_key },
    }) catch {};

    try writer.print("\nMOK key pair generated:\n", .{});
    try writer.print("  Private key:  {s}\n", .{paths.mok_key});
    try writer.print("  Certificate:  {s}\n", .{paths.mok_cert});
    try writer.print("  PEM cert:     {s}\n", .{paths.mok_pem});

    return true;
}

/// Enroll MOK certificate
pub fn enrollMok(allocator: std.mem.Allocator, writer: *std.Io.Writer) !bool {
    _ = allocator;
    const io = std.Options.debug_io;

    if (!fileExists(paths.mok_cert)) {
        try writer.print("Error: MOK certificate not found. Run 'nvfury sign setup' first.\n", .{});
        return false;
    }

    try writer.print("Enrolling MOK certificate...\n", .{});
    try writer.print("\nYou will be prompted to create a one-time password.\n", .{});
    try writer.print("Remember this password - you'll need it after reboot.\n\n", .{});

    // Use mokutil to import the key
    var child = std.process.spawn(io, .{
        .argv = &.{ "mokutil", "--import", paths.mok_cert },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch {
        try writer.print("Error: mokutil not found. Install mokutil package.\n", .{});
        return false;
    };

    const term = child.wait(io) catch return false;
    if (term != .exited or term.exited != 0) {
        try writer.print("\nMOK enrollment failed.\n", .{});
        return false;
    }

    try writer.print("\nMOK certificate queued for enrollment.\n", .{});
    try writer.print("\nIMPORTANT: Reboot your system and complete MOK enrollment:\n", .{});
    try writer.print("  1. At the MOK Manager blue screen, select 'Enroll MOK'\n", .{});
    try writer.print("  2. Select 'Continue'\n", .{});
    try writer.print("  3. Enter the password you just created\n", .{});
    try writer.print("  4. Select 'Reboot'\n", .{});

    return true;
}

/// Sign a kernel module
pub fn signModule(allocator: std.mem.Allocator, module_path: []const u8) !bool {
    if (!fileExists(paths.mok_key) or !fileExists(paths.mok_cert)) {
        return error.NoSigningKey;
    }

    const io = std.Options.debug_io;

    // Use kmodsign or sign-file (kernel's script)
    // Try sign-file first (more common)
    const kernel_version = try builder.getKernelVersion(allocator);
    defer allocator.free(kernel_version);

    var sign_file_path: [256]u8 = undefined;
    const sign_file = std.fmt.bufPrint(&sign_file_path, "/usr/src/linux-headers-{s}/scripts/sign-file", .{kernel_version}) catch null;

    // Also try common locations
    const sign_tools = [_][]const u8{
        if (sign_file) |sf| sf else "/usr/lib/modules/*/build/scripts/sign-file",
        "/usr/src/kernels/*/scripts/sign-file",
        "/usr/bin/kmodsign",
        "/usr/lib/linux-tools/*/sign-file",
    };

    var sign_cmd: ?[]const u8 = null;
    for (sign_tools) |tool| {
        if (std.mem.indexOf(u8, tool, "*") == null) {
            if (fileExists(tool)) {
                sign_cmd = tool;
                break;
            }
        }
    }

    if (sign_cmd == null) {
        // Fall back to sbsign
        if (fileExists("/usr/bin/sbsign")) {
            // sbsign has different syntax
            const result = std.process.run(allocator, io, .{
                .argv = &.{
                    "sbsign",
                    "--key",    paths.mok_key,
                    "--cert",   paths.mok_pem,
                    "--output", module_path,
                    module_path,
                },
            }) catch return false;
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);

            return result.term == .exited and result.term.exited == 0;
        }
        return error.NoSignTool;
    }

    // Use sign-file
    const result = std.process.run(allocator, io, .{
        .argv = &.{
            sign_cmd.?,
            "sha256",
            paths.mok_key,
            paths.mok_cert,
            module_path,
        },
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return result.term == .exited and result.term.exited == 0;
}

/// Sign all NVIDIA modules in a directory
pub fn signNvidiaModules(allocator: std.mem.Allocator, source_dir: []const u8, writer: *std.Io.Writer) !u32 {
    var signed_count: u32 = 0;

    for (nvidia_modules) |module| {
        // Try different possible locations
        const locations = [_][]const u8{
            "kernel-open",
            "kernel",
            ".",
        };

        for (locations) |loc| {
            const module_path = std.fs.path.join(allocator, &.{ source_dir, loc, module }) catch continue;
            defer allocator.free(module_path);

            if (fileExists(module_path)) {
                try writer.print("  Signing: {s}...", .{module});

                if (signModule(allocator, module_path)) |_| {
                    try writer.print(" OK\n", .{});
                    signed_count += 1;
                } else |err| {
                    try writer.print(" FAILED ({s})\n", .{@errorName(err)});
                }
                break;
            }
        }
    }

    return signed_count;
}

/// Verify a module's signature
pub fn verifyModule(allocator: std.mem.Allocator, module_path: []const u8) !bool {
    const io = std.Options.debug_io;

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "modinfo", "-F", "sig_id", module_path },
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return result.term == .exited and result.term.exited == 0 and result.stdout.len > 0;
}

/// Print signing status
pub fn printStatus(allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    const status = try getStatus(allocator);

    try writer.print("SecureBoot Module Signing Status\n\n", .{});

    try writer.print("  SecureBoot:     ", .{});
    if (status.enabled) {
        try writer.print("ENABLED\n", .{});
    } else {
        try writer.print("Disabled\n", .{});
    }

    try writer.print("  MOK Key:        ", .{});
    if (status.mok_key_exists) {
        try writer.print("Present ({s})\n", .{paths.mok_key});
    } else {
        try writer.print("Not found\n", .{});
    }

    try writer.print("  MOK Certificate:", .{});
    if (status.mok_cert_exists) {
        try writer.print(" Present ({s})\n", .{paths.mok_cert});
    } else {
        try writer.print(" Not found\n", .{});
    }

    try writer.print("  MOK Enrolled:   ", .{});
    if (status.mok_enrolled) {
        try writer.print("Yes\n", .{});
    } else if (status.mok_cert_exists) {
        try writer.print("No (run 'nvfury sign enroll')\n", .{});
    } else {
        try writer.print("N/A\n", .{});
    }

    try writer.print("  Modules Signed: ", .{});
    if (status.modules_signed) {
        try writer.print("Yes\n", .{});
    } else {
        try writer.print("No\n", .{});
    }

    if (status.enabled and !status.mok_enrolled) {
        try writer.print("\nSecureBoot is enabled but MOK is not enrolled.\n", .{});
        try writer.print("Unsigned kernel modules will fail to load.\n", .{});
        try writer.print("\nTo set up module signing:\n", .{});
        try writer.print("  1. sudo nvfury sign setup   # Generate keys\n", .{});
        try writer.print("  2. sudo nvfury sign enroll  # Enroll MOK (requires reboot)\n", .{});
        try writer.print("  3. nvfury install --sign    # Install with signing\n", .{});
    }
}

test "sign module" {
    _ = isSecureBootEnabled();
    _ = fileExists("/nonexistent");
}
