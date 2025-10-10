const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const match = @import("match.zig");
const Scratch = @import("scratch.zig");

const Pattern = @import("../compile.zig").Pattern;
const Database = @import("../common.zig").Database;

const check = @import("../common.zig").check;

/// Scan options.
pub const Options = struct {
    /// The allocator to use for the scan.
    allocator: std.mem.Allocator = std.heap.c_allocator,
    /// Flags modifying the behaviour of scan behaviour.
    ///
    /// This parameter is provided for future use and is unused at present.
    flags: u32 = 0,
    /// Pointer to a match event callback function.
    ///
    /// If a null pointer is given, no matches will be returned.
    onEvent: match.EventHandler = null,
    /// The user defined pointer which will be passed to the callback function.
    context: ?*anyopaque = null,
};

/// The block (non-streaming) regular expression scanner.
pub fn scan_block(db: *const Database, data: []const u8, scratch: Scratch, opts: Options) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_scan(@ptrCast(db.ptr), data.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
}

/// The vectored regular expression scanner.
pub fn scan_vector(db: *const Database, data: []const std.posix.iovec_const, scratch: Scratch, opts: Options) !void {
    var ptrs = try std.ArrayList(*const u8).initCapacity(opts.allocator, data.len);
    var lens = try std.ArrayList(u32).initCapacity(opts.allocator, data.len);

    defer ptrs.deinit(opts.allocator);
    defer lens.deinit(opts.allocator);

    for (data) |buf| {
        try ptrs.append(opts.allocator, @ptrCast(buf.base));
        try lens.append(opts.allocator, @intCast(buf.len));
    }

    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_scan_vector(@ptrCast(db.ptr), ptrs.items.ptr, lens.items.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
}

// Unit tests

test scan_block {
    const pattern = try Pattern.parse("f[o]+");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    var to: u64 = 0;

    try scan_block(&db, "hello foobar", scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.setData(u64, evt.to);
            }
        }.handler,
        .context = &to,
    });

    try std.testing.expectEqual(9, to);
}

test "scan_block no matches" {
    const pattern = try Pattern.parse("xyz");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    var match_found = false;

    try scan_block(&db, "hello world", scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.setData(bool, true);
            }
        }.handler,
        .context = &match_found,
    });

    try std.testing.expect(!match_found);
}

test "scan_block empty data" {
    const pattern = try Pattern.parse("hello");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    var match_found = false;

    try scan_block(&db, "", scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.setData(bool, true);
            }
        }.handler,
        .context = &match_found,
    });

    try std.testing.expect(!match_found);
}

test "scan_block multiple matches" {
    const pattern = try Pattern.parse("hello");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    var matches = try std.ArrayList(u64).initCapacity(std.testing.allocator, 10);
    defer matches.deinit(std.testing.allocator);

    try scan_block(&db, "hello world hello", scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch |err| {
                    std.log.err("Failed to append match: {s}", .{@errorName(err)});
                    return error.Terminate;
                };
            }
        }.handler,
        .context = &matches,
    });

    // The pattern "hello" should match twice: at position 5 and 17
    try std.testing.expectEqual(@as(usize, 2), matches.items.len);
    try std.testing.expectEqual(@as(u64, 5), matches.items[0]); // "hello" at position 0-5
    try std.testing.expectEqual(@as(u64, 17), matches.items[1]); // "hello" at position 12-17
}

test "scan_block without callback" {
    const pattern = try Pattern.parse("f[o]+");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    // Should not crash when no callback is provided
    try scan_block(&db, "hello foobar", scratch, .{});
}

test "scan_block callback error handling" {
    const pattern = try Pattern.parse("f[o]+");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    try std.testing.expectError(error.ScanTerminated, scan_block(&db, "hello foobar", scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                _ = evt;
                return error.Terminate;
            }
        }.handler,
        .context = null,
    }));
}

