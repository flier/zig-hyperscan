const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const match = @import("match.zig");
const Scratch = @import("scratch.zig");

const check = @import("../common.zig").check;

/// Scan options.
pub const Options = struct {
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
pub fn scan_block(db: *const hs.hs_database_t, data: []const u8, scratch: Scratch, opts: Options) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_scan(db, data.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
}

/// The vectored regular expression scanner.
pub fn scan_vector(db: *const hs.hs_database_t, data: []const std.posix.iovec_const, scratch: Scratch, opts: Options) !void {
    var ptrs: [data.len]*const u8 = undefined;
    var lens: [data.len]u32 = undefined;

    for (data, 0..) |iovec, i| {
        ptrs[i] = iovec.iov_base;
        lens[i] = iovec.iov_len;
    }

    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_scan_vector(db, ptrs.ptr, lens.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
}
