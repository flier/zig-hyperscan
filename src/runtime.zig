const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const common = @import("common.zig");

pub const Scratch = @import("scratch.zig");

pub const MatchAction = enum(c_int) {
    Continue = 0,
    Terminate = 1,
};

pub const MatchStartOffsetPastHorizon = hs.HS_OFFSET_PAST_HORIZON;

pub const MatchEvent = struct {
    /// The ID number of the expression that matched.
    id: u32,
    /// The offset of the first byte that matches the expression.
    ///
    /// - If a start of match flag is enabled for the current pattern,
    /// this argument will be set to the start of match for the pattern assuming
    /// that that start of match value lies within the current 'start of match horizon' chosen by one of the SOM_HORIZON mode flags.
    /// - If the start of match value lies outside this horizon
    /// (possible only when the SOM_HORIZON value is not `HS_MODE_SOM_HORIZON_LARGE`),
    /// the `from` value will be set to `MatchStartOffsetPostHorizon`.
    /// - This argument will be set to zero if the Start of Match flag is not enabled for the given pattern.
    from: u64,
    /// The offset after the last byte that matches the expression.
    to: u64,
    /// This is provided for future use and is unused at present.
    flags: u32,
    /// The pointer supplied by the user to the `scan`, `scan_vector` or `scan_stream` function.
    context: ?*anyopaque,

    pub fn isStartOffsetPastHorizon(self: MatchEvent) bool {
        return self.from == MatchStartOffsetPastHorizon;
    }
};

/// A callback function that will be invoked whenever a match is located in the target data during the execution of a scan.
/// The callback function should return a value indicating whether or not matching should continue on the target data.
/// If no callbacks are desired from a scan call, null may be provided in order to suppress match production.
pub const MatchEventHandler = ?*const fn (MatchEvent) MatchAction;

pub const ScanOptions = struct {
    flags: u32 = 0,
    scratch: Scratch,
    onEvent: ?MatchEventHandler = null,
    context: ?*anyopaque = null,
};

pub fn scan_block(db: *const hs.hs_database_t, data: []const u8, opts: ScanOptions) !void {
    var onEvent: hs.match_event_handler = null;
    var context: ?*anyopaque = null;

    if (opts.onEvent) |h| {
        const ctx = MatchContext{
            .handler = h,
            .context = opts.context,
        };

        onEvent = &onMatchEvent;
        context = @constCast(&ctx);
    }

    return common.check(hs.hs_scan(db, data.ptr, @intCast(data.len), opts.flags, @ptrCast(opts.scratch.scratch), onEvent, context));
}

pub fn scan_vector(db: *const hs.hs_database_t, data: []const std.posix.iovec_const, opts: ScanOptions) !void {
    var ptrs: [data.len]*const u8 = undefined;
    var lens: [data.len]u32 = undefined;

    for (data, 0..) |iovec, i| {
        ptrs[i] = iovec.iov_base;
        lens[i] = iovec.iov_len;
    }

    var onEvent: hs.match_event_handler = null;
    var context: ?*anyopaque = null;

    if (opts.onEvent) |h| {
        const ctx = MatchContext{
            .handler = h,
            .context = opts.context,
        };

        onEvent = &onMatchEvent;
        context = @constCast(&ctx);
    }

    return common.check(hs.hs_scan_vector(db, ptrs.ptr, lens.ptr, @intCast(data.len), opts.flags, @ptrCast(opts.scratch.scratch), onEvent, context));
}

const MatchContext = struct {
    handler: MatchEventHandler,
    context: ?*anyopaque = null,
};

fn onMatchEvent(id: c_uint, from: c_ulonglong, to: c_ulonglong, flags: c_uint, context: ?*anyopaque) callconv(.c) c_int {
    const ctx: *MatchContext = @ptrCast(@alignCast(context));

    if (ctx.handler) |handler| {
        return @intFromEnum(handler(MatchEvent{
            .id = id,
            .from = from,
            .to = to,
            .flags = flags,
            .context = ctx.context,
        }));
    }

    return 0;
}
