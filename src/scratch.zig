//! A Hyperscan scratch space.

const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const common = @import("common.zig");

const Scratch = @This();

scratch: *hs.hs_scratch_t,

/// Allocate a "scratch" space for use by Hyperscan.
pub fn alloc(db: *const hs.hs_database_t) !Scratch {
    var scratch: ?*hs.hs_scratch_t = null;

    try common.check(hs.hs_alloc_scratch(db, &scratch));

    return if (scratch) |s| Scratch{
        .scratch = @ptrCast(s),
    } else error.UnknownError;
}

/// Allocate a scratch space that is a clone of an existing scratch space.
pub fn clone(self: *const Scratch) !Scratch {
    var scratch: ?*hs.hs_scratch_t = null;

    try common.check(hs.hs_clone_scratch(self.scratch, &scratch));

    return Scratch{
        .scratch = scratch,
    };
}

/// Provides the size of the given scratch space.
pub fn size(self: *const Scratch) !usize {
    var sz: usize = 0;

    try common.check(hs.hs_scratch_size(self.scratch, &sz));

    return sz;
}

/// Free a scratch block previously allocated by `alloc` or `clone`.
pub fn deinit(self: *const Scratch) void {
    common.check(hs.hs_free_scratch(self.scratch)) catch |e| {
        std.log.err("free scratch: {s}", .{@errorName(e)});
    };
}
