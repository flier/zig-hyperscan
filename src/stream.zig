//! A Hyperscan scanning stream.

const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const common = @import("common.zig");
const match = @import("match.zig");
const scan_ = @import("scan.zig");

const Scratch = @import("scratch.zig");

const ScanOptions = scan_.Options;
pub const Stream = @This();

id: *hs.hs_stream_t,

pub const OpenOptions = struct {
    flags: u32 = 0,
};

/// Open and initialise a stream.
pub fn open(db: *const hs.hs_database_t, opts: OpenOptions) !Stream {
    var stream_id: ?*hs.hs_stream_t = null;

    try common.check(hs.hs_open_stream(db, opts.flags, &stream_id));

    return if (stream_id) |id| Stream{
        .id = id,
    } else error.UnknownError;
}

/// Write data to be scanned to the opened stream.
pub fn scan(self: *const Stream, data: []const u8, opts: ScanOptions) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return common.check(hs.hs_scan_stream(self.id, data.ptr, @intCast(data.len), opts.flags, @ptrCast(opts.scratch.scratch), ctx.onEvent, @constCast(&ctx)));
}

/// Close a stream.
pub fn close(self: *const Stream, opts: ScanOptions) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return common.check(hs.hs_close_stream(self.id, @ptrCast(opts.scratch.scratch), ctx.onEvent, @constCast(&ctx)));
}

/// Reset a stream to an initial state.
pub fn reset(self: *const Stream, opts: ScanOptions) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return common.check(hs.hs_reset_stream(self.id, opts.flags, @ptrCast(opts.scratch.scratch), ctx.onEvent, @constCast(&ctx)));
}

/// Duplicate the given stream.
///
/// The new stream will have the same state as the original including the current stream offset.
pub fn copy(self: *const Stream) !Stream {
    const stream_id: ?*hs.hs_stream_t = null;

    try common.check(hs.hs_copy_stream(stream_id, self.id));

    return Stream{
        .id = stream_id,
    };
}

/// Duplicate the given stream state onto a new stream.
///
/// The new stream will first be reset
/// (reporting any EOD matches if a non-NULL @p onEvent callback handler is provided).
pub fn reset_and_copy(self: *const Stream, opts: ScanOptions) !void {
    const stream_id: ?*hs.hs_stream_t = null;
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return common.check(hs.hs_reset_and_copy_stream(&stream_id, self.id, @ptrCast(opts.scratch.scratch), ctx.onEvent, @constCast(&ctx)));
}
