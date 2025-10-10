//! A Hyperscan scanning stream.

const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const Database = @import("../common.zig").Database;
const Pattern = @import("../compile.zig").Pattern;

const match = @import("match.zig");

const ScanOptions = @import("scan.zig").Options;
const Scratch = @import("scratch.zig");

const check = @import("../common.zig").check;

pub const Stream = @This();

stream_id: *hs.hs_stream_t,

/// Open options.
pub const OpenOptions = struct {
    flags: u32 = 0,
};

/// Open and initialise a stream.
pub fn open(db: *const Database, opts: OpenOptions) !Stream {
    var stream_id: ?*hs.hs_stream_t = null;

    try check(hs.hs_open_stream(@ptrCast(db.ptr), opts.flags, &stream_id));

    return if (stream_id) |id| Stream{
        .stream_id = id,
    } else error.UnknownError;
}

/// Write data to be scanned to the opened stream.
pub fn scan(self: *const Stream, data: []const u8, scratch: Scratch, opts: ScanOptions) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_scan_stream(self.stream_id, data.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
}

/// Close a stream.
pub fn close(self: *const Stream, scratch: Scratch, opts: ScanOptions) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_close_stream(self.stream_id, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
}

/// Reset a stream to an initial state.
pub fn reset(self: *const Stream, scratch: Scratch, opts: ScanOptions) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_reset_stream(self.stream_id, opts.flags, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
}

/// Duplicate the given stream.
///
/// The new stream will have the same state as the original including the current stream offset.
pub fn copy(self: *const Stream) !Stream {
    var stream_id: ?*hs.hs_stream_t = null;

    try check(hs.hs_copy_stream(&stream_id, self.stream_id));

    return if (stream_id) |id| Stream{
        .stream_id = id,
    } else error.UnknownError;
}

/// Duplicate the given stream state onto a new stream.
///
/// The new stream will first be reset
/// (reporting any EOD matches if a non-NULL @p onEvent callback handler is provided).
pub fn reset_and_copy(self: *const Stream, to: *Stream, scratch: Scratch, opts: ScanOptions) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_reset_and_copy_stream(to.stream_id, self.stream_id, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
}

// Unit tests

test open {
    const foobar = try Pattern.parse("f[o]+bar");
    const db = try Database.compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    // open the stream
    const stream = try open(&db, .{});

    // close the stream
    try stream.close(scratch, .{});
}

test scan {
    // parse the pattern
    const foobar = try Pattern.parse("f[o]+bar");

    // compile the pattern into a streaming database
    const db = try Database.compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    // open the stream
    const stream = try db.open_stream(.{});

    // create the variable that will store the last match offset
    var to: u64 = 0;

    // create the scan options with the test handler that will set the `to` variable to the last match offset
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.setData(u64, evt.to);
            }
        }.handler,
        .context = &to,
    };

    // scan the first part of the string
    try stream.scan("foo", scratch, opts);

    // expect no matches
    try std.testing.expectEqual(0, to);

    // scan the second part of the string
    try stream.scan("bar", scratch, opts);

    // expect one match
    try std.testing.expectEqual(6, to);

    // close the stream
    try stream.close(scratch, opts);
}

test close {
    // parse the pattern
    const foobar = try Pattern.parse("f[o]+bar+$");

    // compile the pattern into a streaming database
    const db = try Database.compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    // open the stream
    const stream = try db.open_stream(.{});

    // create the variable that will store the last match offset
    var to: u64 = 0;

    // create the scan options with the test handler that will set the `to` variable to the last match offset
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.setData(u64, evt.to);
            }
        }.handler,
        .context = &to,
    };

    // scan the first part of the string
    try stream.scan("foo", scratch, opts);

    // expect no matches
    try std.testing.expectEqual(0, to);

    // scan the second part of the string
    try stream.scan("bar", scratch, opts);

    // expect no match, because the pattern is anchored to the end of the string
    try std.testing.expectEqual(0, to);

    // close the stream, then this should report the match
    try stream.close(scratch, opts);

    // expect one match, because the end of the string was reached
    try std.testing.expectEqual(6, to);
}

