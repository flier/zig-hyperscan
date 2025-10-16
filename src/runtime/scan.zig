const std = @import("std");

const hs = @cImport(@cInclude("hs/hs.h"));

const match = @import("match.zig");
const Scratch = @import("Scratch.zig");

const Pattern = @import("../compile.zig").Pattern;
const Database = @import("../common.zig").Database;

const check = @import("../common.zig").check;

/// Scan options.
pub const Options = struct {
    /// The allocator to use for the scan.
    allocator: ?std.mem.Allocator = null,
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
pub fn scanBlock(db: *const Database, data: []const u8, scratch: Scratch, opts: Options) !void {
    var ctx: match.Context = .init(opts.onEvent, opts.context);

    return check(hs.hs_scan(@ptrCast(db.ptr), data.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.ptr), ctx.trampoline, &ctx));
}

/// The vectored regular expression scanner.
pub fn scanVector(db: *const Database, data: []const std.posix.iovec_const, scratch: Scratch, opts: Options) !void {
    var arena: std.heap.ArenaAllocator = .init(opts.allocator orelse std.heap.c_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ptrs = try std.ArrayList(*const u8).initCapacity(alloc, data.len);
    var lens = try std.ArrayList(u32).initCapacity(alloc, data.len);

    for (data) |buf| {
        try ptrs.append(alloc, @ptrCast(buf.base));
        try lens.append(alloc, @intCast(buf.len));
    }

    var ctx: match.Context = .init(opts.onEvent, opts.context);

    return check(hs.hs_scan_vector(@ptrCast(db.ptr), ptrs.items.ptr, lens.items.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.ptr), ctx.trampoline, &ctx));
}

/// The streaming regular expression scanner.
pub fn scanStream(db: *const Database, reader: *std.Io.Reader, scratch: Scratch, opts: Options) !void {
    const stream = try db.openStream(.{});

    var buf: [std.heap.pageSize()]u8 = undefined;

    while (reader.readSliceShort(&buf)) |read| {
        if (read == 0) {
            try stream.close(scratch, opts);

            break;
        }

        try stream.scan(buf[0..read], scratch, opts);
    } else |err| {
        return err;
    }
}

// Unit tests

test scanBlock {
    const pattern: Pattern = try .parse("f[o]+");
    var db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    var to: u64 = 0;

    try scanBlock(&db, "hello foobar", scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u64).* = evt.to;
            }
        }.handler,
        .context = &to,
    });

    try std.testing.expectEqual(9, to);
}

test "scanBlock no matches" {
    const pattern: Pattern = try .parse("xyz");
    var db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    var match_found = false;

    try scanBlock(&db, "hello world", scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(bool).* = true;
            }
        }.handler,
        .context = &match_found,
    });

    try std.testing.expect(!match_found);
}

test "scanBlock empty data" {
    const pattern: Pattern = try .parse("hello");
    var db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    var match_found = false;

    try scanBlock(&db, "", scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(bool).* = true;
            }
        }.handler,
        .context = &match_found,
    });

    try std.testing.expect(!match_found);
}

test "scanBlock multiple matches" {
    const pattern: Pattern = try .parse("hello");
    var db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    var matches: std.ArrayList(u64) = try .initCapacity(std.testing.allocator, 10);
    defer matches.deinit(std.testing.allocator);

    try scanBlock(&db, "hello world hello", scratch, .{
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

test "scanBlock without callback" {
    const pattern: Pattern = try .parse("f[o]+");
    var db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    // Should not crash when no callback is provided
    try scanBlock(&db, "hello foobar", scratch, .{});
}

test "scanBlock callback error handling" {
    const pattern: Pattern = try .parse("f[o]+");
    var db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    try std.testing.expectError(error.ScanTerminated, scanBlock(&db, "hello foobar", scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                _ = evt;
                return error.Terminate;
            }
        }.handler,
        .context = null,
    }));
}

test scanVector {
    const pattern: Pattern = try .parse("f[o]+");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello", .len = 5 },
        .{ .base = "foobar", .len = 6 },
    };

    var to: u64 = 0;

    try scanVector(&db, data[0..data.len], scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u64).* = evt.to;
            }
        }.handler,
        .context = &to,
    });

    try std.testing.expectEqual(8, to);
}

test "scanVector no matches" {
    const pattern: Pattern = try .parse("xyz");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello", .len = 5 },
        .{ .base = "world", .len = 5 },
    };

    var match_found = false;

    try scanVector(&db, data[0..data.len], scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(bool).* = true;
            }
        }.handler,
        .context = &match_found,
    });

    try std.testing.expect(!match_found);
}

test "scanVector empty data" {
    const pattern: Pattern = try .parse("hello");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{};

    var match_found = false;

    try scanVector(&db, data[0..data.len], scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(bool).* = true;
            }
        }.handler,
        .context = &match_found,
    });

    try std.testing.expect(!match_found);
}

