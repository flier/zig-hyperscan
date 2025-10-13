//! A regular expression matcher using Hyperscan.

const std = @import("std");

const Error = @import("error.zig").Error;
const Database = @import("Database.zig").Database;
const Pattern = @import("../compile.zig").Pattern;

const runtime = @import("../runtime.zig");

const Scratch = runtime.Scratch;
const MatchEvent = runtime.MatchEvent;

db: Database,

const Regex = @This();

/// Compiles a regular expression into a Hyperscan database.
///
/// ## Returns
/// a `Regex` handle for scanning byte slices.
///
/// ## Errors
/// - `error.CompileError` invalid pattern.
/// - `error.OutOfMemory` insufficient memory.
///
/// ## Ownership
/// call `deinit()` to release resources when done.
///
/// ## Notes
/// Scratch space is allocated lazily per-scan and freed after each scan.
///
/// ## Example
/// ```zig
/// const regex = try Regex.compile("hello");
/// defer regex.deinit();
/// ```
pub fn compile(expr: []const u8) !Regex {
    var pattern: Pattern = try .parse(expr);

    pattern.flags.som_leftmost = true;

    const db: Database = try .compile(&pattern, .{});

    return .{ .db = db };
}

/// Deinitializes a `Regex` object.
///
/// ## Effects
/// Frees the underlying Hyperscan database.
pub fn deinit(self: *const Regex) void {
    self.db.deinit();
}

/// Options for finding matches.
pub const FindOptions = struct {
    /// Whether to match the longest match.
    ///
    /// By default, the `Regex` object will match the leftmost match.
    /// This function sets the `Regex` object to match the longest match.
    ///
    /// ## Example
    /// ```zig
    /// const regex = try Regex.compile("a(|b)");
    ///
    /// regex.find("ab", .{});
    /// // => "a"
    ///
    /// regex.find(.{ .longest = true }, "ab");
    /// // => "ab"
    ///
    /// regex.find(.{ .longest = true }, "aabb");
    /// // => "aab"
    longest: bool = false,
};

/// Checks whether the regular expression matches `data` at least once.
///
/// ## Returns
/// `true` if at least one match exists; otherwise `false`.
///
/// ## Errors
/// Propagates scanning errors from Hyperscan.
pub fn match(self: *const Regex, data: []const u8) !bool {
    return try self.findIndex(data, .{}) != null;
}

/// Finds the text of the first match according to `opts`.
///
/// ## Behavior
/// With `opts.longest = true`, prefers the longest span among matches sharing the same start.
///
/// ## Returns
/// A slice into the original `data`, or `null` if no match.
///
/// ## Errors
/// Propagates scanning errors from Hyperscan.
pub fn find(self: *const Regex, data: []const u8, opts: FindOptions) !?[]const u8 {
    if (try self.findIndex(data, opts)) |span| {
        return data[span.from..span.to];
    }

    return null;
}

/// A match.
pub const Match = struct {
    /// The id of the match.
    id: u32 = 0,
    /// The start index of the match.
    from: u64,
    /// The end index of the match.
    to: u64,
};

/// Finds the start and end indices of the first match according to `opts`.
///
/// ## Behavior
/// When `opts.longest` is set, extends to the longest match beginning at the same position, and terminates early once a later-starting match is seen.
///
/// ## Returns
/// `Match{ id, from, to }` or `null` if no match.
///
/// ## Errors
/// Propagates scanning errors from Hyperscan.
pub fn findIndex(self: *const Regex, data: []const u8, opts: FindOptions) !?Match {
    const Context = struct {
        match: ?Match = null,
        longest: bool,
    };

    var context: Context = .{
        .longest = opts.longest,
    };

    const scratch = try self.db.allocScratch();
    defer scratch.deinit();

    self.db.scanBlock(data, scratch, .{
        .onEvent = struct {
            fn handler(evt: MatchEvent) !void {
                const ctx = evt.data(Context);

                if (ctx.longest) {
                    if (ctx.match) |last| {
                        if ((evt.from.? == last.from) & (evt.to > last.to)) {
                            ctx.match = .{
                                .id = evt.id,
                                .from = evt.from.?,
                                .to = evt.to,
                            };

                            return;
                        }

                        if (evt.from.? > last.from) {
                            return error.Terminate;
                        }
                    }
                }

                ctx.match = .{
                    .id = evt.id,
                    .from = evt.from.?,
                    .to = evt.to,
                };

                if (!ctx.longest) {
                    return error.Terminate;
                }
            }
        }.handler,
        .context = &context,
    }) catch |err| {
        if (err != Error.ScanTerminated) {
            return err;
        }
    };

    return context.match;
}

