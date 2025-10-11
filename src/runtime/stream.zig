//! A Hyperscan scanning stream.

const std = @import("std");

const hs = @cImport(@cInclude("hs/hs.h"));

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

    return if (stream_id) |id| .{
        .stream_id = id,
    } else error.UnknownError;
}

/// Write data to be scanned to the opened stream.
pub fn scan(self: *const Stream, data: []const u8, scratch: Scratch, opts: ScanOptions) !void {
    const ctx: match.Context = .init(opts.onEvent, opts.context);

    return check(hs.hs_scan_stream(self.stream_id, data.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.ptr), ctx.trampoline, @constCast(&ctx)));
}

/// Close a stream.
pub fn close(self: *const Stream, scratch: Scratch, opts: ScanOptions) !void {
    const ctx: match.Context = .init(opts.onEvent, opts.context);

    return check(hs.hs_close_stream(self.stream_id, @ptrCast(scratch.ptr), ctx.trampoline, @constCast(&ctx)));
}

/// Reset a stream to an initial state.
pub fn reset(self: *const Stream, scratch: Scratch, opts: ScanOptions) !void {
    const ctx: match.Context = .init(opts.onEvent, opts.context);

    return check(hs.hs_reset_stream(self.stream_id, opts.flags, @ptrCast(scratch.ptr), ctx.trampoline, @constCast(&ctx)));
}

/// Duplicate the given stream.
///
/// The new stream will have the same state as the original including the current stream offset.
pub fn copy(self: *const Stream) !Stream {
    var stream_id: ?*hs.hs_stream_t = null;

    try check(hs.hs_copy_stream(&stream_id, self.stream_id));

    return if (stream_id) |id| .{
        .stream_id = id,
    } else error.UnknownError;
}

/// Duplicate the given stream state onto a new stream.
///
/// The new stream will first be reset
/// (reporting any EOD matches if a non-NULL @p onEvent callback handler is provided).
pub fn resetAndCopy(self: *const Stream, to: *Stream, scratch: Scratch, opts: ScanOptions) !void {
    const ctx: match.Context = .init(opts.onEvent, opts.context);

    return check(hs.hs_reset_and_copy_stream(to.stream_id, self.stream_id, @ptrCast(scratch.ptr), ctx.trampoline, @constCast(&ctx)));
}

/// Creates a compressed representation of the provided stream in the buffer provided.
///
/// This compressed representation can be converted back into a stream state
/// by using `expand` or `resetAndExpand`.
pub fn compress(self: *const Stream, allocator: std.mem.Allocator) ![]u8 {
    var sz: usize = 0;

    var res = hs.hs_compress_stream(self.stream_id, null, 0, &sz);

    var buf: []u8 = undefined;

    if (res == hs.HS_INSUFFICIENT_SPACE) {
        buf = try allocator.alloc(u8, sz);

        res = hs.hs_compress_stream(self.stream_id, buf.ptr, buf.len, &sz);
    }

    try check(res);

    return buf[0..sz];
}

/// Decompresses a compressed representation created by `compress` into a new stream.
pub fn expand(db: *const Database, buf: []const u8) !Stream {
    var stream_id: ?*hs.hs_stream_t = null;

    try check(hs.hs_expand_stream(@ptrCast(db.ptr), &stream_id, buf.ptr, @intCast(buf.len)));

    return if (stream_id) |id| .{
        .stream_id = id,
    } else error.UnknownError;
}

/// Decompresses a compressed representation created by `compress` on top of the stream.
///
/// The stream will first be reset (reporting any EOD matches if a non-NULL `onEvent` callback handler is provided).
pub fn resetAndExpand(self: *Stream, buf: []const u8, scratch: Scratch, opts: ScanOptions) !void {
    const ctx: match.Context = .init(opts.onEvent, opts.context);

    return check(hs.hs_reset_and_expand_stream(self.stream_id, buf.ptr, @intCast(buf.len), @ptrCast(scratch.ptr), ctx.trampoline, @constCast(&ctx)));
}

// Unit tests