test reset {
    // parse the pattern
    const foobar = try Pattern.parse("f[o]+bar");

    // compile the pattern into a streaming database
    const db = try Database.compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    // open the stream
    const stream = try db.open_stream(.{});

    // create the variable that will store the last match offset
    var to: u64 = 0;

    // create the scan options with the test handler that will set the `to` variable to the last match offset
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.setData(u64, evt.to);
            }
        }.handler,
        .context = &to,
    };

    // scan the first part of the string
    try stream.scan("foo", scratch, opts);

    // expect no matches since the string was not complete
    try std.testing.expectEqual(0, to);

    // reset the stream, this should have the same state as the original stream
    try stream.reset(scratch, opts);

    // scan the first part of the string again
    try stream.scan("foo", scratch, opts);

    // expect no matches since the stream was reset
    try std.testing.expectEqual(0, to);

    // scan the second part of the string
    try stream.scan("bar", scratch, opts);

    // expect one match
    try std.testing.expectEqual(6, to);

    // close the stream
    try stream.close(scratch, opts);
}

test copy {
    // parse the pattern
    const foobar = try Pattern.parse("f[o]+bar");

    // compile the pattern into a streaming database
    const db = try Database.compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    // open the stream
    const stream = try db.open_stream(.{});

    // create the variable that will store the last match offset
    var to: u64 = 0;

    // create the scan options with the test handler that will set the `to` variable to the last match offset
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.setData(u64, evt.to);
            }
        }.handler,
        .context = &to,
    };

    // scan the first part of the string
    try stream.scan("foo", scratch, opts);

    // expect no matches since the string was not complete
    try std.testing.expectEqual(0, to);

    // copy the stream, this should have the same state as the original stream
    const stream2 = try stream.copy();

    // scan the second part of the string
    try stream.scan("bar", scratch, opts);

    // expect one match
    try std.testing.expectEqual(6, to);

    // close the stream
    try stream.close(scratch, opts);

    // scan the second part of the string
    try stream2.scan("oobar", scratch, opts);

    // expect one match
    try std.testing.expectEqual(8, to);

    // close the stream
    try stream2.close(scratch, opts);
}

test reset_and_copy {
    // parse the pattern
    const foobar = try Pattern.parse("f[o]+bar");

    // compile the pattern into a streaming database
    const db = try Database.compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    // open the stream
    const stream = try db.open_stream(.{});

    // create the variable that will store the last match offset
    var to: u64 = 0;

    // create the scan options with the test handler that will set the `to` variable to the last match offset
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.setData(u64, evt.to);
            }
        }.handler,
        .context = &to,
    };

    // scan the first part of the string
    try stream.scan("foo", scratch, opts);

    // expect no matches since the string was not complete
    try std.testing.expectEqual(0, to);

    // copy the stream
    var stream2 = try stream.copy();

    // then copy and reset the stream, then the stream2 should have the same state as the original stream
    try stream.reset_and_copy(&stream2, scratch, opts);

    // scan the second part of the string
    try stream.scan("bar", scratch, opts);

    // expect one match
    try std.testing.expectEqual(6, to);

    // close the stream
    try stream.close(scratch, opts);

    // scan the string
    try stream2.scan("foooobar", scratch, opts);

    // expect one match
    try std.testing.expectEqual(11, to);

    // close the stream
    try stream2.close(scratch, opts);
}

// Error handling tests

test "open steam with non-streaming database" {
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{ .mode = .{ .block = true } });
    defer db.deinit();

    try std.testing.expectError(error.DbModeError, db.open_stream(.{}));
}

test "scan with empty data" {
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});
    defer stream.close(scratch, .{}) catch {};

    var match_count: u32 = 0;

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count,
    };

    // Scan empty data - should not crash
    try stream.scan("", scratch, opts);
    try std.testing.expectEqual(0, match_count);
}

test "scan with null event handler" {
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});
    defer stream.close(scratch, .{}) catch {};

    // Scan with null event handler - should not crash
    try stream.scan("test data", scratch, .{ .onEvent = null });
}

test "close without scan" {
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});

    // Close stream without scanning - should work
    try stream.close(scratch, .{});
}

test "reset without scan" {
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});
    defer stream.close(scratch, .{}) catch {};

    // Reset stream without scanning - should work
    try stream.reset(scratch, .{});
}

// Edge case tests