/// Finds all matches in `data` according to `opts`.
///
/// ## Returns
/// An owned slice of views (`[][]const u8`) into `data`, or `null` when no match.
///
/// ## Ownership
/// Caller must free the returned outer slice with `allocator.free`; inner slices alias `data` and must not be freed.
///
/// ## Errors
/// Allocation or scanning errors.
pub fn findAll(self: *const Regex, allocator: std.mem.Allocator, data: []const u8, opts: FindOptions) !?[][]const u8 {
    if (try self.findAllIndex(allocator, data, opts)) |matches| {
        defer allocator.free(matches);

        if (matches.len == 0) return null;

        var matched = try allocator.alloc([]const u8, matches.len);

        for (matches, 0..) |m, i| {
            matched[i] = data[m.from..m.to];
        }

        return matched;
    }

    return null;
}

/// Finds all match spans in `data` according to `opts`.
///
/// ## Returns
/// An owned slice of `Match` values, or `null` when no match.
///
/// ## Ownership
/// Caller must free the returned slice with `allocator.free`.
///
/// ## Errors
/// Allocation or scanning errors.
pub fn findAllIndex(self: *const Regex, allocator: std.mem.Allocator, data: []const u8, opts: FindOptions) !?[]Match {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const Context = struct {
        allocator: std.mem.Allocator,
        matches: std.ArrayList(Match),
        longest: bool,
    };

    var context: Context = .{
        .allocator = alloc,
        .matches = try .initCapacity(alloc, 4),
        .longest = opts.longest,
    };

    const scratch = try self.db.allocScratch();
    defer scratch.deinit();

    try self.db.scanBlock(data, scratch, .{
        .onEvent = struct {
            fn handler(evt: MatchEvent) !void {
                const ctx = evt.data(Context);

                if (ctx.longest) {
                    if (ctx.matches.getLastOrNull()) |last| {
                        if ((evt.from == last.from) & (evt.to > last.to)) {
                            _ = ctx.matches.pop();
                        }
                    }
                }

                ctx.matches.append(ctx.allocator, .{
                    .id = evt.id,
                    .from = evt.from.?,
                    .to = evt.to,
                }) catch return error.Terminate;
            }
        }.handler,
        .context = &context,
    });

    return if (context.matches.items.len > 0) try allocator.dupe(Match, context.matches.items) else null;
}

/// Replaces all matches in `data` with `replacement` according to `opts`.
///
/// ## Returns
/// A newly allocated string with replacements applied. If there are no matches, returns a duplicate of `data`.
///
/// ## Ownership
/// Caller must free the returned slice with the same `allocator`.
///
/// ## Errors
/// Allocation or scanning errors.
pub fn replace(self: *const Regex, allocator: std.mem.Allocator, data: []const u8, replacement: []const u8) ![]const u8 {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    if (try self.findAllIndex(alloc, data, .{ .longest = true })) |matches| {
        var replaced: std.ArrayList(u8) = try .initCapacity(alloc, data.len);

        var last: u64 = 0;

        for (matches) |m| {
            if (m.from > last) {
                try replaced.appendSlice(alloc, data[last..m.from]);
            }

            try replaced.appendSlice(alloc, replacement);

            last = m.to;
        }

        if (last < data.len) {
            try replaced.appendSlice(alloc, data[last..]);
        }

        return allocator.dupe(u8, replaced.items);
    }

    return allocator.dupe(u8, data);
}

/// A function that maps a matched slice to its replacement.
///
/// ## Contract
/// Return `null` to keep the original match; return an allocated slice to replace it.
///
/// ## Ownership
/// The caller (`replaceFn`) will free any non-null returned slice after copying its contents.
pub const ReplaceFn = fn (std.mem.Allocator, []const u8) ?[]const u8;

/// Replaces matches by invoking `f` for each match and splicing the result.
///
/// ## Callback
/// `f(match)` may return `null` (keep original) or an allocated slice (used as replacement).
///
/// ## Ownership
/// Any non-null slice returned by `f` is freed by this function after copying.
///
/// ## Returns
/// A newly allocated string; caller must free it.
///
/// ## Errors
/// Allocation or scanning errors.
pub fn replaceFn(self: *const Regex, allocator: std.mem.Allocator, data: []const u8, f: ReplaceFn) ![]const u8 {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    if (try self.findAllIndex(alloc, data, .{ .longest = true })) |matches| {
        var replaced: std.ArrayList(u8) = try .initCapacity(alloc, data.len);

        var last: usize = 0;

        for (matches) |m| {
            if (m.from > last) {
                try replaced.appendSlice(alloc, data[last..m.from]);
            }

            if (f(alloc, data[m.from..m.to])) |replacement| {
                try replaced.appendSlice(alloc, replacement);
            } else {
                try replaced.appendSlice(alloc, data[m.from..m.to]);
            }

            last = m.to;
        }

        if (last < data.len) {
            try replaced.appendSlice(alloc, data[last..]);
        }

        return allocator.dupe(u8, replaced.items);
    }

    return allocator.dupe(u8, data);
}