test open {
    const foobar: Pattern = try .parse("f[o]+bar");
    const db: Database = try .compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // open the stream
    const stream = try open(&db, .{});

    // close the stream
    try stream.close(scratch, .{});
}

test scan {
    // parse the pattern
    const foobar: Pattern = try .parse("f[o]+bar");

    // compile the pattern into a streaming database
    const db: Database = try .compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // open the stream
    const stream = try db.openStream(.{});

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
    const foobar: Pattern = try .parse("f[o]+bar+$");

    // compile the pattern into a streaming database
    const db: Database = try .compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // open the stream
    const stream = try db.openStream(.{});

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
    const foobar: Pattern = try .parse("f[o]+bar");

    // compile the pattern into a streaming database
    const db: Database = try .compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // open the stream
    const stream = try db.openStream(.{});

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
    const foobar: Pattern = try .parse("f[o]+bar");

    // compile the pattern into a streaming database
    const db: Database = try .compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // open the stream
    const stream = try db.openStream(.{});

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

test resetAndCopy {
    // parse the pattern
    const foobar: Pattern = try .parse("f[o]+bar");

    // compile the pattern into a streaming database
    const db: Database = try .compile(&foobar, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // allocate the scratch space
    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // open the stream
    const stream = try db.openStream(.{});

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
    try stream.resetAndCopy(&stream2, scratch, opts);

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
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .block = true } });
    defer db.deinit();

    try std.testing.expectError(error.DbModeError, db.openStream(.{}));
}

test "scan with empty data" {
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});
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
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});
    defer stream.close(scratch, .{}) catch {};

    // Scan with null event handler - should not crash
    try stream.scan("test data", scratch, .{ .onEvent = null });
}

test "close without scan" {
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});

    // Close stream without scanning - should work
    try stream.close(scratch, .{});
}

test "reset without scan" {
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});
    defer stream.close(scratch, .{}) catch {};

    // Reset stream without scanning - should work
    try stream.reset(scratch, .{});
}

// Edge case tests

test "scan with very large data" {
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});
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
    const pattern: Pattern = try .parse("\\x00\\x01\\x02");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});
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
    const pattern: Pattern = try .parse("测试");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});
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
        try .parse("hello"),
        try .parse("world"),
    };
    const db: Database = try .compileMulti(&patterns, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});
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
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // Create multiple streams
    const stream1 = try db.openStream(.{});
    const stream2 = try db.openStream(.{});
    const stream3 = try db.openStream(.{});

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
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});
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
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});
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
        try .parse("hello"),
        try .parse("world"),
    };
    const db: Database = try .compileMulti(&patterns, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});
    defer stream.close(scratch, .{}) catch {};

    // Track matches and termination
    var matches: std.ArrayList(struct { id: u32, to: u64 }) = try .initCapacity(std.testing.allocator, 10);
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

// Compress and expand tests

test "compress stream" {
    // Parse a pattern for streaming
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // Open a stream
    const stream = try db.openStream(.{});
    defer stream.close(scratch, .{}) catch {};

    // Scan some data to change the stream state
    try stream.scan("some test data", scratch, .{});

    // Compress the stream
    const compressed = try stream.compress(std.testing.allocator);
    defer std.testing.allocator.free(compressed);

    // Verify compressed data is not empty
    try std.testing.expect(compressed.len > 0);
}

test "compress empty stream" {
    // Parse a pattern for streaming
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // Open a stream but don't scan anything
    const stream = try db.openStream(.{});
    defer stream.close(scratch, .{}) catch {};

    // Compress the empty stream
    const compressed = try stream.compress(std.testing.allocator);
    defer std.testing.allocator.free(compressed);

    // Verify compressed data is not empty (even empty streams have state)
    try std.testing.expect(compressed.len > 0);
}