test "scan with very large data" {
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});
    defer stream.close(scratch, .{}) catch {};

    // Create a large string (1MB)
    const large_data = try std.testing.allocator.alloc(u8, 1024 * 1024);
    defer std.testing.allocator.free(large_data);

    // Fill with 'a' characters and add 'test' at the end
    @memset(large_data, 'a');
    @memcpy(large_data[large_data.len - 4 ..], "test");

    var match_count: u32 = 0;
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count,
    };

    try stream.scan(large_data, scratch, opts);
    try std.testing.expectEqual(1, match_count);
}

test "scan with special characters" {
    const pattern = try Pattern.parse("\\x00\\x01\\x02");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});
    defer stream.close(scratch, .{}) catch {};

    var match_count: u32 = 0;
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count,
    };

    // Test with null bytes and control characters
    const special_data = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05 };
    try stream.scan(&special_data, scratch, opts);
    try std.testing.expectEqual(1, match_count);
}

test "scan with unicode characters" {
    const pattern = try Pattern.parse("测试");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});
    defer stream.close(scratch, .{}) catch {};

    var match_count: u32 = 0;
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count,
    };

    const unicode_data = "这是测试数据";
    try stream.scan(unicode_data, scratch, opts);
    try std.testing.expectEqual(1, match_count);
}

test "multiple scans with different patterns" {
    const patterns = [_]Pattern{
        try Pattern.parse("hello"),
        try Pattern.parse("world"),
    };
    const db = try Database.compile_multi(&patterns, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});
    defer stream.close(scratch, .{}) catch {};

    var matches = try std.ArrayList(u64).initCapacity(std.testing.allocator, 10);
    defer matches.deinit(std.testing.allocator);

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch {};
            }
        }.handler,
        .context = &matches,
    };

    // Multiple scans
    try stream.scan("hello ", scratch, opts);
    try stream.scan("beautiful ", scratch, opts);
    try stream.scan("world", scratch, opts);

    try std.testing.expectEqual(2, matches.items.len);
    try std.testing.expectEqual(5, matches.items[0]); // "hello"
    try std.testing.expectEqual(21, matches.items[1]); // "world"
}

// Concurrent tests

test "multiple streams with same database" {
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    // Create multiple streams
    const stream1 = try db.open_stream(.{});
    const stream2 = try db.open_stream(.{});
    const stream3 = try db.open_stream(.{});

    var match_count1: u32 = 0;
    var match_count2: u32 = 0;
    var match_count3: u32 = 0;

    const opts1 = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count1,
    };

    const opts2 = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count2,
    };

    const opts3 = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count3,
    };

    // Scan different data with each stream
    try stream1.scan("test data 1", scratch, opts1);
    try stream2.scan("test data 2", scratch, opts2);
    try stream3.scan("test data 3", scratch, opts3);

    // Close all streams
    try stream1.close(scratch, opts1);
    try stream2.close(scratch, opts2);
    try stream3.close(scratch, opts3);

    try std.testing.expectEqual(1, match_count1);
    try std.testing.expectEqual(1, match_count2);
    try std.testing.expectEqual(1, match_count3);
}

test "scan multi parts data and terminate on second match" {
    // Parse a pattern that will match multiple times
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});
    defer stream.close(scratch, .{}) catch {};

    // Track matches and termination
    var matches = try std.ArrayList(u64).initCapacity(std.testing.allocator, 10);
    defer matches.deinit(std.testing.allocator);
    var terminated = false;

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                const ctx = evt.data(struct {
                    matches: *std.ArrayList(u64),
                    terminated: *bool,
                });

                // Record the match
                ctx.matches.append(std.testing.allocator, evt.to) catch |err| {
                    std.log.err("Failed to append match: {s}", .{@errorName(err)});
                    return error.Terminate;
                };

                // Terminate on second match
                if (ctx.matches.items.len >= 2) {
                    ctx.terminated.* = true;
                    return error.Terminate;
                }
            }
        }.handler,
        .context = @constCast(&.{ .matches = &matches, .terminated = &terminated }),
    };

    // Scan first part - should match once
    try stream.scan("first test data", scratch, opts);
    try std.testing.expectEqual(1, matches.items.len);
    try std.testing.expectEqual(10, matches.items[0]); // "test" at position 6-10
    try std.testing.expect(!terminated);

    // Scan second part - should match second time and terminate
    try std.testing.expectError(error.ScanTerminated, stream.scan(" second test data", scratch, opts));
    try std.testing.expectEqual(2, matches.items.len);
    try std.testing.expectEqual(27, matches.items[1]); // "test" at position 23-27
    try std.testing.expect(terminated);

    // Scan third part - should be skipped due to termination
    // This should not cause any additional matches
    const before_count = matches.items.len;
    try std.testing.expectError(error.ScanTerminated, stream.scan(" third test data", scratch, opts));
    try std.testing.expectEqual(before_count, matches.items.len); // No new matches
}

