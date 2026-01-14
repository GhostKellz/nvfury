//! nvfury/gpu - GPU Detection & Architecture Info
//!
//! Detects NVIDIA GPU architecture for patch recommendations.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;

/// NVIDIA GPU Architecture
pub const Architecture = enum {
    unknown,
    kepler,      // GTX 600/700
    maxwell,     // GTX 900
    pascal,      // GTX 10 series
    volta,       // Titan V, Quadro GV100
    turing,      // RTX 20 series
    ampere,      // RTX 30 series
    ada_lovelace, // RTX 40 series
    blackwell,   // RTX 50 series

    pub fn name(self: Architecture) []const u8 {
        return switch (self) {
            .unknown => "Unknown",
            .kepler => "Kepler",
            .maxwell => "Maxwell",
            .pascal => "Pascal",
            .volta => "Volta",
            .turing => "Turing",
            .ampere => "Ampere",
            .ada_lovelace => "Ada Lovelace",
            .blackwell => "Blackwell",
        };
    }

    pub fn generation(self: Architecture) []const u8 {
        return switch (self) {
            .unknown => "Unknown",
            .kepler => "GTX 600/700",
            .maxwell => "GTX 900",
            .pascal => "GTX 10",
            .volta => "Titan V",
            .turing => "RTX 20",
            .ampere => "RTX 30",
            .ada_lovelace => "RTX 40",
            .blackwell => "RTX 50",
        };
    }

    pub fn isRtx(self: Architecture) bool {
        return switch (self) {
            .turing, .ampere, .ada_lovelace, .blackwell => true,
            else => false,
        };
    }

    pub fn supportsReflex(self: Architecture) bool {
        return self.isRtx();
    }

    pub fn supportsDlss(self: Architecture) bool {
        return self.isRtx();
    }

    pub fn supportsDlss3(self: Architecture) bool {
        return switch (self) {
            .ada_lovelace, .blackwell => true,
            else => false,
        };
    }
};

