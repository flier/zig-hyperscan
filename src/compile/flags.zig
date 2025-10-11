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
        if (std.mem.indexOfNone(u8, s, allChars)) |_| {
            return error.Invalid;
        }

        return .{
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

    /// Format the flags to a string.
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

    /// Get the value of the flags.
    pub inline fn value(self: Flags) u32 {
        return @bitCast(self);
    }

    // ===== Unit Tests =====

    test "default flags" {
        const flags = Flags{};
        try std.testing.expect(!flags.caseless);
        try std.testing.expect(!flags.dot_all);
        try std.testing.expect(!flags.multiline);
        try std.testing.expect(!flags.single_match);
        try std.testing.expect(!flags.allow_empty);
        try std.testing.expect(!flags.utf8);
        try std.testing.expect(!flags.ucp);
        try std.testing.expect(!flags.prefilter);
        try std.testing.expect(!flags.som_leftmost);
        try std.testing.expect(!flags.combination);
        try std.testing.expect(!flags.quiet);
        try std.testing.expectEqual(@as(u32, 0), flags.value());
    }

    test "individual flags - caseless" {
        const flags = try parse("i");
        try std.testing.expect(flags.caseless);
        try std.testing.expect(!flags.dot_all);
        try std.testing.expectEqual(@as(u32, 1), flags.value());
    }

    test "individual flags - dot_all" {
        const flags = try parse("s");
        try std.testing.expect(!flags.caseless);
        try std.testing.expect(flags.dot_all);
        try std.testing.expectEqual(@as(u32, 2), flags.value());
    }

    test "individual flags - multiline" {
        const flags = try parse("m");
        try std.testing.expect(!flags.caseless);
        try std.testing.expect(flags.multiline);
        try std.testing.expectEqual(@as(u32, 4), flags.value());
    }

    test "individual flags - single_match" {
        const flags = try parse("H");
        try std.testing.expect(!flags.caseless);
        try std.testing.expect(flags.single_match);
        try std.testing.expectEqual(@as(u32, 8), flags.value());
    }

    test "individual flags - allow_empty" {
        const flags = try parse("V");
        try std.testing.expect(!flags.caseless);
        try std.testing.expect(flags.allow_empty);
        try std.testing.expectEqual(@as(u32, 16), flags.value());
    }

    test "individual flags - utf8" {
        const flags = try parse("8");
        try std.testing.expect(!flags.caseless);
        try std.testing.expect(flags.utf8);
        try std.testing.expectEqual(@as(u32, 32), flags.value());
    }

    test "individual flags - ucp" {
        const flags = try parse("W");
        try std.testing.expect(!flags.caseless);
        try std.testing.expect(flags.ucp);
        try std.testing.expectEqual(@as(u32, 64), flags.value());
    }

    test "individual flags - prefilter" {
        const flags = try parse("P");
        try std.testing.expect(!flags.caseless);
        try std.testing.expect(flags.prefilter);
        try std.testing.expectEqual(@as(u32, 128), flags.value());
    }

    test "individual flags - som_leftmost" {
        const flags = try parse("L");
        try std.testing.expect(!flags.caseless);
        try std.testing.expect(flags.som_leftmost);
        try std.testing.expectEqual(@as(u32, 256), flags.value());
    }

    test "individual flags - combination" {
        const flags = try parse("C");
        try std.testing.expect(!flags.caseless);
        try std.testing.expect(flags.combination);
        try std.testing.expectEqual(@as(u32, 512), flags.value());
    }

    test "individual flags - quiet" {
        const flags = try parse("Q");
        try std.testing.expect(!flags.caseless);
        try std.testing.expect(flags.quiet);
        try std.testing.expectEqual(@as(u32, 1024), flags.value());
    }

    test "flag combinations - two flags" {
        const flags = try parse("is");
        try std.testing.expect(flags.caseless);
        try std.testing.expect(flags.dot_all);
        try std.testing.expect(!flags.multiline);
        try std.testing.expectEqual(@as(u32, 3), flags.value());
    }

    test "flag combinations - three flags" {
        const flags = try parse("ism");
        try std.testing.expect(flags.caseless);
        try std.testing.expect(flags.dot_all);
        try std.testing.expect(flags.multiline);
        try std.testing.expectEqual(@as(u32, 7), flags.value());
    }

    test "flag combinations - all flags" {
        const flags = try parse(allChars);
        try std.testing.expectEqualDeep(allFlags, flags);
        try std.testing.expectEqual(@as(u32, 2047), flags.value());
    }

    test "flag combinations - mixed order" {
        const flags = try parse("Qis");
        try std.testing.expect(flags.caseless);
        try std.testing.expect(flags.dot_all);
        try std.testing.expect(flags.quiet);
        try std.testing.expectEqual(@as(u32, 1027), flags.value());
    }

    test "flag combinations - duplicates" {
        const flags = try parse("iis");
        try std.testing.expect(flags.caseless);
        try std.testing.expect(flags.dot_all);
        try std.testing.expectEqual(@as(u32, 3), flags.value());
    }

    test "parse empty string" {
        const flags = try parse("");
        try std.testing.expectEqualDeep(Flags{}, flags);
        try std.testing.expectEqual(@as(u32, 0), flags.value());
    }

    test "parse invalid characters" {
        try std.testing.expectError(error.Invalid, parse("x"));
        try std.testing.expectError(error.Invalid, parse("abc"));
        try std.testing.expectError(error.Invalid, parse("iX"));
        try std.testing.expectError(error.Invalid, parse("123"));
        try std.testing.expectError(error.Invalid, parse("!@#"));
    }

    test "parse with spaces" {
        try std.testing.expectError(error.Invalid, parse(" i"));
        try std.testing.expectError(error.Invalid, parse("i "));
        try std.testing.expectError(error.Invalid, parse(" i "));
    }

    test "parse with newlines" {
        try std.testing.expectError(error.Invalid, parse("i\n"));
        try std.testing.expectError(error.Invalid, parse("\ni"));
        try std.testing.expectError(error.Invalid, parse("i\rs"));
    }

    test "format empty flags" {
        try std.testing.expectFmt("", "{f}", .{Flags{}});
    }

    test "format single flags" {
        try std.testing.expectFmt("i", "{f}", .{Flags{ .caseless = true }});
        try std.testing.expectFmt("s", "{f}", .{Flags{ .dot_all = true }});
        try std.testing.expectFmt("m", "{f}", .{Flags{ .multiline = true }});
        try std.testing.expectFmt("H", "{f}", .{Flags{ .single_match = true }});
        try std.testing.expectFmt("V", "{f}", .{Flags{ .allow_empty = true }});
        try std.testing.expectFmt("8", "{f}", .{Flags{ .utf8 = true }});
        try std.testing.expectFmt("W", "{f}", .{Flags{ .ucp = true }});
        try std.testing.expectFmt("P", "{f}", .{Flags{ .prefilter = true }});
        try std.testing.expectFmt("L", "{f}", .{Flags{ .som_leftmost = true }});
        try std.testing.expectFmt("C", "{f}", .{Flags{ .combination = true }});
        try std.testing.expectFmt("Q", "{f}", .{Flags{ .quiet = true }});
    }

    test "format multiple flags" {
        try std.testing.expectFmt("is", "{f}", .{Flags{ .caseless = true, .dot_all = true }});
        try std.testing.expectFmt("ism", "{f}", .{Flags{ .caseless = true, .dot_all = true, .multiline = true }});
        try std.testing.expectFmt(allChars, "{f}", .{allFlags});
    }

    test "format preserves order" {
        const flags = Flags{ .quiet = true, .caseless = true, .dot_all = true };
        try std.testing.expectFmt("isQ", "{f}", .{flags});
    }

    test "value calculations" {
        // Test individual bit positions
        try std.testing.expectEqual(@as(u32, 1), value(Flags{ .caseless = true }));
        try std.testing.expectEqual(@as(u32, 2), value(Flags{ .dot_all = true }));
        try std.testing.expectEqual(@as(u32, 4), value(Flags{ .multiline = true }));
        try std.testing.expectEqual(@as(u32, 8), value(Flags{ .single_match = true }));
        try std.testing.expectEqual(@as(u32, 16), value(Flags{ .allow_empty = true }));
        try std.testing.expectEqual(@as(u32, 32), value(Flags{ .utf8 = true }));
        try std.testing.expectEqual(@as(u32, 64), value(Flags{ .ucp = true }));
        try std.testing.expectEqual(@as(u32, 128), value(Flags{ .prefilter = true }));
        try std.testing.expectEqual(@as(u32, 256), value(Flags{ .som_leftmost = true }));
        try std.testing.expectEqual(@as(u32, 512), value(Flags{ .combination = true }));
        try std.testing.expectEqual(@as(u32, 1024), value(Flags{ .quiet = true }));
    }

    test "value combinations" {
        // Test various combinations
        try std.testing.expectEqual(@as(u32, 3), value(Flags{ .caseless = true, .dot_all = true }));
        try std.testing.expectEqual(@as(u32, 7), value(Flags{ .caseless = true, .dot_all = true, .multiline = true }));
        try std.testing.expectEqual(@as(u32, 1027), value(Flags{ .caseless = true, .dot_all = true, .quiet = true }));
        try std.testing.expectEqual(@as(u32, 2047), value(allFlags));
    }

    test "round trip - parse then format" {
        const test_cases = [_][]const u8{
            "",
            "i",
            "s",
            "m",
            "H",
            "V",
            "8",
            "W",
            "P",
            "L",
            "C",
            "Q",
            "is",
            "ism",
            "HV8",
            "WPLCQ",
            allChars,
        };

        for (test_cases) |input| {
            const flags = try parse(input);
            const output = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{flags});
            defer std.testing.allocator.free(output);

            // Sort both strings to compare regardless of order
            const sorted_input = try sortString(std.testing.allocator, input);
            defer std.testing.allocator.free(sorted_input);
            const sorted_output = try sortString(std.testing.allocator, output);
            defer std.testing.allocator.free(sorted_output);

            try std.testing.expectEqualStrings(sorted_input, sorted_output);
        }
    }

    test "round trip - format then parse" {
        const test_flags = [_]Flags{
            Flags{},
            Flags{ .caseless = true },
            Flags{ .dot_all = true },
            Flags{ .multiline = true },
            Flags{ .single_match = true },
            Flags{ .allow_empty = true },
            Flags{ .utf8 = true },
            Flags{ .ucp = true },
            Flags{ .prefilter = true },
            Flags{ .som_leftmost = true },
            Flags{ .combination = true },
            Flags{ .quiet = true },
            Flags{ .caseless = true, .dot_all = true },
            Flags{ .caseless = true, .dot_all = true, .multiline = true },
            allFlags,
        };

        for (test_flags) |input_flags| {
            const formatted = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{input_flags});
            defer std.testing.allocator.free(formatted);
            const parsed = try parse(formatted);
            try std.testing.expectEqualDeep(input_flags, parsed);
        }
    }

    test "bit manipulation" {
        // Test that the packed struct correctly maps to bit positions
        const flags = Flags{ .caseless = true, .quiet = true };
        const flag_value = flags.value();

        // Check individual bits
        try std.testing.expect((flag_value & 1) != 0); // caseless
        try std.testing.expect((flag_value & 1024) != 0); // quiet
        try std.testing.expect((flag_value & 2) == 0); // dot_all should be 0
    }

    test "reserved bits" {
        // Test that reserved bits are always 0
        const flags = allFlags;
        const flag_value = flags.value();

        // Reserved bits are the upper 21 bits (bits 11-31)
        const reserved_mask = 0xFFF80000;
        try std.testing.expectEqual(@as(u32, 0), flag_value & reserved_mask);
    }

    // Helper function to sort a string for comparison
    fn sortString(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        const sorted = try allocator.dupe(u8, input);
        std.mem.sort(u8, sorted, {}, comptime std.sort.asc(u8));
        return sorted;
    }
};

const allChars = "ismHV8WPLCQ";

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