test "scan multi parts data and terminate on first match" {
    // Parse a pattern that will match multiple times
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});
    defer stream.close(scratch, .{}) catch {};

    // Track matches and termination
    var matches = try std.ArrayList(u64).initCapacity(std.testing.allocator, 10);
    defer matches.deinit(std.testing.allocator);
    var terminated = false;

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                const ctx = evt.data(struct {
                    matches: *std.ArrayList(u64),
                    terminated: *bool,
                });

                // Record the match
                ctx.matches.append(std.testing.allocator, evt.to) catch |err| {
                    std.log.err("Failed to append match: {s}", .{@errorName(err)});
                    return error.Terminate;
                };

                // Terminate on first match
                ctx.terminated.* = true;
                return error.Terminate;
            }
        }.handler,
        .context = @constCast(&.{ .matches = &matches, .terminated = &terminated }),
    };

    // Scan first part - should match once and terminate immediately
    try std.testing.expectError(error.ScanTerminated, stream.scan("first test data", scratch, opts));
    try std.testing.expectEqual(1, matches.items.len);
    try std.testing.expectEqual(10, matches.items[0]); // "test" at position 6-10
    try std.testing.expect(terminated);

    // Scan second part - should be skipped due to previous termination
    const before_count = matches.items.len;
    try std.testing.expectError(error.ScanTerminated, stream.scan(" second test data", scratch, opts));
    try std.testing.expectEqual(before_count, matches.items.len); // No new matches
}

test "scan multi parts data with multiple patterns and terminate on second match" {
    // Parse multiple patterns that will match multiple times
    const patterns = [_]Pattern{
        try Pattern.parse("hello"),
        try Pattern.parse("world"),
    };
    const db = try Database.compile_multi(&patterns, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});
    defer stream.close(scratch, .{}) catch {};

    // Track matches and termination
    var matches = try std.ArrayList(struct { id: u32, to: u64 }).initCapacity(std.testing.allocator, 10);
    defer matches.deinit(std.testing.allocator);
    var terminated = false;

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                const ctx = evt.data(struct {
                    matches: *std.ArrayList(struct { id: u32, to: u64 }),
                    terminated: *bool,
                });

                // Record the match
                ctx.matches.append(std.testing.allocator, .{ .id = evt.id, .to = evt.to }) catch |err| {
                    std.log.err("Failed to append match: {s}", .{@errorName(err)});
                    return error.Terminate;
                };

                // Terminate on second match
                if (ctx.matches.items.len >= 2) {
                    ctx.terminated.* = true;
                    return error.Terminate;
                }
            }
        }.handler,
        .context = @constCast(&.{ .matches = &matches, .terminated = &terminated }),
    };

    // Scan first part - should match "hello"
    try stream.scan("hello ", scratch, opts);
    try std.testing.expectEqual(1, matches.items.len);
    try std.testing.expectEqual(0, matches.items[0].id); // "hello" pattern id
    try std.testing.expectEqual(5, matches.items[0].to); // "hello" at position 0-5
    try std.testing.expect(!terminated);

    // Scan second part - should match "world" and terminate
    try std.testing.expectError(error.ScanTerminated, stream.scan("world ", scratch, opts));
    try std.testing.expectEqual(2, matches.items.len);
    try std.testing.expectEqual(1, matches.items[1].id); // "world" pattern id
    try std.testing.expectEqual(11, matches.items[1].to); // "world" at position 6-11
    try std.testing.expect(terminated);

    // Scan third part - should be skipped due to termination
    const before_count = matches.items.len;
    try std.testing.expectError(error.ScanTerminated, stream.scan("hello world", scratch, opts));
    try std.testing.expectEqual(before_count, matches.items.len); // No new matches
}
