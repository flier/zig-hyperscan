//! A type containing information related to an expression that is returned by `expre_info`.

const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const check = @import("error.zig").check;

const Flags = @import("flags.zig").Flags;
const Ext = @import("expr_ext.zig").Ext;

/// The minimum length in bytes of a match for the pattern.
min_width: u32,
/// The maximum length in bytes of a match for the pattern.
///
/// If the pattern has an unbounded maximum length, this will be set to `null`.
max_width: ?u32,
/// Whether this expression can produce matches that are not returned in order, such as those produced by assertions.
unordered_matches: bool,
/// Whether this expression can produce matches at end of data (EOD).
matches_at_eod: bool,
/// Whether this expression can *only* produce matches at end of data (EOD).
matches_only_at_eod: bool,

const Info = @This();

/// Utility function providing information about a regular expression.
pub fn init(expr: []const u8, flags: Flags, ext: ?Ext) !Info {
    const info: ?*hs.hs_expr_info_t = null;
    const err: ?*hs.hs_compile_error_t = null;

    var res: c_int = 0;

    if (ext) |e| {
        const expr_ext = e.value();

        res = hs.hs_expression_ext_info(expr.ptr, flags.value(), &expr_ext, info, err);
    } else {
        res = hs.hs_expression_info(expr.ptr, flags.value(), info, err);
    }

    if (err) |ce| {
        defer check(hs.hs_free_compile_error(ce)) catch |e| {
            std.log.err("free compile error: {s}", .{@errorName(e)});
        };

        std.log.warn("compile expression `{s}/{f}` failed, {s}", .{ expr, flags, ce.message });
    }

    try check(res);

    return Info{
        .min_width = info.min_width,
        .max_width = if (info.max_width == hs.UINT_MAX) null else info.max_width,
        .unordered_matches = info.unordered_matches != 0,
        .matches_at_eod = info.matches_at_eod != 0,
        .matches_only_at_eod = info.matches_only_at_eod != 0,
    };
}
