//! The Hyperscan compiler API definition.

const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

pub const Pattern = @import("compile/pattern.zig");
pub const Platform = @import("compile/platform.zig");

const check = @import("common.zig").check;

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

    /// Get the value of the mode.
    pub inline fn value(self: Mode) u32 {
        return @bitCast(self);
    }
};

test Mode {
    try std.testing.expectEqual(0, Mode.value(Mode{}));
    try std.testing.expectEqual(hs.HS_MODE_BLOCK, Mode.value(Mode{ .block = true }));
    try std.testing.expectEqual(hs.HS_MODE_STREAM, Mode.value(Mode{ .stream = true }));
    try std.testing.expectEqual(hs.HS_MODE_VECTORED, Mode.value(Mode{ .vectored = true }));
    try std.testing.expectEqual(hs.HS_MODE_BLOCK | hs.HS_MODE_SOM_HORIZON_LARGE, Mode.value(Mode{ .block = true, .som_horizon_large = true }));
    try std.testing.expectEqual(hs.HS_MODE_STREAM | hs.HS_MODE_SOM_HORIZON_MEDIUM, Mode.value(Mode{ .stream = true, .som_horizon_medium = true }));
    try std.testing.expectEqual(hs.HS_MODE_VECTORED | hs.HS_MODE_SOM_HORIZON_SMALL, Mode.value(Mode{ .vectored = true, .som_horizon_small = true }));
}

/// Compile options.
pub const Options = struct {
    /// The allocator to use for the compile.
    allocator: std.mem.Allocator = std.heap.c_allocator,
    /// Compile mode flags
    mode: Mode,
    /// The target platform for the database.
    platform: ?Platform = null,
    /// Whether to compile a pure literal expression.
    literal: bool = false,
};

/// The basic regular expression compiler.
pub fn compile(pattern: *const Pattern, opts: Options) !*const hs.hs_database_t {
    var db: ?*hs.hs_database_t = null;
    var err: ?*hs.hs_compile_error_t = null;

    const flags = pattern.flags.value();
    const mode = opts.mode.value();
    const platform_info: ?hs.hs_platform_info_t = if (opts.platform) |p| @bitCast(p.raw()) else null;
    const platform = if (platform_info) |p| &p else null;

    const compile_fn = if (opts.literal) hs.hs_compile_lit else hs.hs_compile;
    const res = compile_fn(pattern.expr.ptr, flags, pattern.expr.len, mode, platform, &db, &err);

    free_compile_error(err);

    try check(res);

    return db orelse return error.UnknownError;
}

/// The multiple regular expression compiler.
pub fn compile_multi(patterns: []const Pattern, opts: Options) !*const hs.hs_database_t {
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
        try exts.append(opts.allocator, if (pattern.ext) |ext| @bitCast(ext.raw()) else hs.hs_expr_ext_t{});
        try exts_ptrs.append(opts.allocator, &exts.items[exts.items.len - 1]);

        has_exts |= pattern.ext != null;
    }

    const elems: u32 = @intCast(patterns.len);
    const mode = opts.mode.value();
    const platform_info: ?hs.hs_platform_info_t = if (opts.platform) |p| @bitCast(p.raw()) else null;
    const platform = if (platform_info) |p| &p else null;

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

    free_compile_error(err);

    try check(res);

    return db orelse return error.UnknownError;
}

/// Free an error structure generated by `compile`or `compile_multi`.
pub fn free_compile_error(err: ?*hs.hs_compile_error_t) void {
    if (err) |ce| {
        if (ce.expression >= 0) {
            std.log.warn("compile expression #{d} failed, {s}", .{ ce.expression, ce.message });
        } else {
            std.log.warn("compile failed, {s}", .{ce.message});
        }

        check(hs.hs_free_compile_error(ce)) catch |e| {
            std.log.err("free compile error: {s}", .{@errorName(e)});
        };
    }
}

test {
    _ = @import("compile/expr_ext.zig");
    _ = @import("compile/expr_info.zig");
    _ = @import("compile/flags.zig");
    _ = @import("compile/pattern.zig");
    _ = @import("compile/platform.zig");
}
