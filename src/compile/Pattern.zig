//! A pattern with basic regular expression.

const std = @import("std");

const Flags = @import("flags.zig").Flags;
const ExprExt = @import("ExprExt.zig");
const ExprInfo = @import("ExprInfo.zig");

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
///
/// Creates a new pattern with the given regular expression string and compile flags.
/// The pattern can be used for compilation into a Hyperscan database.
///
/// ## Arguments
/// - `expr`: The regular expression string to compile
/// - `flags`: Compile flags that modify the behavior of the expression
///
/// ## Returns
/// A new `Pattern` instance with the specified expression and flags.
///
/// ## Example
/// ```zig
/// const pattern = Pattern.init("hello.*world", .{ .caseless = true });
/// ```
pub fn init(expr: []const u8, flags: Flags) Pattern {
    return .{
        .expr = expr,
        .flags = flags,
    };
}

/// Create a pattern with additional parameters.
///
/// Creates a new pattern based on the current pattern but with additional expression
/// parameters such as offset constraints, length requirements, or edit distance limits.
///
/// ## Arguments
/// - `self`: The source pattern to extend
/// - `ext`: Additional expression parameters to apply
///
/// ## Returns
/// A new `Pattern` instance with the same expression, flags, and ID as the source,
/// but with the additional parameters applied.
///
/// ## Example
/// ```zig
/// const base_pattern = Pattern.init("test", .{});
/// const extended_pattern = base_pattern.withExt(.{
///     .min_offset = 10,
///     .max_offset = 100,
///     .min_length = 5,
/// });
/// ```
pub fn withExt(self: *const Pattern, ext: ExprExt) Pattern {
    return .{
        .expr = self.expr,
        .flags = self.flags,
        .id = self.id,
        .ext = ext,
    };
}

/// Parse a pattern from a string.
///
/// Parses a pattern string that may include flags and optional ID in various formats:
/// - Simple: `"expression"` - just the regex expression
/// - With flags: `"/expression/flags"` - expression with compile flags
/// - With ID and flags: `"id:/expression/flags"` - pattern with ID and flags
///
/// Supported flag characters:
/// - `i`: Case-insensitive matching
/// - `s`: Dot matches newline
/// - `m`: Multiline mode
/// - `H`: Single match only
/// - `V`: Allow empty matches
/// - `8`: UTF-8 mode
/// - `W`: Unicode property support
/// - `P`: Prefiltering mode
/// - `L`: Leftmost start of match
/// - `C`: Logical combination
/// - `Q`: Quiet mode (no match reporting)
///
/// ## Arguments
/// - `s`: The pattern string to parse
///
/// ## Returns
/// A `Pattern` instance parsed from the string, or an error if the format is invalid.
///
/// # Errors
/// - `error.Invalid`: If the pattern string contains invalid flag characters
///
/// ## Example
/// ```zig
/// const pattern1 = try Pattern.parse("hello");
/// const pattern2 = try Pattern.parse("/hello/i");
/// const pattern3 = try Pattern.parse("42:/hello.*world/ism");
/// ```
pub fn parse(s: []const u8) !Pattern {
    if (std.mem.indexOf(u8, s, ":/")) |start| {
        if (start > 0 and std.mem.indexOfNone(u8, s[0..start], "0123456789") == null) {
            if (std.mem.lastIndexOfScalar(u8, s, '/')) |end| {
                if (start + 1 < end) {
                    return .{
                        .expr = s[start + 2 .. end],
                        .flags = try .parse(s[end + 1 ..]),
                        .id = try std.fmt.parseInt(u32, s[0..start], 10),
                    };
                }
            }
        }
    }

    if (std.mem.startsWith(u8, s, "/") & std.mem.containsAtLeastScalar(u8, s, 2, '/')) {
        if (std.mem.lastIndexOfScalar(u8, s, '/')) |end| {
            return .{
                .expr = s[1..end],
                .flags = try .parse(s[end + 1 ..]),
                .id = null,
            };
        }
    }

    return .{
        .expr = s,
    };
}

/// Utility function providing information about a regular expression.
///
/// Analyzes the pattern and returns detailed information about its properties,
/// including minimum/maximum width, match behavior, and other characteristics.
///
/// ## Arguments
/// - `self`: The pattern to analyze
///
/// ## Returns
/// An `ExprInfo` struct containing analysis results, or an error if the pattern is invalid.
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
pub fn exprInfo(self: *const Pattern) !ExprInfo {
    return .analysis(self.expr, self.flags, self.ext);
}