/// Detected GPU information
pub const GpuInfo = struct {
    name: [64]u8 = [_]u8{0} ** 64,
    name_len: usize = 0,
    vendor_id: u16 = 0,
    device_id: u16 = 0,
    architecture: Architecture = .unknown,
    is_nvidia: bool = false,

    pub fn getName(self: *const GpuInfo) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// NVIDIA vendor ID
pub const NVIDIA_VENDOR_ID: u16 = 0x10DE;

/// Device ID to Architecture mapping
/// Based on https://pci-ids.ucw.cz/read/PC/10de
const DeviceArchMapping = struct {
    start: u16,
    end: u16,
    arch: Architecture,
};

const device_arch_map = [_]DeviceArchMapping{
    // Blackwell (RTX 50 series) - GB1xx
    .{ .start = 0x2600, .end = 0x26FF, .arch = .blackwell }, // GB102
    .{ .start = 0x2680, .end = 0x268F, .arch = .blackwell }, // GB103
    .{ .start = 0x2700, .end = 0x27FF, .arch = .blackwell }, // GB10x variants

    // Ada Lovelace (RTX 40 series) - AD1xx
    .{ .start = 0x2600, .end = 0x26FF, .arch = .ada_lovelace }, // Note: Overlaps - Blackwell takes precedence
    .{ .start = 0x2700, .end = 0x27FF, .arch = .ada_lovelace },
    .{ .start = 0x2800, .end = 0x28FF, .arch = .ada_lovelace },
    .{ .start = 0x2200, .end = 0x22FF, .arch = .ada_lovelace }, // AD102
    .{ .start = 0x2300, .end = 0x23FF, .arch = .ada_lovelace }, // AD103
    .{ .start = 0x2400, .end = 0x24FF, .arch = .ada_lovelace }, // AD104
    .{ .start = 0x2500, .end = 0x25FF, .arch = .ada_lovelace }, // AD106/107

    // Ampere (RTX 30 series) - GA1xx
    .{ .start = 0x2200, .end = 0x22FF, .arch = .ampere }, // GA102
    .{ .start = 0x2480, .end = 0x24FF, .arch = .ampere }, // GA104
    .{ .start = 0x2500, .end = 0x25FF, .arch = .ampere }, // GA106
    .{ .start = 0x2560, .end = 0x256F, .arch = .ampere }, // GA107

    // Turing (RTX 20 series) - TU1xx
    .{ .start = 0x1E00, .end = 0x1EFF, .arch = .turing }, // TU102
    .{ .start = 0x1F00, .end = 0x1FFF, .arch = .turing }, // TU104/106
    .{ .start = 0x2180, .end = 0x21FF, .arch = .turing }, // TU116/117

    // Volta
    .{ .start = 0x1D00, .end = 0x1DFF, .arch = .volta },

    // Pascal (GTX 10 series) - GP1xx
    .{ .start = 0x1B00, .end = 0x1BFF, .arch = .pascal }, // GP102
    .{ .start = 0x1C00, .end = 0x1CFF, .arch = .pascal }, // GP104/106/107/108

    // Maxwell (GTX 900 series) - GM1xx/GM2xx
    .{ .start = 0x1380, .end = 0x13FF, .arch = .maxwell }, // GM107/108
    .{ .start = 0x1400, .end = 0x14FF, .arch = .maxwell }, // GM204/206

    // Kepler - GK1xx/GK2xx
    .{ .start = 0x1180, .end = 0x11FF, .arch = .kepler },
    .{ .start = 0x1000, .end = 0x10FF, .arch = .kepler },
};

/// Detect architecture from PCI device ID
pub fn detectArchitecture(device_id: u16) Architecture {
    // Check Blackwell first (newest) - specific known IDs
    // RTX 5090: 0x2B85 (GB202)
    // RTX 5080: 0x2B02 (GB203)
    // RTX 5070 Ti: 0x2B03 (GB203)
    // RTX 5070: 0x2B04 (GB205)
    if (device_id == 0x2B85 or device_id == 0x2B02 or
        device_id == 0x2B03 or device_id == 0x2B04 or
        device_id == 0x2B05 or device_id == 0x2B06 or
        device_id == 0x2B07)
    {
        return .blackwell;
    }
    // Also check the range 0x2B00-0x2BFF for Blackwell
    if (device_id >= 0x2B00 and device_id <= 0x2BFF) {
        return .blackwell;
    }

    // Check Ada Lovelace specific IDs (RTX 40 series)
    // RTX 4090: 0x2684 (AD102)
    // RTX 4080: 0x2704, 0x2782 (AD103)
    // RTX 4070 Ti: 0x2786 (AD104)
    if (device_id == 0x2684 or device_id == 0x2704 or
        device_id == 0x2782 or device_id == 0x2786 or
        device_id == 0x2204)
    {
        return .ada_lovelace;
    }
    // Ada Lovelace range: 0x2200-0x27FF (excluding Blackwell 0x2B00-0x2BFF)
    if (device_id >= 0x2200 and device_id <= 0x27FF) {
        return .ada_lovelace;
    }

    // Use the mapping table for others
    for (device_arch_map) |mapping| {
        if (device_id >= mapping.start and device_id <= mapping.end) {
            return mapping.arch;
        }
    }

    return .unknown;
}

/// Detect GPU from sysfs
/// Iterates over all DRM cards to find NVIDIA GPU
pub fn detectGpu() ?GpuInfo {
    var info = GpuInfo{};

    // Iterate over card0 through card7 to find NVIDIA GPU
    var card_num: u8 = 0;
    while (card_num < 8) : (card_num += 1) {
        var vendor_path_buf: [64]u8 = undefined;
        var device_path_buf: [64]u8 = undefined;

        const vendor_path = std.fmt.bufPrint(&vendor_path_buf, "/sys/class/drm/card{d}/device/vendor", .{card_num}) catch continue;
        const device_path = std.fmt.bufPrint(&device_path_buf, "/sys/class/drm/card{d}/device/device", .{card_num}) catch continue;

        // Read vendor ID
        if (readSysfsHex(vendor_path)) |vendor| {
            const vendor_id: u16 = @truncate(vendor);
            if (vendor_id == NVIDIA_VENDOR_ID) {
                // Found NVIDIA GPU
                info.vendor_id = vendor_id;
                info.is_nvidia = true;

                // Read device ID
                if (readSysfsHex(device_path)) |device| {
                    info.device_id = @truncate(device);
                    info.architecture = detectArchitecture(info.device_id);
                }

                // Try to get GPU name from nvidia-smi
                if (getGpuNameFromNvidiaSmi()) |name| {
                    const len = @min(name.len, info.name.len);
                    @memcpy(info.name[0..len], name[0..len]);
                    info.name_len = len;
                } else {
                    // Fallback name based on architecture
                    const fallback = info.architecture.generation();
                    const len = @min(fallback.len, info.name.len);
                    @memcpy(info.name[0..len], fallback);
                    info.name_len = len;
                }

                return info;
            }
        }
    }

    return null;
}

/// Read hex value from sysfs file
fn readSysfsHex(path: []const u8) ?u32 {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0) catch return null;
    defer std.posix.close(fd);

    var buf: [32]u8 = undefined;
    const len = std.posix.read(fd, &buf) catch return null;
    const content = mem.trim(u8, buf[0..len], " \t\n\r");

    // Parse 0xXXXX format
    if (content.len > 2 and content[0] == '0' and content[1] == 'x') {
        return std.fmt.parseInt(u32, content[2..], 16) catch return null;
    }
    return std.fmt.parseInt(u32, content, 16) catch return null;
}

