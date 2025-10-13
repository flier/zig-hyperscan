//! A regular expression matcher using Hyperscan.

const std = @import("std");

const Error = @import("error.zig").Error;
const Database = @import("Database.zig").Database;
const Pattern = @import("../compile.zig").Pattern;

const runtime = @import("../runtime.zig");

const Scratch = runtime.Scratch;
const MatchEvent = runtime.MatchEvent;

db: Database,
scratch: Scratch,

const Regex = @This();

/// Compiles a regular expression into a Hyperscan database.
///
/// Returns a `Regex` object that can be used to find matches in data.
///
/// # Errors
/// - `error.CompileError`: If the pattern contains invalid regex syntax
/// - `error.OutOfMemory`: If insufficient memory is available
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
    const scratch: Scratch = try db.allocScratch();

    return .{ .db = db, .scratch = scratch };
}

/// Deinitializes a `Regex` object.
pub fn deinit(self: *const Regex) void {
    self.scratch.deinit();
    self.db.deinit();
}

/// Finds returns a slice holding the text of the leftmost match in `data` of the regular expression.
///
/// A return value of `null` indicates no match.
pub fn find(self: *const Regex, data: []const u8) !?[]const u8 {
    if (try self.findIndex(data)) |span| {
        return data[span.from..span.to];
    }

    return null;
}

/// A match.
pub const Match = struct {
    /// The id of the match.
    id: u32,
    /// The start index of the match.
    from: u64,
    /// The end index of the match.
    to: u64,
};

/// Finds the index of the leftmost match in `data` of the regular expression.
///
/// A return value of `null` indicates no match.
pub fn findIndex(self: *const Regex, data: []const u8) !?Match {
    const Context = struct {
        match: ?Match = null,
    };

    var context: Context = .{};

    self.db.scanBlock(data, self.scratch, .{
        .onEvent = struct {
            fn handler(evt: MatchEvent) !void {
                evt.data(Context).match = .{
                    .id = evt.id,
                    .from = evt.from.?,
                    .to = evt.to,
                };

                return error.Terminate;
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

/// Finds all matches in `data` of the regular expression.
///
/// Returns a slice of slices holding the text of all matches in `data`.
///
/// A return value of `null` indicates no match.
pub fn findAll(self: *const Regex, allocator: std.mem.Allocator, data: []const u8) !?[][]const u8 {
    if (try self.findAllIndex(allocator, data)) |matches| {
        defer allocator.free(matches);

        if (matches.len == 0) return null;

        var matched = try allocator.alloc([]const u8, matches.len);

        for (matches, 0..) |match, i| {
            matched[i] = data[match.from..match.to];
        }

        return matched;
    }

    return null;
}

pub fn findAllIndex(self: *const Regex, allocator: std.mem.Allocator, data: []const u8) !?[]Match {
    const Context = struct {
        allocator: std.mem.Allocator,
        matches: std.ArrayList(Match),
    };

    var context: Context = .{
        .allocator = allocator,
        .matches = try .initCapacity(allocator, 4),
    };

    defer context.matches.deinit(allocator);

    try self.db.scanBlock(data, self.scratch, .{
        .onEvent = struct {
            fn handler(evt: MatchEvent) !void {
                const ctx = evt.data(Context);

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

// Unit Tests

test compile {
    const regex = try Regex.compile("hello");
    defer regex.deinit();

    if (try regex.find("hello world")) |matched| {
        try std.testing.expectEqualSlices(u8, "hello", matched);
    } else {
        return error.NoMatched;
    }
}

test find {
    const regex = try Regex.compile("hello");
    defer regex.deinit();

    if (try regex.find("hello world")) |matched| {
        try std.testing.expectEqualSlices(u8, "hello", matched);
    } else {
        return error.NoMatched;
    }
}

test findIndex {
    const regex = try Regex.compile("hello");
    defer regex.deinit();

    if (try regex.findIndex("hello world")) |span| {
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

    const matches = try regex.findAll(std.testing.allocator, "hello world helo helo");

    if (matches) |m| {
        defer std.testing.allocator.free(m);

        try std.testing.expectEqualDeep(&[_][]const u8{ "hello", "helo", "helo" }, m);
    }
}

test findAllIndex {
    const regex = try Regex.compile("he[l]+o");
    defer regex.deinit();

    if (try regex.findAllIndex(std.testing.allocator, "hello world helo helo")) |spans| {
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
