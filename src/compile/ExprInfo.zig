//! A type containing information related to an expression.

const std = @import("std");

const hs = @cImport(@cInclude("hs/hs.h"));

const Flags = @import("flags.zig").Flags;
const ExprExt = @import("ExprExt.zig");

const check = @import("../common.zig").check;
const freeCompileError = @import("../compile.zig").freeCompileError;

/// The maximum length in bytes of a match for the pattern.
pub const MaxLength = union(enum) {
    /// The pattern has an unbounded maximum length.
    unbounded,
    /// The maximum length in bytes of a match for the pattern.
    value: u32,

    fn init(n: c_uint) MaxLength {
        return if (n != std.math.maxInt(c_uint)) .{ .value = n } else .unbounded;
    }
};

/// The minimum length in bytes of a match for the pattern.
min_width: u32,
/// The maximum length in bytes of a match for the pattern.
///
/// If the pattern has an unbounded maximum length, this will be set to `.unbounded`.
max_width: MaxLength,
/// Whether this expression can produce matches that are not returned in order, such as those produced by assertions.
unordered_matches: bool = false,
/// Whether this expression can produce matches at end of data (EOD).
matches_at_eod: bool = false,
/// Whether this expression can *only* produce matches at end of data (EOD).
matches_only_at_eod: bool = false,

const Info = @This();

/// Utility function providing information about a regular expression.
///
/// Analyzes the pattern and returns detailed information about its properties,
/// including minimum/maximum width, match behavior, and other characteristics.
///
/// ## Arguments
/// - `expr`: The pattern to analyze
/// - `flags`: The flags to use for the analysis
/// - `ext`: The additional parameters to use for the analysis
///
/// ## Returns
/// An `Info` struct containing analysis results, or an error if the pattern is invalid.
///
/// # Errors
/// - `error.CompileError`: If the pattern contains invalid regex syntax
///
/// ## Example
/// ```zig
/// const pattern = try Pattern.parse("hello.*world");
/// const info = try pattern.exprInfo();
/// std.log.info("Min width: {}, Max width: {}", .{ info.min_width, info.max_width });
/// ```
pub fn analysis(expr: []const u8, flags: Flags, ext: ?ExprExt) !Info {
    var expr_info: ?*hs.hs_expr_info_t = null;
    var err: ?*hs.hs_compile_error_t = null;

    var res: c_int = 0;

    if (ext) |e| {
        const expr_ext = e.raw();

        res = hs.hs_expression_ext_info(expr.ptr, flags.value(), @ptrCast(&expr_ext), &expr_info, &err);
    } else {
        res = hs.hs_expression_info(expr.ptr, flags.value(), &expr_info, &err);
    }

    freeCompileError(@ptrCast(err));

    try check(res);

    if (expr_info) |i| {
        defer std.c.free(i);

        return .{
            .min_width = i.min_width,
            .max_width = .init(i.max_width),
            .unordered_matches = i.unordered_matches != 0,
            .matches_at_eod = i.matches_at_eod != 0,
            .matches_only_at_eod = i.matches_only_at_eod != 0,
        };
    }

    return error.UnknownError;
}

// Unit tests

test analysis {
    try std.testing.expectEqualDeep(Info{
        .min_width = 3,
        .max_width = .{ .value = 3 },
    }, try analysis("abc", .{}, null));

    try std.testing.expectEqualDeep(Info{
        .min_width = 4,
        .max_width = .unbounded,
    }, try analysis("foo\\d+", .{}, null));
}