/// Get GPU name from nvidia-smi
fn getGpuNameFromNvidiaSmi() ?[]const u8 {
    // Static buffer for GPU name
    const S = struct {
        var name_buf: [64]u8 = undefined;
        var name_len: usize = 0;
    };

    const io = std.Options.debug_io;
    const result = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "nvidia-smi", "--query-gpu=name", "--format=csv,noheader,nounits" },
    }) catch return null;
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        return null;
    }

    const name = mem.trim(u8, result.stdout, " \t\n\r");
    if (name.len == 0) return null;

    // Handle multi-GPU (take first line)
    const first_line = if (mem.indexOf(u8, name, "\n")) |idx| name[0..idx] else name;

    S.name_len = @min(first_line.len, S.name_buf.len);
    @memcpy(S.name_buf[0..S.name_len], first_line[0..S.name_len]);

    return S.name_buf[0..S.name_len];
}

/// Get recommended patches for detected GPU
pub fn getRecommendedPatches(arch: Architecture, kernel_compiler: []const u8) []const []const u8 {
    // Static arrays for different configurations
    const base_patches = [_][]const u8{
        "gaming-scheduler",
        "memory-optimize",
    };

    const clang_patches = [_][]const u8{
        "clang-compat",
        "gaming-scheduler",
        "memory-optimize",
    };

    const blackwell_patches = [_][]const u8{
        "clang-compat",
        "gaming-scheduler",
        "memory-optimize",
        "blackwell-boost-gaming",
        "blackwell-power-curve",
    };

    const blackwell_patches_gcc = [_][]const u8{
        "gaming-scheduler",
        "memory-optimize",
        "blackwell-boost-gaming",
        "blackwell-power-curve",
    };

    const is_clang = mem.indexOf(u8, kernel_compiler, "clang") != null;

    if (arch == .blackwell) {
        return if (is_clang) &blackwell_patches else &blackwell_patches_gcc;
    }

    return if (is_clang) &clang_patches else &base_patches;
}

/// Check if architecture benefits from specific patch
pub fn patchBenefitsArch(patch_name: []const u8, arch: Architecture) bool {
    // Blackwell-specific patches
    if (mem.eql(u8, patch_name, "blackwell-boost-gaming") or
        mem.eql(u8, patch_name, "blackwell-power-curve"))
    {
        return arch == .blackwell;
    }

    // AMD X3D optimization - check CPU, not GPU (always return true, CPU detection elsewhere)
    if (mem.eql(u8, patch_name, "amd-x3d-optimized")) {
        return true; // Let CPU detection handle this
    }

    // General patches benefit all
    return true;
}

