const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const common = @import("common.zig");
const match = @import("match.zig");

pub const Scratch = @import("scratch.zig");

pub const Options = struct {
    flags: u32 = 0,
    onEvent: match.EventHandler = null,
    context: ?*anyopaque = null,
};

pub fn scan_block(db: *const hs.hs_database_t, data: []const u8, scratch: Scratch, opts: Options) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return common.check(hs.hs_scan(db, data.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.scratch), ctx.onEvent, @constCast(&ctx)));
}

pub fn scan_vector(db: *const hs.hs_database_t, data: []const std.posix.iovec_const, scratch: Scratch, opts: Options) !void {
    var ptrs: [data.len]*const u8 = undefined;
    var lens: [data.len]u32 = undefined;

    for (data, 0..) |iovec, i| {
        ptrs[i] = iovec.iov_base;
        lens[i] = iovec.iov_len;
    }

    const ctx = match.Context.init(opts.onEvent, opts.context);

    return common.check(hs.hs_scan_vector(db, ptrs.ptr, lens.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.scratch), ctx.onEvent, @constCast(&ctx)));
}
