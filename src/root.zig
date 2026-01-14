//! nvfury - NVIDIA Open Kernel Module Forge
//!
//! Performance-tuned NVIDIA open driver builder for Linux gaming.
//! Fetches, patches, compiles, and installs NVIDIA open GPU kernel modules
//! with aggressive performance tuning.

pub const version = struct {
    pub const major = 0;
    pub const minor = 1;
    pub const patch = 0;
    pub const string = "0.1.0";
};

pub const fetch = @import("fetch.zig");
pub const patch = @import("patch.zig");
pub const builder = @import("builder.zig");
pub const install = @import("install.zig");
pub const tune = @import("tune.zig");
pub const dkms = @import("dkms.zig");
pub const config = @import("config.zig");
pub const gpu = @import("gpu.zig");

/// Default paths for nvfury
pub const paths = struct {
    /// Cache directory for source and builds
    pub const cache = "~/.cache/nvfury/";
    /// Config directory
    pub const config_dir = "~/.config/nvfury/";
    /// NVIDIA open source cache
    pub const source = "~/.cache/nvfury/nvidia-open/";
    /// Build output cache
    pub const build_output = "~/.cache/nvfury/build/";
    /// Module backup location
    pub const backup = "/var/lib/nvfury/backup/";
    /// Modprobe config output
    pub const modprobe = "/etc/modprobe.d/nvfury.conf";
};

/// Supported NVIDIA driver versions (590+ with GSP support)
pub const supported_versions = [_][]const u8{
    "590.48.01", // Current stable with GSP=1
    "590.36.01",
    "585.143.02",
    "580.105.08",
};

/// GPU architecture support
pub const Architecture = enum {
    turing, // RTX 20xx, GTX 16xx
    ampere, // RTX 30xx
    ada_lovelace, // RTX 40xx
    hopper, // Data center
    blackwell, // RTX 50xx

    pub fn supportsOpen(self: Architecture) bool {
        // All supported architectures work with open modules
        _ = self;
        return true;
    }

    pub fn minDriverVersion(self: Architecture) []const u8 {
        return switch (self) {
            .turing, .ampere => "515.43.04",
            .ada_lovelace => "525.60.11",
            .hopper => "525.60.11",
            .blackwell => "565.57.01",
        };
    }
};

test "version info" {
    const std = @import("std");
    try std.testing.expect(version.major == 0);
    try std.testing.expect(version.minor == 1);
}