/// Splits `data` into parts separated by matches of the regex (delimiters omitted).
///
/// ## Returns
/// An owned slice of views into `data`. If no delimiter is found, returns a single-element slice containing `data`.
///
/// ## Ownership
/// Caller must free the returned outer slice with `allocator.free`; inner slices alias `data` and must not be freed.
///
/// ## Errors
/// Allocation or scanning errors.
pub fn split(self: *const Regex, allocator: std.mem.Allocator, data: []const u8) ![][]const u8 {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var parts: std.ArrayList([]const u8) = try .initCapacity(alloc, 4);

    if (try self.findAllIndex(alloc, data, .{ .longest = true })) |matches| {
        var last: usize = 0;

        for (matches) |m| {
            try parts.append(alloc, if (m.from > last) data[last..m.from] else "");

            last = m.to;
        }

        if (last < data.len) {
            try parts.append(alloc, data[last..]);
        }
    }

    if (parts.items.len == 0) {
        // No delimiter matched; return the original input as a single slice
        try parts.append(alloc, data);
    }

    return allocator.dupe([]const u8, parts.items);
}

// Unit Tests

test compile {
    const regex = try Regex.compile("hello");
    defer regex.deinit();

    if (try regex.find("hello world", .{})) |matched| {
        try std.testing.expectEqualSlices(u8, "hello", matched);
    } else {
        return error.NoMatched;
    }
}

test match {
    const regex = try Regex.compile("hello");
    defer regex.deinit();

    try std.testing.expect(try regex.match("hello world"));
    try std.testing.expect(!try regex.match("world"));
}

test find {
    const regex = try Regex.compile("hello");
    defer regex.deinit();

    if (try regex.find("hello world", .{})) |matched| {
        try std.testing.expectEqualSlices(u8, "hello", matched);
    } else {
        return error.NoMatched;
    }
}

test findIndex {
    const regex = try Regex.compile("hello");
    defer regex.deinit();

    if (try regex.findIndex("hello world", .{})) |span| {
        try std.testing.expectEqual(Match{
            .id = 0,
            .from = 0,
            .to = 5,
        }, span);
    } else {
        return error.NoMatched;
    }
}

test findAll {
    const regex = try Regex.compile("he[l]+o");
    defer regex.deinit();

    const matches = try regex.findAll(std.testing.allocator, "hello world helo helo", .{});

    if (matches) |m| {
        defer std.testing.allocator.free(m);

        try std.testing.expectEqualDeep(&[_][]const u8{ "hello", "helo", "helo" }, m);
    }
}

test findAllIndex {
    const regex = try Regex.compile("he[l]+o");
    defer regex.deinit();

    if (try regex.findAllIndex(std.testing.allocator, "hello world helo helo", .{})) |spans| {
        defer std.testing.allocator.free(spans);

        const expected = [_]Match{
            .{ .id = 0, .from = 0, .to = 5 },
            .{ .id = 0, .from = 12, .to = 16 },
            .{ .id = 0, .from = 17, .to = 21 },
        };

        try std.testing.expectEqualDeep(&expected, spans);
    } else {
        return error.NoMatched;
    }
}

test "findAllIndex with longest option (disambiguate same start)" {
    const regex = try Regex.compile("a(|b)");
    defer regex.deinit();

    if (try regex.findAllIndex(std.testing.allocator, "ab a abb", .{ .longest = true })) |spans_longest| {
        defer std.testing.allocator.free(spans_longest);

        const expected_longest = [_]Match{
            .{ .id = 0, .from = 0, .to = 2 }, // "ab"
            .{ .id = 0, .from = 3, .to = 4 }, // "a"
            .{ .id = 0, .from = 5, .to = 7 }, // "ab" from "abb"
        };

        try std.testing.expectEqualDeep(&expected_longest, spans_longest);
    } else {
        return error.NoMatched;
    }
}

test "findAllIndex default without ambiguity" {
    const regex = try Regex.compile("ab+");
    defer regex.deinit();

    if (try regex.findAllIndex(std.testing.allocator, "ab a abb", .{})) |spans| {
        defer std.testing.allocator.free(spans);

        const expected = [_]Match{
            .{ .id = 0, .from = 0, .to = 2 }, // "ab"
            .{ .id = 0, .from = 5, .to = 7 }, // "ab"
            .{ .id = 0, .from = 5, .to = 8 }, // "abb"
        };

        try std.testing.expectEqualDeep(&expected, spans);
    } else {
        return error.NoMatched;
    }
}

