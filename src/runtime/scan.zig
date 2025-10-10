const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const match = @import("match.zig");
const Scratch = @import("scratch.zig");

const Pattern = @import("../compile.zig").Pattern;
const Database = @import("../common.zig").Database;

const check = @import("../common.zig").check;

/// Scan options.
pub const Options = struct {
    /// The allocator to use for the scan.
    allocator: std.mem.Allocator = std.heap.c_allocator,
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
pub fn scan_block(db: *const Database, data: []const u8, scratch: Scratch, opts: Options) !void {
    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_scan(@ptrCast(db.ptr), data.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
}

test scan_block {
    const pattern = try Pattern.parse("f[o]+");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    var to: u64 = 0;

    try scan_block(&db, "hello foobar", scratch, .{
        .onEvent = testHandler,
        .context = &to,
    });

    try std.testing.expectEqual(9, to);
}

fn testHandler(evt: match.Event) !void {
    evt.setData(u64, evt.to);
}

/// The vectored regular expression scanner.
pub fn scan_vector(db: *const Database, data: []const std.posix.iovec_const, scratch: Scratch, opts: Options) !void {
    var ptrs = try std.ArrayList(*const u8).initCapacity(opts.allocator, data.len);
    var lens = try std.ArrayList(u32).initCapacity(opts.allocator, data.len);

    defer ptrs.deinit(opts.allocator);
    defer lens.deinit(opts.allocator);

    for (data) |buf| {
        try ptrs.append(opts.allocator, @ptrCast(buf.base));
        try lens.append(opts.allocator, @intCast(buf.len));
    }

    const ctx = match.Context.init(opts.onEvent, opts.context);

    return check(hs.hs_scan_vector(@ptrCast(db.ptr), ptrs.items.ptr, lens.items.ptr, @intCast(data.len), opts.flags, @ptrCast(scratch.ptr), ctx.onEvent, @constCast(&ctx)));
}

test scan_vector {
    const pattern = try Pattern.parse("f[o]+");
    const db = try Database.compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello", .len = 5 },
        .{ .base = "foobar", .len = 6 },
    };

    var to: u64 = 0;

    try scan_vector(&db, data[0..data.len], scratch, .{
        .onEvent = testHandler,
        .context = &to,
    });

    try std.testing.expectEqual(8, to);
}