test "expand stream" {
    // Parse a pattern for streaming
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // Open a stream and scan some data
    const original_stream = try db.openStream(.{});
    defer original_stream.close(scratch, .{}) catch {};

    try original_stream.scan("some te", scratch, .{});

    // Compress the original stream
    const compressed = try original_stream.compress(std.testing.allocator);
    defer std.testing.allocator.free(compressed);

    // Expand the compressed stream
    const expanded_stream = try expand(&db, compressed);
    defer expanded_stream.close(scratch, .{}) catch {};

    // Verify the expanded stream works correctly
    var match_count: u32 = 0;
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count,
    };

    // The expanded stream should have the same state as the original
    // Continue scanning from where the original left off
    try expanded_stream.scan("st", scratch, opts);
    try std.testing.expectEqual(1, match_count); // Should find "test" in "some test"
}

test "compress and expand with multiple patterns" {
    // Parse multiple patterns for streaming
    const patterns = [_]Pattern{
        try .parse("foobar"),
        try .parse("he[l]+o"),
    };
    const db: Database = try .compileMulti(&patterns, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // Open a stream and scan some data
    const original_stream = try db.openStream(.{});
    defer original_stream.close(scratch, .{}) catch {};

    // Verify the expanded stream works correctly
    var matches: std.ArrayList(u32) = try .initCapacity(std.testing.allocator, 10);
    defer matches.deinit(std.testing.allocator);

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(std.ArrayList(u32)).append(std.testing.allocator, evt.id) catch {};
            }
        }.handler,
        .context = &matches,
    };

    try original_stream.scan("hel", scratch, opts);

    // Compress the original stream
    const compressed = try original_stream.compress(std.testing.allocator);
    defer std.testing.allocator.free(compressed);

    // Expand the compressed stream
    const expanded_stream = try expand(&db, compressed);
    defer expanded_stream.close(scratch, opts) catch {};

    // The expanded stream should have the same state as the original
    // Continue scanning from where the original left off
    try expanded_stream.scan("lo", scratch, opts);
    try std.testing.expectEqual(1, matches.items.len);
    try std.testing.expectEqual(1, matches.items[0]); // Should find "world" pattern (id=1)
}

test "compress and expand round trip" {
    // Parse a pattern for streaming
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // Open a stream and scan some data
    const original_stream = try db.openStream(.{});
    defer original_stream.close(scratch, .{}) catch {};

    try original_stream.scan("some te", scratch, .{});

    // Compress the original stream
    const compressed = try original_stream.compress(std.testing.allocator);
    defer std.testing.allocator.free(compressed);

    // Expand the compressed stream
    const expanded_stream = try expand(&db, compressed);
    defer expanded_stream.close(scratch, .{}) catch {};

    // Test that both streams behave identically for the same input
    var original_matches: std.ArrayList(u64) = try .initCapacity(std.testing.allocator, 10);
    defer original_matches.deinit(std.testing.allocator);

    var expanded_matches: std.ArrayList(u64) = try .initCapacity(std.testing.allocator, 10);
    defer expanded_matches.deinit(std.testing.allocator);

    const original_opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch {};
            }
        }.handler,
        .context = &original_matches,
    };

    const expanded_opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch {};
            }
        }.handler,
        .context = &expanded_matches,
    };

    // Both streams should produce the same results for the same input
    try original_stream.scan("st data", scratch, original_opts);
    try expanded_stream.scan("st data", scratch, expanded_opts);

    try std.testing.expectEqualDeep(original_matches.items, expanded_matches.items);
}

test "expand with invalid data" {
    // Parse a pattern for streaming
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    // Try to expand with invalid data
    const invalid_data = [_]u8{ 0x00, 0x01, 0x02, 0x03 };
    try std.testing.expectError(error.Invalid, expand(&db, &invalid_data));
}

test "compress and expand with large stream state" {
    // Parse a pattern for streaming
    const pattern: Pattern = try .parse("f[o]+bar");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true, .som_horizon_large = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    var match_count: u32 = 0;
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count,
    };

    // Open a stream and scan a lot of data to create a large state
    const original_stream = try db.openStream(.{});
    defer original_stream.close(scratch, opts) catch {};

    try original_stream.scan("f", scratch, opts);

    // Create a large string with multiple "o" occurrences
    const buf = try std.testing.allocator.alloc(u8, 10000);
    defer std.testing.allocator.free(buf);

    @memset(buf, 'o');

    try original_stream.scan(buf, scratch, opts);

    // Compress the stream with large state
    const compressed = try original_stream.compress(std.testing.allocator);
    defer std.testing.allocator.free(compressed);

    // Verify compressed data is reasonable size
    try std.testing.expect(compressed.len > 0);
    try std.testing.expect(compressed.len < buf.len); // Should be compressed

    // Expand the compressed stream
    const expanded_stream = try expand(&db, compressed);
    defer expanded_stream.close(scratch, .{}) catch {};

    // Continue scanning from where the original left off
    try expanded_stream.scan("bar", scratch, opts);
    try std.testing.expectEqual(1, match_count);
}