test "scanVector multiple matches" {
    const pattern: Pattern = try .parse("hello");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello", .len = 5 },
        .{ .base = " world ", .len = 7 },
        .{ .base = "hello", .len = 5 },
    };

    var matches: std.ArrayList(u64) = try .initCapacity(std.testing.allocator, 10);
    defer matches.deinit(std.testing.allocator);

    try scanVector(&db, data[0..data.len], scratch, .{
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

test "scanVector without callback" {
    const pattern: Pattern = try .parse("f[o]+");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello", .len = 5 },
        .{ .base = "foobar", .len = 6 },
    };

    // Should not crash when no callback is provided
    try scanVector(&db, data[0..data.len], scratch, .{});
}

test "scanVector callback error handling" {
    const pattern: Pattern = try .parse("f[o]+");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello", .len = 5 },
        .{ .base = "foobar", .len = 6 },
    };

    try std.testing.expectError(error.ScanTerminated, scanVector(&db, data[0..data.len], scratch, .{
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
        const pattern: Pattern = try .parse("hello");
        var db: Database = try .compile(&pattern, .{ .literal = true });
        defer db.deinit();

        var scratch = try db.allocScratch();
        defer scratch.deinit();

        var match_found = false;

        try scanBlock(&db, "hello world", scratch, .{
            .onEvent = struct {
                fn handler(evt: match.Event) !void {
                    evt.data(bool).* = true;
                }
            }.handler,
            .context = &match_found,
        });

        try std.testing.expect(match_found);
    }

    // Test with complex regex pattern
    {
        const pattern: Pattern = try .parse("\\b\\w+@\\w+\\.\\w+\\b");
        var db: Database = try .compile(&pattern, .{});
        defer db.deinit();

        var scratch = try db.allocScratch();
        defer scratch.deinit();

        var match_found = false;

        try scanBlock(&db, "Contact us at test@example.com for more info", scratch, .{
            .onEvent = struct {
                fn handler(evt: match.Event) !void {
                    evt.data(bool).* = true;
                }
            }.handler,
            .context = &match_found,
        });

        try std.testing.expect(match_found);
    }
}

// ===== scanStream Unit Tests =====

test scanStream {
    const pattern: Pattern = try .parse("f[o]+");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const test_data = "hello foobar world";
    var reader: std.Io.Reader = .fixed(test_data);
    var to: u64 = 0;

    try scanStream(&db, &reader, scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u64).* = evt.to;
            }
        }.handler,
        .context = &to,
    });

    try std.testing.expectEqual(9, to);
}

test "scanStream no matches" {
    const pattern: Pattern = try .parse("xyz");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const test_data = "hello world";
    var reader: std.Io.Reader = .fixed(test_data);
    var match_found = false;

    try scanStream(&db, &reader, scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(bool).* = true;
            }
        }.handler,
        .context = &match_found,
    });

    try std.testing.expect(!match_found);
}

test "scanStream empty data" {
    const pattern: Pattern = try .parse("hello");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const test_data = "";
    var reader: std.Io.Reader = .fixed(test_data);
    var match_found = false;

    try scanStream(&db, &reader, scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(bool).* = true;
            }
        }.handler,
        .context = &match_found,
    });

    try std.testing.expect(!match_found);
}

test "scanStream multiple matches" {
    const pattern: Pattern = try .parse("hello");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const test_data = "hello world hello";
    var reader: std.Io.Reader = .fixed(test_data);
    var matches: std.ArrayList(u64) = try .initCapacity(std.testing.allocator, 10);
    defer matches.deinit(std.testing.allocator);

    try scanStream(&db, &reader, scratch, .{
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
    try std.testing.expectEqualDeep(&[_]u64{ 5, 17 }, matches.items);
}

test "scanStream without callback" {
    const pattern: Pattern = try .parse("f[o]+");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const test_data = "hello foobar world";
    var reader: std.Io.Reader = .fixed(test_data);

    // Should not crash when no callback is provided
    try scanStream(&db, &reader, scratch, .{});
}

test "scanStream callback error handling" {
    const pattern: Pattern = try .parse("f[o]+");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const test_data = "hello foobar world";
    var reader: std.Io.Reader = .fixed(test_data);

    try std.testing.expectError(error.ScanTerminated, scanStream(&db, &reader, scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                _ = evt;
                return error.Terminate;
            }
        }.handler,
        .context = null,
    }));
}

test "scanStream large data" {
    const pattern: Pattern = try .parse("test");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    // Create data larger than page size to test chunked reading
    var test_data: std.ArrayList(u8) = try .initCapacity(std.testing.allocator, std.heap.pageSize() * 2);
    defer test_data.deinit(std.testing.allocator);

    // Fill with "hello" repeated many times, then add "test" at the end
    for (0..(std.heap.pageSize() / 5)) |_| {
        try test_data.appendSlice(std.testing.allocator, "hello");
    }
    try test_data.appendSlice(std.testing.allocator, "test");

    var reader: std.Io.Reader = .fixed(test_data.items);
    var match_found = false;

    try scanStream(&db, &reader, scratch, .{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(bool).* = true;
            }
        }.handler,
        .context = &match_found,
    });

    try std.testing.expect(match_found);
}