/// Format a pattern to a string.
///
/// Formats the pattern as a string representation that can be parsed back using `parse()`.
/// The format includes the expression, flags, and optional ID in a standardized format.
///
/// ## Arguments
/// - `self`: The pattern to format
/// - `writer`: The writer to output the formatted string to
///
/// ## Returns
/// An error if writing fails.
///
/// ## Example
/// ```zig
/// const pattern = try Pattern.parse("42:/hello.*world/ism");
///
/// var buffer = std.ArrayList(u8).init(allocator);
/// defer buffer.deinit();
///
/// try pattern.format(buffer.writer());
///
/// std.log.info("Formatted pattern: {s}", .{buffer.items});
/// ```
pub fn format(self: *const Pattern, writer: *std.Io.Writer) !void {
    if (self.id) |id| {
        try writer.print("{d}:/{s}/{f}", .{ id, self.expr, self.flags });
    } else if (self.flags.value() > 0) {
        try writer.print("/{s}/{f}", .{ self.expr, self.flags });
    } else {
        try writer.print("{s}", .{self.expr});
    }
}

// Unit tests

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

// Additional comprehensive tests

test "init with various flags" {
    const pattern1: Pattern = .init("test", .{ .caseless = true });
    try std.testing.expectEqualStrings("test", pattern1.expr);
    try std.testing.expect(pattern1.flags.caseless);
    try std.testing.expect(!pattern1.flags.dot_all);
    try std.testing.expect(pattern1.id == null);
    try std.testing.expect(pattern1.ext == null);

    const pattern2: Pattern = .init("regex", .{ .multiline = true, .utf8 = true });
    try std.testing.expectEqualStrings("regex", pattern2.expr);
    try std.testing.expect(pattern2.flags.multiline);
    try std.testing.expect(pattern2.flags.utf8);
    try std.testing.expect(!pattern2.flags.caseless);
}

test withExt {
    const pattern_with_ext = Pattern.init("test", .{
        .caseless = true,
    }).withExt(.{
        .min_offset = 10,
        .max_offset = 100,
    });

    try std.testing.expectEqualStrings("test", pattern_with_ext.expr);
    try std.testing.expect(pattern_with_ext.flags.caseless);
    try std.testing.expect(pattern_with_ext.id == null);
    try std.testing.expect(pattern_with_ext.ext != null);
    try std.testing.expectEqual(@as(u64, 10), pattern_with_ext.ext.?.min_offset);
    try std.testing.expectEqual(@as(u64, 100), pattern_with_ext.ext.?.max_offset);
}

test "withExt preserves id" {
    const base_pattern = Pattern{ .expr = "test", .id = 42, .flags = .{} };
    const ext = ExprExt{ .min_length = 5 };
    const pattern_with_ext = base_pattern.withExt(ext);

    try std.testing.expectEqualStrings("test", pattern_with_ext.expr);
    try std.testing.expectEqual(42, pattern_with_ext.id.?);
    try std.testing.expect(pattern_with_ext.ext != null);
    try std.testing.expectEqual(@as(u64, 5), pattern_with_ext.ext.?.min_length);
}

test "parse edge cases - empty strings" {
    try std.testing.expectEqualDeep(Pattern.init("", .{}), try Pattern.parse(""));
    try std.testing.expectEqualDeep(Pattern.init("", .{}), try Pattern.parse("//"));
    try std.testing.expectEqualDeep(Pattern{ .expr = "", .id = 0 }, try Pattern.parse("0://"));
}

test "parse edge cases - malformed patterns" {
    // Invalid ID format
    try std.testing.expectEqualDeep(Pattern.init("abc:/test/", .{}), try Pattern.parse("abc:/test/"));
    try std.testing.expectEqualDeep(Pattern.init(":/test/", .{}), try Pattern.parse(":/test/"));

    // Missing closing slash
    try std.testing.expectEqualDeep(Pattern.init("/test", .{}), try Pattern.parse("/test"));
    try std.testing.expectEqualDeep(Pattern.init("1:/test", .{}), try Pattern.parse("1:/test"));

    // Only slashes
    try std.testing.expectEqualDeep(Pattern.init("", .{}), try Pattern.parse("//"));
    try std.testing.expectEqualDeep(Pattern.init("/", .{}), try Pattern.parse("///"));
}

