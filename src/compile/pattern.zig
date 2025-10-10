//! A pattern with basic regular expression.

const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const Flags = @import("flags.zig").Flags;
const ExprExt = @import("expr_ext.zig");
const ExprInfo = @import("expr_info.zig");

const check = @import("../common.zig").check;

/// The regular expression to compile.
expr: []const u8,
/// Flags which modify the behaviour of the expression.
flags: Flags = .{},
/// The id to associate with the expression.
id: ?u32 = null,
/// The additional parameters for the expression.
ext: ?ExprExt = null,

const Pattern = @This();

/// Initialize a pattern with expression and flags.
pub fn init(expr: []const u8, flags: Flags) Pattern {
    return Pattern{
        .expr = expr,
        .flags = flags,
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

/// Create a pattern with additional parameters.
pub fn withExt(self: *const Pattern, ext: ExprExt) Pattern {
    return Pattern{
        .expr = self.expr,
        .flags = self.flags,
        .id = self.id,
        .ext = ext,
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
    };
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

/// Utility function providing information about a regular expression.
pub fn expr_info(self: *const Pattern) !ExprInfo {
    return ExprInfo.analysis(self.expr, self.flags, self.ext);
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

test format {
    try std.testing.expectFmt("test", "{f}", .{Pattern.init("test", .{})});
    try std.testing.expectFmt("/test/s", "{f}", .{Pattern.init("test", .{ .dot_all = true })});
    try std.testing.expectFmt("1:/test/s", "{f}", .{Pattern{ .expr = "test", .id = 1, .flags = .{ .dot_all = true } }});
    try std.testing.expectFmt("1:/test/", "{f}", .{Pattern{ .expr = "test", .id = 1 }});
}