test "architecture detection" {
    // Blackwell (RTX 50 series)
    try std.testing.expectEqual(Architecture.blackwell, detectArchitecture(0x2B85)); // RTX 5090
    try std.testing.expectEqual(Architecture.blackwell, detectArchitecture(0x2B02)); // RTX 5080
    try std.testing.expectEqual(Architecture.blackwell, detectArchitecture(0x2B03)); // RTX 5070 Ti

    // Ada Lovelace (RTX 40 series)
    try std.testing.expectEqual(Architecture.ada_lovelace, detectArchitecture(0x2684)); // RTX 4090
    try std.testing.expectEqual(Architecture.ada_lovelace, detectArchitecture(0x2204)); // RTX 4090 variant
}

test "architecture properties" {
    try std.testing.expect(Architecture.blackwell.isRtx());
    try std.testing.expect(Architecture.blackwell.supportsDlss3());
    try std.testing.expect(!Architecture.ampere.supportsDlss3());
    try std.testing.expect(Architecture.turing.supportsReflex());
}

// ============================================================================
// Multi-GPU Support
// ============================================================================

/// GPU type classification
pub const GpuType = enum {
    unknown,
    discrete,   // Dedicated GPU (dGPU)
    integrated, // Integrated GPU (iGPU)
    external,   // External GPU (eGPU via Thunderbolt)

    pub fn name(self: GpuType) []const u8 {
        return switch (self) {
            .unknown => "Unknown",
            .discrete => "Discrete",
            .integrated => "Integrated",
            .external => "External",
        };
    }
};

/// GPU vendor
pub const GpuVendor = enum {
    unknown,
    nvidia,
    amd,
    intel,

    pub fn name(self: GpuVendor) []const u8 {
        return switch (self) {
            .unknown => "Unknown",
            .nvidia => "NVIDIA",
            .amd => "AMD",
            .intel => "Intel",
        };
    }
};

/// Vendor IDs
pub const VENDOR_AMD: u16 = 0x1002;
pub const VENDOR_INTEL: u16 = 0x8086;

/// Extended GPU information for multi-GPU systems
pub const GpuDevice = struct {
    /// DRM card number (card0, card1, etc.)
    card_num: u8 = 0,
    /// PCI bus address (e.g., "0000:01:00.0")
    pci_address: [16]u8 = [_]u8{0} ** 16,
    pci_address_len: usize = 0,
    /// Device name
    name: [64]u8 = [_]u8{0} ** 64,
    name_len: usize = 0,
    /// Vendor ID
    vendor_id: u16 = 0,
    /// Device ID
    device_id: u16 = 0,
    /// Vendor enum
    vendor: GpuVendor = .unknown,
    /// GPU type
    gpu_type: GpuType = .unknown,
    /// NVIDIA architecture (if applicable)
    architecture: Architecture = .unknown,
    /// Is this the primary/render GPU?
    is_primary: bool = false,
    /// Power state (for discrete GPUs)
    power_state: ?[]const u8 = null,

    pub fn getName(self: *const GpuDevice) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getPciAddress(self: *const GpuDevice) []const u8 {
        return self.pci_address[0..self.pci_address_len];
    }

    pub fn isNvidia(self: *const GpuDevice) bool {
        return self.vendor == .nvidia;
    }
};

/// Multi-GPU system information
pub const MultiGpuInfo = struct {
    /// All detected GPUs
    gpus: [8]GpuDevice = [_]GpuDevice{.{}} ** 8,
    /// Number of GPUs found
    count: usize = 0,
    /// Number of NVIDIA GPUs
    nvidia_count: usize = 0,
    /// Is this a hybrid graphics system? (iGPU + dGPU)
    is_hybrid: bool = false,
    /// Primary GPU index
    primary_gpu: usize = 0,

    /// Get NVIDIA GPUs only
    pub fn nvidiaGpus(self: *const MultiGpuInfo) []const GpuDevice {
        // Return a slice of all GPUs, caller should filter
        return self.gpus[0..self.count];
    }

    /// Get primary NVIDIA GPU (if any)
    pub fn primaryNvidia(self: *const MultiGpuInfo) ?*const GpuDevice {
        for (&self.gpus, 0..) |*gpu, i| {
            if (i >= self.count) break;
            if (gpu.isNvidia() and gpu.is_primary) {
                return gpu;
            }
        }
        // Fallback to first NVIDIA GPU
        for (&self.gpus, 0..) |*gpu, i| {
            if (i >= self.count) break;
            if (gpu.isNvidia()) {
                return gpu;
            }
        }
        return null;
    }
};