test "parse with complex flags" {
    const pattern: Pattern = try .parse("/test/ismHV8WPLCQ");
    try std.testing.expectEqualStrings("test", pattern.expr);
    try std.testing.expect(pattern.flags.caseless);
    try std.testing.expect(pattern.flags.dot_all);
    try std.testing.expect(pattern.flags.multiline);
    try std.testing.expect(pattern.flags.single_match);
    try std.testing.expect(pattern.flags.allow_empty);
    try std.testing.expect(pattern.flags.utf8);
    try std.testing.expect(pattern.flags.ucp);
    try std.testing.expect(pattern.flags.prefilter);
    try std.testing.expect(pattern.flags.som_leftmost);
    try std.testing.expect(pattern.flags.combination);
    try std.testing.expect(pattern.flags.quiet);
}

test "parse with ID and complex flags" {
    const pattern: Pattern = try .parse("42:/complex.*pattern/ism");
    try std.testing.expectEqualStrings("complex.*pattern", pattern.expr);
    try std.testing.expectEqual(42, pattern.id.?);
    try std.testing.expect(pattern.flags.caseless);
    try std.testing.expect(pattern.flags.dot_all);
    try std.testing.expect(pattern.flags.multiline);
    try std.testing.expect(!pattern.flags.single_match);
}

test "parse invalid flag characters" {
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/invalid"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/ix"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/123"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/!@#"));
}

test "format with various flag combinations" {
    // Test all individual flags
    try std.testing.expectFmt("/test/i", "{f}", .{Pattern.init("test", .{ .caseless = true })});
    try std.testing.expectFmt("/test/s", "{f}", .{Pattern.init("test", .{ .dot_all = true })});
    try std.testing.expectFmt("/test/m", "{f}", .{Pattern.init("test", .{ .multiline = true })});
    try std.testing.expectFmt("/test/H", "{f}", .{Pattern.init("test", .{ .single_match = true })});
    try std.testing.expectFmt("/test/V", "{f}", .{Pattern.init("test", .{ .allow_empty = true })});
    try std.testing.expectFmt("/test/8", "{f}", .{Pattern.init("test", .{ .utf8 = true })});
    try std.testing.expectFmt("/test/W", "{f}", .{Pattern.init("test", .{ .ucp = true })});
    try std.testing.expectFmt("/test/P", "{f}", .{Pattern.init("test", .{ .prefilter = true })});
    try std.testing.expectFmt("/test/L", "{f}", .{Pattern.init("test", .{ .som_leftmost = true })});
    try std.testing.expectFmt("/test/C", "{f}", .{Pattern.init("test", .{ .combination = true })});
    try std.testing.expectFmt("/test/Q", "{f}", .{Pattern.init("test", .{ .quiet = true })});
}

test "format with multiple flags" {
    try std.testing.expectFmt("/test/is", "{f}", .{Pattern.init("test", .{ .caseless = true, .dot_all = true })});
    try std.testing.expectFmt("/test/ism", "{f}", .{Pattern.init("test", .{ .caseless = true, .dot_all = true, .multiline = true })});
    try std.testing.expectFmt("/test/HV8", "{f}", .{Pattern.init("test", .{ .single_match = true, .allow_empty = true, .utf8 = true })});
}

test "format with ID and flags" {
    try std.testing.expectFmt("0:/test/", "{f}", .{Pattern{ .expr = "test", .id = 0 }});
    try std.testing.expectFmt("999:/test/is", "{f}", .{Pattern{ .expr = "test", .id = 999, .flags = .{ .caseless = true, .dot_all = true } }});
    try std.testing.expectFmt("42:/complex.*pattern/ismHV8WPLCQ", "{f}", .{Pattern{ .expr = "complex.*pattern", .id = 42, .flags = .{ .caseless = true, .dot_all = true, .multiline = true, .single_match = true, .allow_empty = true, .utf8 = true, .ucp = true, .prefilter = true, .som_leftmost = true, .combination = true, .quiet = true } }});
}

test "format empty expression" {
    try std.testing.expectFmt("", "{f}", .{Pattern.init("", .{})});
    try std.testing.expectFmt("", "{f}", .{Pattern.init("", .{})});
    try std.testing.expectFmt("0://", "{f}", .{Pattern{ .expr = "", .id = 0 }});
    try std.testing.expectFmt("//is", "{f}", .{Pattern.init("", .{ .caseless = true, .dot_all = true })});
}

