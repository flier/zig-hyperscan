const std = @import("std");

const hs = @cImport(@cInclude("hs/hs.h"));

/// A type for event details passed to the event handler.
///
/// Contains information about a match found during scanning, including the
/// pattern ID, match offsets, and user context.
pub const Event = struct {
    /// The ID number of the expression that matched.
    ///
    /// This corresponds to the pattern ID specified during compilation,
    /// or the index in the patterns array for multi-pattern compilation.
    id: u32,
    /// The offset of the first byte that matches the expression.
    ///
    /// - If a start of match flag is enabled for the current pattern,
    /// this argument will be set to the start of match for the pattern assuming
    /// that that start of match value lies within the current 'start of match horizon' chosen by one of the SOM_HORIZON mode flags.
    /// - If the start of match value lies outside this horizon
    /// (possible only when the SOM_HORIZON value is not `HS_MODE_SOM_HORIZON_LARGE`),
    /// the `from` value will be set to `null`.
    /// - This argument will be set to zero if the Start of Match flag is not enabled for the given pattern.
    from: ?u64,
    /// The offset after the last byte that matches the expression.
    ///
    /// This is the position immediately after the last character of the match.
    to: u64,
    /// This is provided for future use and is unused at present.
    flags: u32 = 0,
    /// The pointer supplied by the user to the `scan`, `scan_vector` or `scan_stream` function.
    ///
    /// This allows the event handler to access user-defined context data.
    context: ?*anyopaque = null,

    /// Returns true if the start of match offset is past the horizon.
    ///
    /// This indicates that the start of match information is not available
    /// due to horizon limitations in the SOM (Start of Match) tracking.
    ///
    /// ## Returns
    /// `true` if the start offset is past the horizon, `false` otherwise.
    pub fn isStartOffsetPastHorizon(self: Event) bool {
        return self.from == null;
    }

    /// Returns the data pointer stored in the event context.
    ///
    /// Safely casts the context pointer to the specified type.
    ///
    /// ## Arguments
    /// - `T`: The type to cast the context to
    ///
    /// ## Returns
    /// A pointer to the context data cast to the specified type.
    ///
    /// # Safety
    /// The caller must ensure that the context actually contains data of type `T`.
    pub fn data(self: *const Event, comptime T: type) *T {
        return @ptrCast(@alignCast(self.context));
    }
};

test Event {
    const num: i32 = 123;

    const evt = Event{
        .id = 0,
        .from = null,
        .to = 0,
        .context = @constCast(&num),
    };

    try std.testing.expect(evt.isStartOffsetPastHorizon());
    try std.testing.expectEqual(&num, evt.data(i32));
}

/// An error type for the event handler.
///
/// Defines errors that can be returned from event handlers to control
/// the scanning process.
pub const Error = error{
    /// The scanning should terminate.
    ///
    /// Return this error from an event handler to stop the scanning process
    /// immediately. This is useful when you've found what you're looking for
    /// and don't need to continue scanning.
    Terminate,
};

/// A callback function that will be invoked whenever a match is located in the target data during the execution of a scan.
///
/// The callback function should return a value indicating whether or not matching should continue on the target data.
/// If no callbacks are desired from a scan call, null may be provided in order to suppress match production.
///
/// ## Arguments
/// - `event`: The match event containing details about the match found
///
/// ## Returns
/// - `void`: Continue scanning
/// - `error.Terminate`: Stop scanning immediately
///
/// ## Example
/// ```zig
/// fn onMatch(event: MatchEvent) !void {
///     std.log.info("Match found: pattern {d} at offset {d} to {d}", .{ event.id, event.from, event.to });
///
///     // Stop scanning after first match
///     if (event.id == 0) {
///         return error.Terminate;
///     }
/// }
/// ```
pub const EventHandler = ?*const fn (Event) Error!void;

/// A context for the event handler.
pub const Context = struct {
    /// The trampoline function that will be invoked by the Hyperscan library.
    trampoline: hs.match_event_handler,
    /// The user defined event handler.
    handler: EventHandler,
    /// The user defined pointer which will be passed to the event handler.
    context: ?*anyopaque,

    /// Initializes a new event handler context.
    ///
    /// ## Arguments
    /// - `handler`: The event handler to use
    /// - `context`: The user defined pointer which will be passed to the event handler
    ///
    /// ## Returns
    /// A new event handler context.
    ///
    /// ## Example
    /// ```zig
    /// const context = Context.init(onMatch, null);
    /// ```
    pub fn init(handler: EventHandler, context: ?*anyopaque) Context {
        return .{
            .trampoline = if (handler) |_| &onEvent else null,
            .handler = handler,
            .context = context,
        };
    }
};

/// The event handler callback function.
fn onEvent(id: c_uint, from: c_ulonglong, to: c_ulonglong, flags: c_uint, context: ?*anyopaque) callconv(.c) c_int {
    std.debug.assert(context != null);

    const ctx: *Context = @ptrCast(@alignCast(context));

    if (ctx.handler) |handler| {
        const res = handler(.{
            .id = id,
            .from = if (from == hs.HS_OFFSET_PAST_HORIZON) null else from,
            .to = to,
            .flags = flags,
            .context = ctx.context,
        });

        if (res) |_| {
            return 0;
        } else |_| {
            return -1;
        }
    }

    return 0;
}

// Unit tests

test onEvent {
    const empty: Context = .init(null, null);

    try std.testing.expectEqual(0, onEvent(0, 0, 0, 0, @constCast(&empty)));

    const terminate: Context = .init(struct {
        fn handler(_: Event) !void {
            return error.Terminate;
        }
    }.handler, null);

    try std.testing.expectEqual(-1, onEvent(0, 0, 0, 0, @constCast(&terminate)));
}
