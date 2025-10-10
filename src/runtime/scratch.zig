//! A Hyperscan scratch space.

const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const check = @import("../common.zig").check;

const Scratch = @This();

ptr: *hs.hs_scratch_t,

/// Allocate a "scratch" space for use by Hyperscan.
pub fn alloc(db: *const hs.hs_database_t) !Scratch {
    var scratch: ?*hs.hs_scratch_t = null;

    try check(hs.hs_alloc_scratch(db, &scratch));

    return if (scratch) |s| Scratch{
        .ptr = @ptrCast(s),
    } else error.UnknownError;
}

/// Allocate a scratch space that is a clone of an existing scratch space.
pub fn clone(self: *const Scratch) !Scratch {
    var scratch: ?*hs.hs_scratch_t = null;

    try check(hs.hs_clone_scratch(self.ptr, &scratch));

    return Scratch{
        .ptr = scratch,
    };
}

/// Provides the size of the given scratch space.
pub fn size(self: *const Scratch) !usize {
    var sz: usize = 0;

    try check(hs.hs_scratch_size(self.ptr, &sz));

    return sz;
}

/// Free a scratch block previously allocated by `alloc` or `clone`.
pub fn deinit(self: *const Scratch) void {
    check(hs.hs_free_scratch(self.ptr)) catch |e| {
        std.log.err("free scratch: {s}", .{@errorName(e)});
    };
}