test "round trip - parse then format" {
    const test_cases = [_][]const u8{
        "simple",
        "/simple/",
        "/simple/is",
        "42:/complex/ismHV8WPLCQ",
        "0://",
        "999:/empty//",
    };

    for (test_cases) |input| {
        const parsed: Pattern = try .parse(input);
        const formatted = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{parsed});
        defer std.testing.allocator.free(formatted);

        // Parse the formatted result and compare
        const reparsed: Pattern = try .parse(formatted);
        try std.testing.expectEqualDeep(parsed, reparsed);
    }
}

test "round trip - format then parse" {
    const test_patterns = [_]Pattern{
        .init("test", .{}),
        .init("test", .{ .caseless = true }),
        .init("test", .{ .dot_all = true, .multiline = true }),
        .{ .expr = "test", .id = 42 },
        .{ .expr = "test", .id = 0, .flags = .{ .utf8 = true } },
        .{ .expr = "complex.*pattern", .id = 999, .flags = .{ .caseless = true, .dot_all = true, .multiline = true } },
    };

    for (test_patterns) |input_pattern| {
        const formatted = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{input_pattern});
        defer std.testing.allocator.free(formatted);
        const parsed: Pattern = try .parse(formatted);
        try std.testing.expectEqualDeep(input_pattern, parsed);
    }
}

test "exprInfo with simple patterns" {
    const pattern1: Pattern = .init("abc", .{});
    const info1 = try pattern1.exprInfo();
    try std.testing.expectEqual(3, info1.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 3 }, info1.max_width);
    try std.testing.expect(!info1.unordered_matches);
    try std.testing.expect(!info1.matches_at_eod);
    try std.testing.expect(!info1.matches_only_at_eod);

    const pattern2: Pattern = .init("test", .{ .caseless = true });
    const info2 = try pattern2.exprInfo();
    try std.testing.expectEqual(4, info2.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 4 }, info2.max_width);
}

test "exprInfo with complex patterns" {
    const pattern1: Pattern = .init("foo\\d+", .{});
    const info1 = try pattern1.exprInfo();
    try std.testing.expectEqual(4, info1.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength.unbounded, info1.max_width);

    const pattern2: Pattern = .init(".*", .{});
    const info2 = try pattern2.exprInfo();
    try std.testing.expectEqual(0, info2.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength.unbounded, info2.max_width);
}

test "exprInfo with flags" {
    const pattern1: Pattern = .init("test", .{ .multiline = true, .utf8 = true });
    const info1 = try pattern1.exprInfo();
    try std.testing.expectEqual(4, info1.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 4 }, info1.max_width);

    const pattern2: Pattern = .init("^test$", .{ .multiline = true });
    const info2 = try pattern2.exprInfo();
    try std.testing.expectEqual(4, info2.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 4 }, info2.max_width);
}

test "exprInfo with extensions" {
    const ext = ExprExt{ .min_offset = 10, .max_offset = 100 };
    const pattern = Pattern.init("test", .{}).withExt(ext);
    const info = try pattern.exprInfo();
    try std.testing.expectEqual(4, info.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 4 }, info.max_width);
}

test "exprInfo edge cases" {
    // Empty pattern
    const empty_pattern: Pattern = .init("", .{});
    const empty_info = try empty_pattern.exprInfo();
    try std.testing.expectEqual(0, empty_info.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 0 }, empty_info.max_width);

    // Single character
    const single_pattern: Pattern = .init("a", .{});
    const single_info = try single_pattern.exprInfo();
    try std.testing.expectEqual(1, single_info.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 1 }, single_info.max_width);
}

test "exprInfo with anchors" {
    const pattern1: Pattern = .init("^test$", .{});
    const info1 = try pattern1.exprInfo();
    try std.testing.expectEqual(4, info1.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 4 }, info1.max_width);

    const pattern2: Pattern = .init("test$", .{});
    const info2 = try pattern2.exprInfo();
    try std.testing.expectEqual(4, info2.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 4 }, info2.max_width);
}