test scan_vector {
    const pattern = try Pattern.parse("f[o]+");
    const db = try Database.compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello", .len = 5 },
        .{ .base = "foobar", .len = 6 },
    };

    var to: u64 = 0;

    try scan_vector(&db, data[0..data.len], scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.setData(u64, evt.to);
            }
        }.handler,
        .context = &to,
    });

    try std.testing.expectEqual(8, to);
}

test "scan_vector no matches" {
    const pattern = try Pattern.parse("xyz");
    const db = try Database.compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello", .len = 5 },
        .{ .base = "world", .len = 5 },
    };

    var match_found = false;

    try scan_vector(&db, data[0..data.len], scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.setData(bool, true);
            }
        }.handler,
        .context = &match_found,
    });

    try std.testing.expect(!match_found);
}

test "scan_vector empty data" {
    const pattern = try Pattern.parse("hello");
    const db = try Database.compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{};

    var match_found = false;

    try scan_vector(&db, data[0..data.len], scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.setData(bool, true);
            }
        }.handler,
        .context = &match_found,
    });

    try std.testing.expect(!match_found);
}

test "scan_vector multiple matches" {
    const pattern = try Pattern.parse("hello");
    const db = try Database.compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello", .len = 5 },
        .{ .base = " world ", .len = 7 },
        .{ .base = "hello", .len = 5 },
    };

    var matches = try std.ArrayList(u64).initCapacity(std.testing.allocator, 10);
    defer matches.deinit(std.testing.allocator);

    try scan_vector(&db, data[0..data.len], scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch |err| {
                    std.log.err("Failed to append match: {s}", .{@errorName(err)});
                    return error.Terminate;
                };
            }
        }.handler,
        .context = &matches,
    });

    // The pattern "hello" should match twice: at position 5 and 17
    // In vectored mode, the offset is cumulative across all vectors
    try std.testing.expectEqual(@as(usize, 2), matches.items.len);
    try std.testing.expectEqual(@as(u64, 5), matches.items[0]); // "hello" at position 0-5
    try std.testing.expectEqual(@as(u64, 17), matches.items[1]); // "hello" at position 12-17
}

test "scan_vector without callback" {
    const pattern = try Pattern.parse("f[o]+");
    const db = try Database.compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello", .len = 5 },
        .{ .base = "foobar", .len = 6 },
    };

    // Should not crash when no callback is provided
    try scan_vector(&db, data[0..data.len], scratch, .{});
}

test "scan_vector callback error handling" {
    const pattern = try Pattern.parse("f[o]+");
    const db = try Database.compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello", .len = 5 },
        .{ .base = "foobar", .len = 6 },
    };

    try std.testing.expectError(error.ScanTerminated, scan_vector(&db, data[0..data.len], scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                _ = evt;
                return error.Terminate;
            }
        }.handler,
        .context = null,
    }));
}

test "scan with different pattern types" {
    // Test with simple literal pattern
    {
        const pattern = try Pattern.parse("hello");
        const db = try Database.compile(&pattern, .{ .literal = true });
        defer db.deinit();

        const scratch = try db.alloc_scratch();
        defer scratch.deinit();

        var match_found = false;

        try scan_block(&db, "hello world", scratch, .{
            .onEvent = struct {
                fn handler(evt: match.Event) !void {
                    evt.setData(bool, true);
                }
            }.handler,
            .context = &match_found,
        });

        try std.testing.expect(match_found);
    }

    // Test with complex regex pattern
    {
        const pattern = try Pattern.parse("\\b\\w+@\\w+\\.\\w+\\b");
        const db = try Database.compile(&pattern, .{});
        defer db.deinit();

        const scratch = try db.alloc_scratch();
        defer scratch.deinit();

        var match_found = false;

        try scan_block(&db, "Contact us at test@example.com for more info", scratch, .{
            .onEvent = struct {
                fn handler(evt: match.Event) !void {
                    evt.setData(bool, true);
                }
            }.handler,
            .context = &match_found,
        });

        try std.testing.expect(match_found);
    }
}
