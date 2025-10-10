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

fn testHandler(evt: match.Event) !void {
    evt.setData(u64, evt.to);
}

/// Write data to be scanned to the opened stream.
pub fn scan(self: *const Stream, data: []const u8, scratch: Scratch, opts: ScanOptions) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_scan_stream(self.stream_id, data.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
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
        .onEvent = testHandler,
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

/// Close a stream.
pub fn close(self: *const Stream, scratch: Scratch, opts: ScanOptions) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_close_stream(self.stream_id, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
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
        .onEvent = testHandler,
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

/// Reset a stream to an initial state.
pub fn reset(self: *const Stream, scratch: Scratch, opts: ScanOptions) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_reset_stream(self.stream_id, opts.flags, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
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
        .onEvent = testHandler,
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
        .onEvent = testHandler,
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

/// Duplicate the given stream state onto a new stream.
///
/// The new stream will first be reset
/// (reporting any EOD matches if a non-NULL @p onEvent callback handler is provided).
pub fn reset_and_copy(self: *const Stream, to: *Stream, scratch: Scratch, opts: ScanOptions) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_reset_and_copy_stream(to.stream_id, self.stream_id, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
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
        .onEvent = testHandler,
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
