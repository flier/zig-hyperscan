//! A type containing information on the target platform which may optionally be
//! provided to the compile calls (compile, compile_multi, compile_ext_multi).

const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const check = @import("../common.zig").check;

/// Tuning flags
pub const Tune = enum(u32) {
    /// Generic
    generic = hs.HS_TUNE_FAMILY_GENERIC,
    /// Intel(R) microarchitecture code name Sandy Bridge
    sandy_bridge = hs.HS_TUNE_FAMILY_SNB,
    /// Intel(R) microarchitecture code name Ivy Bridge
    ivy_bridge = hs.HS_TUNE_FAMILY_IVB,
    /// Intel(R) microarchitecture code name Haswell
    haswell = hs.HS_TUNE_FAMILY_HSW,
    /// Intel(R) microarchitecture code name Silvermont
    silvermont = hs.HS_TUNE_FAMILY_SLM,
    /// Intel(R) microarchitecture code name Broadwell
    broadwell = hs.HS_TUNE_FAMILY_BDW,
    /// Intel(R) microarchitecture code name Skylake
    skylake = hs.HS_TUNE_FAMILY_SKL,
    /// Intel(R) microarchitecture code name Skylake Server
    skylake_server = hs.HS_TUNE_FAMILY_SKX,
    /// Intel(R) microarchitecture code name Goldmont
    goldmont = hs.HS_TUNE_FAMILY_GLM,
    /// Intel(R) microarchitecture code name Icelake
    icelake = hs.HS_TUNE_FAMILY_ICL,
    /// Intel(R) microarchitecture code name Icelake Server
    icelake_server = hs.HS_TUNE_FAMILY_ICX,
};

/// CPU feature support flags
pub const CpuFeatures = enum(u64) {
    /// Intel(R) Advanced Vector Extensions 2 (Intel(R) AVX2)
    avx2 = hs.HS_CPU_FEATURES_AVX2,
    /// Intel(R) Advanced Vector Extensions 512 (Intel(R) AVX512)
    avx512 = hs.HS_CPU_FEATURES_AVX512,
    /// Intel(R) Advanced Vector Extensions 512 Vector Byte Manipulation Instructions (Intel(R) AVX512VBMI)
    avx512vbmi = hs.HS_CPU_FEATURES_AVX512VBMI,
};

const Platform = @This();

tune: Tune = .generic,
cpu_features: ?CpuFeatures = null,

/// Utility function to test the current system architecture.
pub fn valid() !void {
    return check(hs.hs_valid_platform());
}

test valid {
    try Platform.valid();
}

/// Populates the platform information based on the current host.
pub fn populate() !Platform {
    var platform: hs.hs_platform_info_t = undefined;

    try check(hs.hs_populate_platform(&platform));

    return Platform{
        .tune = @enumFromInt(platform.tune),
        .cpu_features = if (platform.cpu_features != 0) @enumFromInt(platform.cpu_features) else null,
    };
}

test populate {
    const platform = try Platform.populate();

    try std.testing.expectEqual(platform.tune, .generic);
    try std.testing.expectEqual(platform.cpu_features, null);
}

/// Utility function to convert the platform to a C type.
pub inline fn raw(self: *const Platform) hs.hs_platform_info_t {
    return hs.hs_platform_info_t{
        .tune = @intFromEnum(self.tune),
        .cpu_features = if (self.cpu_features) |cpu_features| @intFromEnum(cpu_features) else 0,
        .reserved1 = 0,
        .reserved2 = 0,
    };
}

test raw {
    const haswell = Platform{
        .tune = .haswell,
    };

    try std.testing.expectEqual(hs.hs_platform_info_t{
        .tune = hs.HS_TUNE_FAMILY_HSW,
    }, haswell.raw());

    const skylake_server = Platform{
        .tune = .skylake_server,
        .cpu_features = .avx512,
    };

    try std.testing.expectEqual(hs.hs_platform_info_t{
        .tune = hs.HS_TUNE_FAMILY_SKX,
        .cpu_features = hs.HS_CPU_FEATURES_AVX512,
    }, skylake_server.raw());
}