test "exprInfo with quantifiers" {
    const pattern1: Pattern = .init("a+", .{});
    const info1 = try pattern1.exprInfo();
    try std.testing.expectEqual(1, info1.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength.unbounded, info1.max_width);

    const pattern2: Pattern = .init("a{3,5}", .{});
    const info2 = try pattern2.exprInfo();
    try std.testing.expectEqual(3, info2.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 5 }, info2.max_width);

    const pattern3: Pattern = .init("a{3,}", .{});
    const info3 = try pattern3.exprInfo();
    try std.testing.expectEqual(3, info3.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength.unbounded, info3.max_width);
}

test "exprInfo with alternation" {
    const pattern1: Pattern = .init("abc|def", .{});
    const info1 = try pattern1.exprInfo();
    try std.testing.expectEqual(3, info1.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 3 }, info1.max_width);

    const pattern2: Pattern = .init("a|bc", .{});
    const info2 = try pattern2.exprInfo();
    try std.testing.expectEqual(1, info2.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 2 }, info2.max_width);
}

test "exprInfo with character classes" {
    const pattern1: Pattern = .init("[abc]", .{});
    const info1 = try pattern1.exprInfo();
    try std.testing.expectEqual(1, info1.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength{ .value = 1 }, info1.max_width);

    const pattern2: Pattern = .init("[a-z]+", .{});
    const info2 = try pattern2.exprInfo();
    try std.testing.expectEqual(1, info2.min_width);
    try std.testing.expectEqual(ExprInfo.MaxLength.unbounded, info2.max_width);
}

test "exprInfo error handling" {
    // Test with invalid regex pattern
    const invalid_pattern: Pattern = .init("[", .{});
    try std.testing.expectError(error.CompileError, invalid_pattern.exprInfo());

    const invalid_pattern2: Pattern = .init("(unclosed", .{});
    try std.testing.expectError(error.CompileError, invalid_pattern2.exprInfo());
}

test "parse error handling" {
    // Test invalid flag characters
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/invalid"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/xyz"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/123"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/!@#"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/ "));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/\n"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/\t"));
}

test "parse with whitespace and special characters" {
    // Test that whitespace in flags is invalid
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/i s"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/ i"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/i\ns"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/i\ts"));

    // Test that special characters in flags are invalid
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/i,s"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/i;s"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/i:s"));
    try std.testing.expectError(error.Invalid, Pattern.parse("/test/i.s"));
}

test "parse with very long patterns" {
    // Test with very long expression
    const long_expr = try std.testing.allocator.alloc(u8, 10000);
    defer std.testing.allocator.free(long_expr);
    @memset(long_expr, 'a');

    const long_pattern: Pattern = try .parse(long_expr);
    try std.testing.expectEqualStrings(long_expr, long_pattern.expr);
    try std.testing.expectEqual(0, long_pattern.flags.value());
    try std.testing.expect(long_pattern.id == null);
}

test "parse with unicode characters" {
    const unicode_pattern: Pattern = try .parse("/测试/is");
    try std.testing.expectEqualStrings("测试", unicode_pattern.expr);
    try std.testing.expect(unicode_pattern.flags.caseless);
    try std.testing.expect(unicode_pattern.flags.dot_all);

    const unicode_with_id: Pattern = try .parse("42:/测试/is");
    try std.testing.expectEqualStrings("测试", unicode_with_id.expr);
    try std.testing.expectEqual(42, unicode_with_id.id.?);
    try std.testing.expect(unicode_with_id.flags.caseless);
    try std.testing.expect(unicode_with_id.flags.dot_all);
}

test "parse with special regex characters" {
    const special_chars: Pattern = try .parse("/[a-z]+\\d*/is");
    try std.testing.expectEqualStrings("[a-z]+\\d*", special_chars.expr);
    try std.testing.expect(special_chars.flags.caseless);
    try std.testing.expect(special_chars.flags.dot_all);

    const anchors: Pattern = try .parse("/^test$/m");
    try std.testing.expectEqualStrings("^test$", anchors.expr);
    try std.testing.expect(anchors.flags.multiline);
    try std.testing.expect(!anchors.flags.caseless);
}

test "parse with empty flags" {
    const empty_flags: Pattern = try .parse("/test/");
    try std.testing.expectEqualStrings("test", empty_flags.expr);
    try std.testing.expectEqual(0, empty_flags.flags.value());

    const empty_flags_with_id: Pattern = try .parse("42:/test/");
    try std.testing.expectEqualStrings("test", empty_flags_with_id.expr);
    try std.testing.expectEqual(42, empty_flags_with_id.id.?);
    try std.testing.expectEqual(0, empty_flags_with_id.flags.value());
}

