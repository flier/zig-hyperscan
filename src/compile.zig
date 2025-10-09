const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const check = @import("error.zig").check;

pub const Pattern = @import("pattern.zig");

/// Compile mode flags
pub const Mode = packed struct(u32) {
    /// Block scan (non-streaming) database.
    block: bool = false,
    /// Streaming database.
    stream: bool = false,
    /// Vectored scanning database.
    vectored: bool = false,

    _reserved: u21 = 0,

    /// Use full precision to track start of match offsets in stream state.
    som_horizon_large: bool = false,
    /// Use medium precision to track start of match offsets in stream state.
    som_horizon_medium: bool = false,
    /// Use limited precision to track start of match offsets in stream state.
    som_horizon_small: bool = false,

    _reserved2: u5 = 0,

    pub inline fn value(self: Mode) u32 {
        return @bitCast(self);
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
    Generic = 0,
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
    cpu_features: CpuFeatures = .Generic,

    /// Utility function to test the current system architecture.
    pub fn valid() !void {
        return check(hs.hs_valid_platform());
    }

    /// Populates the platform information based on the current host.
    pub fn populate() !Platform {
        var platform: hs.hs_platform_info_t = undefined;

        try check(hs.hs_populate_platform(&platform));

        return Platform{
            .tune = @enumFromInt(platform.tune),
            .cpu_features = @enumFromInt(platform.cpu_features),
        };
    }
};

/// Compile options.
pub const CompileOptions = struct {
    /// The allocator to use for the compile.
    allocator: std.mem.Allocator = std.heap.c_allocator,
    /// Compile mode flags
    mode: Mode,
    /// The target platform for the database.
    platform: ?Platform = null,
    /// Whether to compile a pure literal expression.
    literal: bool = false,

    fn getPlatform(self: CompileOptions) ?hs.hs_platform_info_t {
        return if (self.platform) |p| hs.hs_platform_info_t{
            .tune = @intFromEnum(p.tune),
            .cpu_features = @intFromEnum(p.cpu_features),
            .reserved1 = 0,
            .reserved2 = 0,
        } else null;
    }
};

/// The basic regular expression compiler.
pub fn compile(pattern: *const Pattern, opts: CompileOptions) !*const hs.hs_database_t {
    var db: ?*hs.hs_database_t = null;
    var err: ?*hs.hs_compile_error_t = null;

    const flags = pattern.flags.value();
    const mode = opts.mode.value();
    const platform = if (opts.getPlatform()) |p| &p else null;

    const _compile = if (opts.literal) hs.hs_compile_lit else hs.hs_compile;
    const res = _compile(pattern.expr.ptr, flags, pattern.expr.len, mode, platform, &db, &err);

    free_compile_error([_]Pattern{pattern.*}, err);

    try check(res);

    return db orelse return error.UnknownError;
}

/// The multiple regular expression compiler.
pub fn compile_multi(patterns: []const Pattern, opts: CompileOptions) !*const hs.hs_database_t {
    var exprs = try std.ArrayList([*]const u8).initCapacity(opts.allocator, patterns.len);
    var flags = try std.ArrayList(u32).initCapacity(opts.allocator, patterns.len);
    var ids = try std.ArrayList(u32).initCapacity(opts.allocator, patterns.len);
    var lens = try std.ArrayList(usize).initCapacity(opts.allocator, patterns.len);
    var exts = try std.ArrayList(hs.hs_expr_ext_t).initCapacity(opts.allocator, patterns.len);
    var exts_ptrs = try std.ArrayList(*const hs.hs_expr_ext_t).initCapacity(opts.allocator, patterns.len);

    defer exprs.deinit(opts.allocator);
    defer flags.deinit(opts.allocator);
    defer ids.deinit(opts.allocator);
    defer lens.deinit(opts.allocator);
    defer exts.deinit(opts.allocator);
    defer exts_ptrs.deinit(opts.allocator);

    var has_exts = false;

    for (patterns, 0..) |pattern, i| {
        try exprs.append(opts.allocator, pattern.expr.ptr);
        try flags.append(opts.allocator, pattern.flags.value());
        try ids.append(opts.allocator, pattern.id orelse @intCast(i));
        try lens.append(opts.allocator, pattern.expr.len);
        try exts.append(opts.allocator, if (pattern.ext) |ext| @bitCast(ext.value()) else hs.hs_expr_ext_t{});
        try exts_ptrs.append(opts.allocator, &exts.items[exts.items.len - 1]);

        has_exts |= pattern.ext != null;
    }

    const elems: u32 = @intCast(patterns.len);
    const mode = opts.mode.value();
    const platform = if (opts.getPlatform()) |p| &p else null;

    var db: ?*hs.hs_database_t = null;
    var err: ?*hs.hs_compile_error_t = null;

    var res: c_int = 0;

    if (opts.literal) {
        res = hs.hs_compile_lit_multi(exprs.items.ptr, flags.items.ptr, ids.items.ptr, lens.items.ptr, elems, mode, platform, &db, &err);
    } else if (has_exts) {
        res = hs.hs_compile_ext_multi(exprs.items.ptr, flags.items.ptr, ids.items.ptr, exts_ptrs.items.ptr, elems, mode, platform, &db, &err);
    } else {
        res = hs.hs_compile_multi(exprs.items.ptr, flags.items.ptr, ids.items.ptr, elems, mode, platform, &db, &err);
    }

    free_compile_error(patterns, err);

    try check(res);

    return db orelse return error.UnknownError;
}

fn free_compile_error(patterns: []const Pattern, err: ?*hs.hs_compile_error_t) void {
    if (err) |ce| {
        defer check(hs.hs_free_compile_error(ce)) catch |e| {
            std.log.err("free compile error: {s}", .{@errorName(e)});
        };

        std.log.warn("compile expression `{f}` failed, {s}", .{ patterns[@intCast(ce.expression)], ce.message });
    }
}