/// Detect all GPUs in the system
pub fn detectAllGpus() MultiGpuInfo {
    var info = MultiGpuInfo{};

    // Check /sys/class/drm for all cards
    var card_num: u8 = 0;
    while (card_num < 8) : (card_num += 1) {
        var vendor_path_buf: [64]u8 = undefined;
        var device_path_buf: [64]u8 = undefined;
        var pci_path_buf: [64]u8 = undefined;

        const vendor_path = std.fmt.bufPrint(&vendor_path_buf, "/sys/class/drm/card{d}/device/vendor", .{card_num}) catch continue;
        const device_path = std.fmt.bufPrint(&device_path_buf, "/sys/class/drm/card{d}/device/device", .{card_num}) catch continue;

        // Read vendor ID
        if (readSysfsHex(vendor_path)) |vendor| {
            var gpu = GpuDevice{
                .card_num = card_num,
                .vendor_id = @truncate(vendor),
            };

            // Determine vendor
            gpu.vendor = switch (gpu.vendor_id) {
                NVIDIA_VENDOR_ID => .nvidia,
                VENDOR_AMD => .amd,
                VENDOR_INTEL => .intel,
                else => .unknown,
            };

            // Read device ID
            if (readSysfsHex(device_path)) |device| {
                gpu.device_id = @truncate(device);
            }

            // Get PCI address
            const pci_link_path = std.fmt.bufPrint(&pci_path_buf, "/sys/class/drm/card{d}/device", .{card_num}) catch continue;
            if (getPciAddress(pci_link_path)) |pci_addr| {
                const len = @min(pci_addr.len, gpu.pci_address.len);
                @memcpy(gpu.pci_address[0..len], pci_addr[0..len]);
                gpu.pci_address_len = len;
            }

            // Determine GPU type
            gpu.gpu_type = detectGpuType(gpu.vendor, gpu.device_id);

            // For NVIDIA, detect architecture
            if (gpu.vendor == .nvidia) {
                gpu.architecture = detectArchitecture(gpu.device_id);
                info.nvidia_count += 1;
            }

            // Get GPU name
            if (gpu.vendor == .nvidia) {
                if (getGpuNameFromNvidiaSmi()) |name_str| {
                    const len = @min(name_str.len, gpu.name.len);
                    @memcpy(gpu.name[0..len], name_str[0..len]);
                    gpu.name_len = len;
                } else {
                    // Fallback name
                    const fallback = gpu.architecture.generation();
                    const len = @min(fallback.len, gpu.name.len);
                    @memcpy(gpu.name[0..len], fallback);
                    gpu.name_len = len;
                }
            } else {
                // For non-NVIDIA, use vendor name
                const vendor_name = gpu.vendor.name();
                const len = @min(vendor_name.len, gpu.name.len);
                @memcpy(gpu.name[0..len], vendor_name);
                gpu.name_len = len;
            }

            // First discrete NVIDIA is typically primary for gaming
            if (gpu.vendor == .nvidia and gpu.gpu_type == .discrete and info.nvidia_count == 1) {
                gpu.is_primary = true;
                info.primary_gpu = info.count;
            }

            info.gpus[info.count] = gpu;
            info.count += 1;
        }
    }

    // Detect hybrid graphics
    var has_igpu = false;
    var has_dgpu = false;
    for (info.gpus[0..info.count]) |gpu| {
        if (gpu.gpu_type == .integrated) has_igpu = true;
        if (gpu.gpu_type == .discrete) has_dgpu = true;
    }
    info.is_hybrid = has_igpu and has_dgpu;

    return info;
}

