//! A pattern with basic regular expression.

const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const check = @import("error.zig").check;

const Flags = @import("flags.zig").Flags;

/// The regular expression to compile.
expr: []const u8,
/// Flags which modify the behaviour of the expression.
flags: Flags = .{},
/// The id to associate with the expression.
id: ?u32 = null,

const Pattern = @This();

/// Initialize a pattern with expression and flags.
pub fn init(expr: []const u8, flags: Flags) Pattern {
    return Pattern{
        .expr = expr,
        .flags = flags,
        .id = null,
    };
}

/// Parse a pattern from a string.
pub fn parse(s: []const u8) !Pattern {
    if (std.mem.indexOf(u8, s, ":/")) |start| {
        if (std.fmt.parseInt(u32, s[0..start], 10)) |id| {
            if (std.mem.lastIndexOfScalar(u8, s, '/')) |end| {
                if (start + 1 < end) {
                    return Pattern{
                        .expr = s[start + 2 .. end],
                        .flags = try Flags.parse(s[end + 1 ..]),
                        .id = id,
                    };
                }
            }
        } else |_| {}
    }

    if (std.mem.startsWith(u8, s, "/") & std.mem.containsAtLeastScalar(u8, s, 2, '/')) {
        if (std.mem.lastIndexOfScalar(u8, s, '/')) |end| {
            return Pattern{
                .expr = s[1..end],
                .flags = try Flags.parse(s[end + 1 ..]),
                .id = null,
            };
        }
    }

    return Pattern{
        .expr = s,
        .flags = .{},
        .id = null,
    };
}

/// Format a pattern to a string.
pub fn format(self: *const Pattern, writer: *std.Io.Writer) !void {
    if (self.id) |id| {
        try writer.print("{d}:/{s}/{f}", .{ id, self.expr, self.flags });
    } else if (self.flags.value() > 0) {
        try writer.print("/{s}/{f}", .{ self.expr, self.flags });
    } else {
        try writer.print("{s}", .{self.expr});
    }
}

/// A type containing information related to an expression that is returned by `expre_info`.
pub const ExprInfo = struct {
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
};

/// Utility function providing information about a regular expression.
pub fn expr_info(self: *const Pattern) !ExprInfo {
    const info: ?*hs.hs_expr_info_t = null;
    const err: ?*hs.hs_compile_error_t = null;

    const res = hs.hs_expression_info(self.expr.ptr, self.flags.value(), info, err);
    if (err) |ce| {
        defer check(hs.hs_free_compile_error(ce)) catch |e| {
            std.log.err("free compile error: {s}", .{@errorName(e)});
        };

        std.log.warn("compile expression `{}` failed, {s}", .{ self.*, ce.message });
    }

    try check(res);

    return ExprInfo{
        .min_width = info.min_width,
        .max_width = if (info.max_width == hs.UINT_MAX) null else info.max_width,
        .unordered_matches = info.unordered_matches != 0,
        .matches_at_eod = info.matches_at_eod != 0,
        .matches_only_at_eod = info.matches_only_at_eod != 0,
    };
}

test init {
    try std.testing.expectEqualDeep(Pattern{
        .expr = "test",
    }, Pattern.init("test", .{}));

    try std.testing.expectEqualDeep(Pattern{
        .expr = "test",
        .flags = .{ .dot_all = true },
    }, Pattern.init("test", .{ .dot_all = true }));
}

test parse {
    try std.testing.expectEqualDeep(Pattern.init("test", .{}), try Pattern.parse("test"));
    try std.testing.expectEqualDeep(Pattern.init("test", .{}), try Pattern.parse("/test/"));

    try std.testing.expectEqualDeep(Pattern.init("test", .{ .dot_all = true }), try Pattern.parse("/test/s"));

    try std.testing.expectEqualDeep(Pattern{ .expr = "test", .flags = .{ .dot_all = true }, .id = 1 }, try Pattern.parse("1:/test/s"));
    try std.testing.expectEqualDeep(Pattern.init(":/test/", .{}), try Pattern.parse(":/test/"));
    try std.testing.expectEqualDeep(Pattern.init(":/test", .{}), try Pattern.parse(":/test"));
    try std.testing.expectEqualDeep(Pattern.init("1:/test", .{}), try Pattern.parse("1:/test"));
}

test format {
    try std.testing.expectFmt("test", "{f}", .{Pattern.init("test", .{})});
    try std.testing.expectFmt("/test/s", "{f}", .{Pattern.init("test", .{ .dot_all = true })});
    try std.testing.expectFmt("1:/test/s", "{f}", .{Pattern{ .expr = "test", .id = 1, .flags = .{ .dot_all = true } }});
    try std.testing.expectFmt("1:/test/", "{f}", .{Pattern{ .expr = "test", .id = 1 }});
}