// Reset and expand tests

test resetAndExpand {
    // Parse a pattern for streaming
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    var match_count: u32 = 0;
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count,
    };

    // Open a stream and scan some data
    const original_stream = try db.openStream(.{});
    defer original_stream.close(scratch, opts) catch {};

    try original_stream.scan("some te", scratch, opts);

    // Compress the original stream
    const compressed = try original_stream.compress(std.testing.allocator);
    defer std.testing.allocator.free(compressed);

    // Create a new stream for resetAndExpand
    var target_stream = try db.openStream(.{});
    defer target_stream.close(scratch, opts) catch {};

    // Scan some data to change the target stream state
    try target_stream.scan("different data", scratch, opts);

    // Reset and expand the compressed stream onto the target stream
    try target_stream.resetAndExpand(compressed, scratch, .{});

    // Continue scanning from where the original left off
    try target_stream.scan("st", scratch, opts);
    try std.testing.expectEqual(1, match_count); // Should find "test" in "more test"
}

test "resetAndExpand with EOD matches" {
    // Parse a pattern that requires EOD (end of data) to match
    const pattern: Pattern = try .parse("test$");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // Open a stream and scan partial data
    const original_stream = try db.openStream(.{});
    defer original_stream.close(scratch, .{}) catch {};

    try original_stream.scan("test", scratch, .{});

    // Compress the original stream
    const compressed = try original_stream.compress(std.testing.allocator);
    defer std.testing.allocator.free(compressed);

    // Create a new stream for resetAndExpand
    var target_stream = try db.openStream(.{});
    defer target_stream.close(scratch, .{}) catch {};

    try target_stream.scan("test", scratch, .{});

    // Track EOD matches during resetAndExpand
    var eod_matches: u32 = 0;
    const reset_opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &eod_matches,
    };

    // Reset and expand - may or may not report EOD matches depending on implementation
    try target_stream.resetAndExpand(compressed, scratch, reset_opts);
    try std.testing.expectEqual(1, eod_matches);

    // Verify the target stream now has the same state as the original
    var match_count: u32 = 0;
    const scan_opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count,
    };

    // Continue scanning from where the original left off
    try target_stream.scan("some data", scratch, scan_opts);
    try std.testing.expectEqual(0, match_count); // Should not find matches since pattern requires EOD
}

test "resetAndExpand with multiple patterns" {
    // Parse multiple patterns for streaming
    const patterns = [_]Pattern{
        try .parse("hello"),
        try .parse("world"),
    };
    const db: Database = try .compileMulti(&patterns, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    var matches: std.ArrayList(u32) = try .initCapacity(std.testing.allocator, 10);
    defer matches.deinit(std.testing.allocator);

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(std.ArrayList(u32)).append(std.testing.allocator, evt.id) catch {};
            }
        }.handler,
        .context = &matches,
    };

    // Open a stream and scan some data
    const original_stream = try db.openStream(.{});
    defer original_stream.close(scratch, opts) catch {};

    try original_stream.scan("foobar", scratch, opts);

    // Compress the original stream
    const compressed = try original_stream.compress(std.testing.allocator);
    defer std.testing.allocator.free(compressed);

    // Create a new stream for resetAndExpand
    var target_stream = try db.openStream(.{});
    defer target_stream.close(scratch, opts) catch {};

    // Scan some data to change the target stream state
    try target_stream.scan("hel", scratch, opts);

    // Reset and expand the compressed stream onto the target stream
    try target_stream.resetAndExpand(compressed, scratch, opts);

    // Continue scanning from where the original left off
    try target_stream.scan("lo world", scratch, opts);
    try std.testing.expectEqual(1, matches.items.len);
    try std.testing.expectEqual(1, matches.items[0]); // Should find "world" pattern (id=1)
}

