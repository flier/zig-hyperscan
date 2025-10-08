const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

pub const Action = enum(c_int) {
    Continue = 0,
    Terminate = 1,
};

pub const StartOffsetPastHorizon = hs.HS_OFFSET_PAST_HORIZON;

pub const Event = struct {
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

    pub fn isStartOffsetPastHorizon(self: Event) bool {
        return self.from == StartOffsetPastHorizon;
    }
};

/// A callback function that will be invoked whenever a match is located in the target data during the execution of a scan.
/// The callback function should return a value indicating whether or not matching should continue on the target data.
/// If no callbacks are desired from a scan call, null may be provided in order to suppress match production.
pub const EventHandler = ?*const fn (Event) Action;

pub const Context = struct {
    onEvent: hs.match_event_handler = null,
    handler: EventHandler,
    context: ?*anyopaque = null,

    pub fn init(handler: EventHandler, context: ?*anyopaque) Context {
        return Context{
            .onEvent = if (handler) |_| &onEvent else null,
            .handler = handler,
            .context = context,
        };
    }
};

fn onEvent(id: c_uint, from: c_ulonglong, to: c_ulonglong, flags: c_uint, context: ?*anyopaque) callconv(.c) c_int {
    const ctx: *Context = @ptrCast(@alignCast(context));

    if (ctx.handler) |handler| {
        return @intFromEnum(handler(Event{
            .id = id,
            .from = from,
            .to = to,
            .flags = flags,
            .context = ctx.context,
        }));
    }

    return 0;
}