test replace {
    const regex = try Regex.compile("he[l]+o");
    defer regex.deinit();

    const replaced = try regex.replace(std.testing.allocator, "hello world helo helo", "world");
    defer std.testing.allocator.free(replaced);

    try std.testing.expectEqualSlices(u8, "world world world world", replaced);
}

test "replace memory management" {
    const regex = try Regex.compile("test");
    defer regex.deinit();

    // Test with matches
    const replaced1 = try regex.replace(std.testing.allocator, "test string test", "replaced");
    defer std.testing.allocator.free(replaced1);
    try std.testing.expectEqualSlices(u8, "replaced string replaced", replaced1);

    // Test without matches (should return original string)
    const replaced2 = try regex.replace(std.testing.allocator, "no match here", "replaced");
    defer std.testing.allocator.free(replaced2);
    try std.testing.expectEqualSlices(u8, "no match here", replaced2);

    // Test empty string
    const replaced3 = try regex.replace(std.testing.allocator, "", "replaced");
    defer std.testing.allocator.free(replaced3);
    try std.testing.expectEqualSlices(u8, "", replaced3);
}

test replaceFn {
    const regex = try Regex.compile("he[l]+o");
    defer regex.deinit();

    const replaced = try regex.replaceFn(
        std.testing.allocator,
        "hello world helo helo",
        struct {
            fn replace(allocator: std.mem.Allocator, data: []const u8) ?[]const u8 {
                return std.ascii.allocUpperString(allocator, data) catch return null;
            }
        }.replace,
    );

    defer std.testing.allocator.free(replaced);

    try std.testing.expectEqualSlices(u8, "HELLO world HELO HELO", replaced);
}

test "find with longest option" {
    const regex = try Regex.compile("a+b?");
    defer regex.deinit();

    // 默认最左匹配（非最长）
    if (try regex.find("aabb", .{})) |matched_leftmost| {
        try std.testing.expectEqualSlices(u8, "a", matched_leftmost);
    } else {
        return error.NoMatched;
    }

    // 开启最长匹配，应扩展到同起点的最长匹配
    if (try regex.find("aabb", .{ .longest = true })) |matched_longest| {
        try std.testing.expectEqualSlices(u8, "aab", matched_longest);
    } else {
        return error.NoMatched;
    }
}

test "findAll with longest option" {
    const regex = try Regex.compile("a(|b)");
    defer regex.deinit();

    const input = "ab a abb";

    const matches = try regex.findAll(std.testing.allocator, input, .{ .longest = true });
    if (matches) |m| {
        defer std.testing.allocator.free(m);

        try std.testing.expectEqualDeep(&[_][]const u8{ "ab", "a", "ab" }, m);
    } else {
        return error.NoMatched;
    }
}

test "replace with longest option" {
    const regex = try Regex.compile("a(|b)");
    defer regex.deinit();

    const replaced = try regex.replace(std.testing.allocator, "ab a abb", "X");
    defer std.testing.allocator.free(replaced);

    try std.testing.expectEqualSlices(u8, "X X Xb", replaced);
}

test split {
    const regex = try Regex.compile("a+");
    defer regex.deinit();

    const parts = try regex.split(std.testing.allocator, "abaabaccadaaae");
    defer std.testing.allocator.free(parts);

    try std.testing.expectEqualDeep(&[_][]const u8{ "", "b", "b", "cc", "d", "e" }, parts);
}

test "replaceFn returns null keeps original" {
    const regex = try Regex.compile("x+");
    defer regex.deinit();

    const input = "abxxcdx";

    const out = try regex.replaceFn(
        std.testing.allocator,
        input,
        struct {
            fn keep(_: std.mem.Allocator, _: []const u8) ?[]const u8 {
                return null;
            }
        }.keep,
    );
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualSlices(u8, input, out);
}

test "findAll returns null when no match" {
    const regex = try Regex.compile("hello");
    defer regex.deinit();

    const matches = try regex.findAll(std.testing.allocator, "world", .{});
    try std.testing.expect(matches == null);
}

test "split without delimiter returns input" {
    const regex = try Regex.compile(",");
    defer regex.deinit();

    const parts = try regex.split(std.testing.allocator, "abc");
    defer std.testing.allocator.free(parts);

    try std.testing.expectEqualDeep(&[_][]const u8{"abc"}, parts);
}

test "split only delimiters returns empty slice" {
    const regex = try Regex.compile(",");
    defer regex.deinit();

    const parts = try regex.split(std.testing.allocator, ",,,");
    defer std.testing.allocator.free(parts);

    try std.testing.expectEqualDeep(&[_][]const u8{ "", "", "" }, parts);
}