test "resetAndExpand round trip" {
    // Parse a pattern for streaming
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // Open a stream and scan some data
    const original_stream = try db.openStream(.{});
    defer original_stream.close(scratch, .{}) catch {};

    const buf = "some test data";
    const first_part = buf[0..7];
    const second_part = buf[7..];

    try original_stream.scan(first_part, scratch, .{});

    // Compress the original stream
    const compressed = try original_stream.compress(std.testing.allocator);
    defer std.testing.allocator.free(compressed);

    // Create a new stream for resetAndExpand
    var target_stream = try db.openStream(.{});
    defer target_stream.close(scratch, .{}) catch {};

    // Scan some data to change the target stream state
    try target_stream.scan("different data", scratch, .{});

    // Reset and expand the compressed stream onto the target stream
    try target_stream.resetAndExpand(compressed, scratch, .{});

    // Test that the target stream behaves identically to the original for the same input
    var original_matches: std.ArrayList(u64) = try .initCapacity(std.testing.allocator, 10);
    defer original_matches.deinit(std.testing.allocator);

    var target_matches: std.ArrayList(u64) = try .initCapacity(std.testing.allocator, 10);
    defer target_matches.deinit(std.testing.allocator);

    const original_opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch {};
            }
        }.handler,
        .context = &original_matches,
    };

    const target_opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch {};
            }
        }.handler,
        .context = &target_matches,
    };

    // Both streams should produce the same results for the same input
    try original_stream.scan(second_part, scratch, original_opts);
    try target_stream.scan(second_part, scratch, target_opts);

    try std.testing.expectEqualDeep(original_matches.items, target_matches.items);
}

test "resetAndExpand with invalid data" {
    // Parse a pattern for streaming
    const pattern: Pattern = try .parse("test");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // Create a stream for resetAndExpand
    var target_stream = try db.openStream(.{});
    defer target_stream.close(scratch, .{}) catch {};

    // Try to resetAndExpand with invalid data
    const invalid_data = [_]u8{ 0x00, 0x01, 0x02, 0x03 };
    try std.testing.expectError(error.Invalid, target_stream.resetAndExpand(&invalid_data, scratch, .{}));
}

test "resetAndExpand with large stream state" {
    // Parse a pattern for streaming
    const pattern: Pattern = try .parse("f[o]+bar");
    const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true, .som_horizon_large = true } });
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    var match_count: u32 = 0;
    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: match.Event) !void {
                evt.data(u32).* += 1;
            }
        }.handler,
        .context = &match_count,
    };

    // Open a stream and scan a lot of data to create a large state
    const original_stream = try db.openStream(.{});
    defer original_stream.close(scratch, opts) catch {};

    try original_stream.scan("f", scratch, opts);

    // Create a large string with multiple "o" occurrences
    const buf = try std.testing.allocator.alloc(u8, 10000);
    defer std.testing.allocator.free(buf);

    @memset(buf, 'o');

    try original_stream.scan(buf, scratch, opts);

    // Compress the stream with large state
    const compressed = try original_stream.compress(std.testing.allocator);
    defer std.testing.allocator.free(compressed);

    // Verify compressed data is reasonable size
    try std.testing.expect(compressed.len > 0);
    try std.testing.expect(compressed.len < buf.len); // Should be compressed

    // Create a new stream for resetAndExpand
    var target_stream = try db.openStream(.{});
    defer target_stream.close(scratch, opts) catch {};

    // Scan some data to change the target stream state
    try target_stream.scan("different data", scratch, opts);

    // Reset and expand the compressed stream onto the target stream
    try target_stream.resetAndExpand(compressed, scratch, opts);

    // Continue scanning from where the original left off
    try target_stream.scan("bar", scratch, opts);
    try std.testing.expectEqual(1, match_count);
}