test "parse with maximum ID values" {
    const max_id: Pattern = try .parse("4294967295:/test/");
    try std.testing.expectEqualStrings("test", max_id.expr);
    try std.testing.expectEqual(4294967295, max_id.id.?);

    const zero_id: Pattern = try .parse("0:/test/");
    try std.testing.expectEqualStrings("test", zero_id.expr);
    try std.testing.expectEqual(0, zero_id.id.?);
}

test "format with special characters in expression" {
    const special_pattern: Pattern = .init("[a-z]+\\d*", .{ .caseless = true });
    try std.testing.expectFmt("/[a-z]+\\d*/i", "{f}", .{special_pattern});

    const unicode_pattern: Pattern = .init("测试", .{ .dot_all = true });
    try std.testing.expectFmt("/测试/s", "{f}", .{unicode_pattern});

    const anchors_pattern: Pattern = .init("^test$", .{ .multiline = true });
    try std.testing.expectFmt("/^test$/m", "{f}", .{anchors_pattern});
}

test "format with very long expressions" {
    const long_expr = try std.testing.allocator.alloc(u8, 1000);
    defer std.testing.allocator.free(long_expr);
    @memset(long_expr, 'a');

    const long_pattern: Pattern = .init(long_expr, .{ .caseless = true });
    const formatted = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{long_pattern});
    defer std.testing.allocator.free(formatted);

    try std.testing.expect(std.mem.startsWith(u8, formatted, "/"));
    try std.testing.expect(std.mem.endsWith(u8, formatted, "/i"));
    try std.testing.expect(std.mem.indexOf(u8, formatted, long_expr) != null);
}

test "format with all possible flag combinations" {
    const all_flags = Flags{
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

    const pattern: Pattern = .{ .expr = "test", .id = 42, .flags = all_flags };
    try std.testing.expectFmt("42:/test/ismHV8WPLCQ", "{f}", .{pattern});
}

test "format with null ID" {
    const pattern_with_null_id = Pattern{ .expr = "test", .id = null, .flags = .{ .caseless = true } };
    try std.testing.expectFmt("/test/i", "{f}", .{pattern_with_null_id});

    const pattern_with_zero_id = Pattern{ .expr = "test", .id = 0, .flags = .{ .caseless = true } };
    try std.testing.expectFmt("0:/test/i", "{f}", .{pattern_with_zero_id});
}

test "memory safety - no leaks" {
    // Test that pattern creation and parsing don't leak memory
    const test_cases = [_][]const u8{
        "simple",
        "/simple/is",
        "42:/complex/ismHV8WPLCQ",
        "0://",
    };

    for (test_cases) |input| {
        const parsed: Pattern = try .parse(input);
        const formatted = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{parsed});
        defer std.testing.allocator.free(formatted);

        // Verify the pattern is valid
        try std.testing.expect(parsed.expr.len >= 0);
        _ = parsed.flags.value();
    }
}

test "pattern equality and comparison" {
    const pattern1: Pattern = .init("test", .{ .caseless = true });
    const pattern2: Pattern = .init("test", .{ .caseless = true });
    const pattern3: Pattern = .init("test", .{ .dot_all = true });
    const pattern4: Pattern = .init("different", .{ .caseless = true });

    // Test that identical patterns are equal
    try std.testing.expectEqualDeep(pattern1, pattern2);

    // Test that different flags make patterns unequal
    try std.testing.expect(!std.meta.eql(pattern1, pattern3));

    // Test that different expressions make patterns unequal
    try std.testing.expect(!std.meta.eql(pattern1, pattern4));
}

test "pattern with extensions equality" {
    const base_pattern: Pattern = .init("test", .{ .caseless = true });
    const pattern1 = base_pattern.withExt(.{ .min_offset = 10, .max_offset = 100 });
    const pattern2 = base_pattern.withExt(.{ .min_offset = 10, .max_offset = 100 });
    const pattern3 = base_pattern.withExt(.{ .min_offset = 20, .max_offset = 100 });

    // Test that identical extensions make patterns equal
    try std.testing.expectEqualDeep(pattern1, pattern2);

    // Test that different extensions make patterns unequal
    try std.testing.expect(!std.meta.eql(pattern1, pattern3));
}