/// Detect GPU type from vendor and device ID
fn detectGpuType(vendor: GpuVendor, device_id: u16) GpuType {
    switch (vendor) {
        .intel => {
            // Intel GPUs are typically integrated
            // Some discrete Arc GPUs exist but are less common
            // Arc A-series starts at 0x56xx
            if (device_id >= 0x5600 and device_id <= 0x56FF) {
                return .discrete; // Intel Arc
            }
            return .integrated;
        },
        .amd => {
            // AMD APU integrated GPUs have specific device IDs
            // Ryzen iGPUs are in ranges like 0x15xx, 0x16xx, 0x17xx
            if ((device_id >= 0x1500 and device_id <= 0x17FF) or
                (device_id >= 0x1630 and device_id <= 0x164F) or
                (device_id >= 0x1900 and device_id <= 0x19FF))
            {
                return .integrated;
            }
            return .discrete;
        },
        .nvidia => {
            // NVIDIA GPUs are almost always discrete
            // Exception: Some Tegra SoCs, but those are rare on desktop Linux
            return .discrete;
        },
        else => return .unknown,
    }
}

/// Get PCI address from sysfs device link
fn getPciAddress(device_path: []const u8) ?[]const u8 {
    const S = struct {
        var buf: [16]u8 = undefined;
        var len: usize = 0;
    };

    // Create null-terminated path
    var path_buf: [512]u8 = undefined;
    if (device_path.len >= path_buf.len) return null;
    @memcpy(path_buf[0..device_path.len], device_path);
    path_buf[device_path.len] = 0;

    var link_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const result = std.c.readlink(@ptrCast(&path_buf), &link_buf, link_buf.len);
    if (result < 0) return null;
    const link = link_buf[0..@intCast(result)];

    // Extract PCI address from path like "../../devices/pci0000:00/0000:00:01.0/0000:01:00.0"
    // We want the last segment
    if (mem.lastIndexOf(u8, link, "/")) |last_slash| {
        const pci_addr = link[last_slash + 1 ..];
        if (pci_addr.len > 0 and pci_addr.len <= S.buf.len) {
            @memcpy(S.buf[0..pci_addr.len], pci_addr);
            S.len = pci_addr.len;
            return S.buf[0..S.len];
        }
    }

    return null;
}

/// Print multi-GPU status
pub fn printMultiGpuStatus(info: *const MultiGpuInfo, writer: anytype) !void {
    try writer.print("GPU Configuration:\n", .{});
    try writer.print("---------------------------------------------------\n", .{});
    try writer.print("Total GPUs:    {d}\n", .{info.count});
    try writer.print("NVIDIA GPUs:   {d}\n", .{info.nvidia_count});
    try writer.print("Hybrid System: {}\n\n", .{info.is_hybrid});

    for (info.gpus[0..info.count], 0..) |gpu, i| {
        try writer.print("GPU {d}: {s}\n", .{ i, gpu.getName() });
        try writer.print("  Vendor:       {s} (0x{x:0>4})\n", .{ gpu.vendor.name(), gpu.vendor_id });
        try writer.print("  Device ID:    0x{x:0>4}\n", .{gpu.device_id});
        try writer.print("  Type:         {s}\n", .{gpu.gpu_type.name()});
        try writer.print("  PCI Address:  {s}\n", .{gpu.getPciAddress()});

        if (gpu.isNvidia()) {
            try writer.print("  Architecture: {s}\n", .{gpu.architecture.name()});
            try writer.print("  RTX Support:  {}\n", .{gpu.architecture.isRtx()});
            try writer.print("  DLSS3:        {}\n", .{gpu.architecture.supportsDlss3()});
        }

        if (gpu.is_primary) {
            try writer.print("  ** Primary GPU **\n", .{});
        }
        try writer.print("\n", .{});
    }

    if (info.is_hybrid) {
        try writer.print("Note: Hybrid graphics detected. Use prime-run or similar\n", .{});
        try writer.print("      to run applications on the discrete NVIDIA GPU.\n", .{});
    }
}

test "multi-gpu detection types" {
    // Test GPU type detection
    try std.testing.expectEqual(GpuType.discrete, detectGpuType(.nvidia, 0x2684));
    try std.testing.expectEqual(GpuType.integrated, detectGpuType(.intel, 0x4626));
    try std.testing.expectEqual(GpuType.discrete, detectGpuType(.intel, 0x5690)); // Arc
}
