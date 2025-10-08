const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const common = @import("common.zig");

pub const Scratch = @import("scratch.zig");

pub const ScanOptions = struct {
    flags: u32 = 0,
    scratch: Scratch,
    onEvent: hs.match_event_handler = null,
    context: ?*anyopaque = null,
};

pub fn scan_block(db: *const hs.hs_database_t, data: []const u8, opts: ScanOptions) !void {
    return common.check(hs.hs_scan(db, data.ptr, @intCast(data.len), opts.flags, @ptrCast(opts.scratch.scratch), opts.onEvent, opts.context));
}

pub fn scan_vector(db: *const hs.hs_database_t, data: []const std.posix.iovec_const, opts: ScanOptions) !void {
    var ptrs: [data.len]*const u8 = undefined;
    var lens: [data.len]u32 = undefined;

    for (data, 0..) |iovec, i| {
        ptrs[i] = iovec.iov_base;
        lens[i] = iovec.iov_len;
    }

    return common.check(hs.hs_scan_vector(db, ptrs.ptr, lens.ptr, @intCast(data.len), opts.flags, @ptrCast(opts.scratch.scratch), opts.onEvent, opts.context));
}
