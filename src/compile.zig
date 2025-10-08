const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const common = @import("common.zig");

/// Compile flags
pub const Flags = enum(u32) {
    /// No flags
    Empty = 0,
    /// Set case-insensitive matching.
    Caseless = hs.HS_FLAG_CASELESS,
    /// Matching a `.` will not exclude newlines.
    DotAll = hs.HS_FLAG_DOTALL,
    /// Set multi-line anchoring.
    Multiline = hs.HS_FLAG_MULTILINE,
    /// Set single-match only mode.
    SingleMatch = hs.HS_FLAG_SINGLEMATCH,
    /// Allow expressions that can match against empty buffers.
    AllowEmpty = hs.HS_FLAG_ALLOWEMPTY,
    /// Enable UTF-8 mode for this expression.
    Utf8 = hs.HS_FLAG_UTF8,
    /// Enable Unicode property support for this expression.
    Ucp = hs.HS_FLAG_UCP,
    /// Enable prefiltering mode for this expression.
    Prefilter = hs.HS_FLAG_PREFILTER,
    /// Enable leftmost start of match reporting.
    SomLeftmost = hs.HS_FLAG_SOM_LEFTMOST,
    /// Logical combination.
    Combination = hs.HS_FLAG_COMBINATION,
    /// Don't do any match reporting.
    Quiet = hs.HS_FLAG_QUIET,
};

/// Compile mode flags
pub const Mode = enum(u32) {
    /// Block scan (non-streaming) database.
    Block = hs.HS_MODE_BLOCK,
    /// Streaming database.
    Stream = hs.HS_MODE_STREAM,
    /// Vectored scanning database.
    Vectored = hs.HS_MODE_VECTORED,
    /// Use full precision to track start of match offsets in stream state.
    SomHorizonLarge = hs.HS_MODE_SOM_HORIZON_LARGE,
    /// Use medium precision to track start of match offsets in stream state.
    SomHorizonMedium = hs.HS_MODE_SOM_HORIZON_MEDIUM,
    /// Use limited precision to track start of match offsets in stream state.
    SomHorizonSmall = hs.HS_MODE_SOM_HORIZON_SMALL,

    pub fn isBlock(self: Mode) bool {
        return (@intFromEnum(self) & hs.HS_MODE_BLOCK) == hs.HS_MODE_BLOCK;
    }

    pub fn isVectored(self: Mode) bool {
        return (@intFromEnum(self) & hs.HS_MODE_VECTORED) == hs.HS_MODE_VECTORED;
    }

    pub fn isStream(self: Mode) bool {
        return (@intFromEnum(self) & hs.HS_MODE_STREAM) == hs.HS_MODE_STREAM;
    }
};

/// Tuning flags
pub const Tune = enum(u32) {
    /// Generic
    Generic = hs.HS_TUNE_FAMILY_GENERIC,
    /// Intel(R) microarchitecture code name Sandy Bridge
    SandyBridge = hs.HS_TUNE_FAMILY_SNB,
    /// Intel(R) microarchitecture code name Ivy Bridge
    IvyBridge = hs.HS_TUNE_FAMILY_IVB,
    /// Intel(R) microarchitecture code name Haswell
    Haswell = hs.HS_TUNE_FAMILY_HSW,
    /// Intel(R) microarchitecture code name Silvermont
    Silvermont = hs.HS_TUNE_FAMILY_SLM,
    /// Intel(R) microarchitecture code name Broadwell
    Broadwell = hs.HS_TUNE_FAMILY_BDW,
    /// Intel(R) microarchitecture code name Skylake
    Skylake = hs.HS_TUNE_FAMILY_SKL,
    /// Intel(R) microarchitecture code name Skylake Server
    SkylakeServer = hs.HS_TUNE_FAMILY_SKX,
    /// Intel(R) microarchitecture code name Goldmont
    Goldmont = hs.HS_TUNE_FAMILY_GLM,
    /// Intel(R) microarchitecture code name Icelake
    Icelake = hs.HS_TUNE_FAMILY_ICL,
    /// Intel(R) microarchitecture code name Icelake Server
    IcelakeServer = hs.HS_TUNE_FAMILY_ICX,
};

/// CPU feature support flags
pub const CpuFeatures = enum(u64) {
    /// No CPU features
    Empty = 0,
    /// Intel(R) Advanced Vector Extensions 2 (Intel(R) AVX2)
    Avx2 = hs.HS_CPU_FEATURES_AVX2,
    /// Intel(R) Advanced Vector Extensions 512 (Intel(R) AVX512)
    Avx512 = hs.HS_CPU_FEATURES_AVX512,
    /// Intel(R) Advanced Vector Extensions 512 Vector Byte Manipulation Instructions (Intel(R) AVX512VBMI)
    Avx512Vbmi = hs.HS_CPU_FEATURES_AVX512VBMI,
};

/// A type containing information on the target platform which may optionally be
/// provided to the compile calls (compile, compile_multi, compile_ext_multi).
pub const Platform = struct {
    tune: Tune = .Generic,
    cpu_features: CpuFeatures = .Empty,

    /// Utility function to test the current system architecture.
    pub fn valid() !void {
        return common.check(hs.hs_valid_platform());
    }

    pub fn populate() !Platform {
        var platform: hs.hs_platform_info_t = undefined;

        try common.check(hs.hs_populate_platform(&platform));

        return Platform{
            .tune = @enumFromInt(platform.tune),
            .cpu_features = @enumFromInt(platform.cpu_features),
        };
    }
};

pub const CompileOptions = struct {
    /// Flags which modify the behaviour of the expression.
    flags: Flags = .Empty,
    /// Compile mode flags
    mode: Mode,
    /// Use full precision to track start of match offsets in stream state.
    som_horizon_large: bool = false,
    /// Use medium precision to track start of match offsets in stream state.
    som_horizon_medium: bool = false,
    /// Use limited precision to track start of match offsets in stream state.
    som_horizon_small: bool = false,
    /// The target platform for the database.
    platform: ?Platform = null,
};

pub fn compile(expr: []const u8, opts: CompileOptions) !*const hs.hs_database_t {
    var db: ?*hs.hs_database_t = null;
    var err: ?*hs.hs_compile_error_t = null;

    const flags = @intFromEnum(opts.flags);
    var mode = @intFromEnum(opts.mode);

    if (opts.som_horizon_large) {
        mode |= hs.HS_MODE_SOM_HORIZON_LARGE;
    } else if (opts.som_horizon_medium) {
        mode |= hs.HS_MODE_SOM_HORIZON_MEDIUM;
    } else if (opts.som_horizon_small) {
        mode |= hs.HS_MODE_SOM_HORIZON_SMALL;
    }

    const platform = if (opts.platform) |p| &hs.hs_platform_info_t{
        .tune = @intFromEnum(p.tune),
        .cpu_features = @intFromEnum(p.cpu_features),
        .reserved1 = 0,
        .reserved2 = 0,
    } else null;

    const res = hs.hs_compile(expr.ptr, flags, mode, platform, &db, &err);
    if (err) |e| {
        defer common.check(hs.hs_free_compile_error(e)) catch {};
    }

    try common.check(res);

    return db orelse return error.UnknownError;
}
