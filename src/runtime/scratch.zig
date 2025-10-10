//! A Hyperscan scratch space.

const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const Database = @import("../common.zig").Database;
const Pattern = @import("../compile.zig").Pattern;

const check = @import("../common.zig").check;

const Scratch = @This();

ptr: *hs.hs_scratch_t,

/// Allocate a "scratch" space for use by Hyperscan.
pub fn alloc(db: *const Database) !Scratch {
    var scratch: ?*hs.hs_scratch_t = null;

    try check(hs.hs_alloc_scratch(@ptrCast(db.ptr), &scratch));

    return if (scratch) |s| Scratch{
        .ptr = s,
    } else error.UnknownError;
}

/// Reallocate a "scratch" space for use with a different database.
pub fn realloc(self: *Scratch, db: *const Database) !void {
    try check(hs.hs_alloc_scratch(@ptrCast(db.ptr), @ptrCast(&self.ptr)));
}

/// Allocate a scratch space that is a clone of an existing scratch space.
pub fn clone(self: *const Scratch) !Scratch {
    var scratch: ?*hs.hs_scratch_t = null;

    try check(hs.hs_clone_scratch(self.ptr, &scratch));

    return if (scratch) |ptr| Scratch{
        .ptr = ptr,
    } else error.UnknownError;
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

// Unit tests

test alloc {
    const pattern = try Pattern.parse("foo");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const scratch = try alloc(&db);
    defer scratch.deinit();

    try std.testing.expect(try scratch.size() >= 1000);
}

test realloc {
    const foo = try Pattern.parse("foo");
    const db = try Database.compile(&foo, .{});
    defer db.deinit();

    var scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const scratch_size = try scratch.size();

    const foobar = try Pattern.parse("foobar");
    const db2 = try Database.compile(&foobar, .{});
    defer db2.deinit();

    try scratch.realloc(&db2);

    try std.testing.expect(try scratch.size() >= scratch_size);
}

test clone {
    const foo = try Pattern.parse("foo");
    const db = try Database.compile(&foo, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const scratch2 = try scratch.clone();
    defer scratch2.deinit();

    try std.testing.expectEqual(try scratch.size(), try scratch2.size());
}

test size {
    const foo = try Pattern.parse("foo");
    const db = try Database.compile(&foo, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    try std.testing.expect(try scratch.size() >= 1000);
}
