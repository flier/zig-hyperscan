const std = @import("std");

/// Compile flags
pub const Flags = packed struct(u32) {
    /// Set case-insensitive matching.
    caseless: bool = false,
    /// Matching a `.` will not exclude newlines.
    dot_all: bool = false,
    /// Set multi-line anchoring.
    multiline: bool = false,
    /// Set single-match only mode.
    single_match: bool = false,
    /// Allow expressions that can match against empty buffers.
    allow_empty: bool = false,
    /// Enable UTF-8 mode for this expression.
    utf8: bool = false,
    /// Enable Unicode property support for this expression.
    ucp: bool = false,
    /// Enable prefiltering mode for this expression.
    prefilter: bool = false,
    /// Enable leftmost start of match reporting.
    som_leftmost: bool = false,
    /// Logical combination.
    combination: bool = false,
    /// Don't do any match reporting.
    quiet: bool = false,

    reserved: u21 = 0,

    pub fn parse(s: []const u8) !Flags {
        if (std.mem.indexOfNone(u8, s, allFlagsChars)) |i| {
            std.log.warn("invalid flag: {c}", .{s[i]});

            return error.InvalidFlag;
        }

        return Flags{
            .caseless = std.mem.containsAtLeastScalar(u8, s, 1, 'i'),
            .dot_all = std.mem.containsAtLeastScalar(u8, s, 1, 's'),
            .multiline = std.mem.containsAtLeastScalar(u8, s, 1, 'm'),
            .single_match = std.mem.containsAtLeastScalar(u8, s, 1, 'H'),
            .allow_empty = std.mem.containsAtLeastScalar(u8, s, 1, 'V'),
            .utf8 = std.mem.containsAtLeastScalar(u8, s, 1, '8'),
            .ucp = std.mem.containsAtLeastScalar(u8, s, 1, 'W'),
            .prefilter = std.mem.containsAtLeastScalar(u8, s, 1, 'P'),
            .som_leftmost = std.mem.containsAtLeastScalar(u8, s, 1, 'L'),
            .combination = std.mem.containsAtLeastScalar(u8, s, 1, 'C'),
            .quiet = std.mem.containsAtLeastScalar(u8, s, 1, 'Q'),
        };
    }

    /// Get the value of the flags.
    pub inline fn value(self: Flags) u32 {
        return @bitCast(self);
    }

    pub fn format(self: Flags, writer: *std.Io.Writer) !void {
        if (self.caseless) {
            try writer.printAsciiChar('i', .{});
        }
        if (self.dot_all) {
            try writer.printAsciiChar('s', .{});
        }
        if (self.multiline) {
            try writer.printAsciiChar('m', .{});
        }
        if (self.single_match) {
            try writer.printAsciiChar('H', .{});
        }
        if (self.allow_empty) {
            try writer.printAsciiChar('V', .{});
        }
        if (self.utf8) {
            try writer.printAsciiChar('8', .{});
        }
        if (self.ucp) {
            try writer.printAsciiChar('W', .{});
        }
        if (self.prefilter) {
            try writer.printAsciiChar('P', .{});
        }
        if (self.som_leftmost) {
            try writer.printAsciiChar('L', .{});
        }
        if (self.combination) {
            try writer.printAsciiChar('C', .{});
        }
        if (self.quiet) {
            try writer.printAsciiChar('Q', .{});
        }
    }

    test value {
        try std.testing.expectEqual(1, value(Flags{
            .caseless = true,
        }));

        try std.testing.expectEqual(1024, value(Flags{ .quiet = true }));

        try std.testing.expectEqual(7, value(Flags{
            .caseless = true,
            .dot_all = true,
            .multiline = true,
        }));
    }

    test parse {
        try std.testing.expectEqualDeep(Flags{}, try parse(""));
        try std.testing.expectEqualDeep(Flags{ .dot_all = true }, try parse("s"));
        try std.testing.expectEqualDeep(allFlags, try parse(allFlagsChars));
    }

    test format {
        try std.testing.expectFmt("", "{f}", .{Flags{}});
        try std.testing.expectFmt("s", "{f}", .{Flags{ .dot_all = true }});
        try std.testing.expectFmt(allFlagsChars, "{f}", .{allFlags});
    }
};

const allFlagsChars = "ismHV8WPLCQ";

const allFlags = Flags{
    .caseless = true,
    .dot_all = true,
    .multiline = true,
    .single_match = true,
    .allow_empty = true,
    .utf8 = true,
    .ucp = true,
    .prefilter = true,
    .som_leftmost = true,
    .combination = true,
    .quiet = true,
};
