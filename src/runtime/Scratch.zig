//! A Hyperscan scratch space.

const std = @import("std");

const hs = @cImport(@cInclude("hs/hs.h"));

const Database = @import("../common.zig").Database;
const Pattern = @import("../compile.zig").Pattern;

const check = @import("../common.zig").check;

const Scratch = @This();

ptr: *hs.hs_scratch_t,

/// Allocate a "scratch" space for use by Hyperscan.
///
/// Allocates scratch space that is required for scanning operations with the given database.
/// The scratch space contains temporary state and should be reused across multiple
/// scan operations for better performance.
///
/// ## Arguments
/// - `db`: The database to allocate scratch space for
///
/// ## Returns
/// A `Scratch` object that can be used for scanning, or an error if allocation fails.
///
/// ## Example
/// ```zig
/// const db = try Database.compile(&pattern, .{});
/// defer db.deinit();
///
/// const scratch = try Scratch.alloc(&db);
/// defer scratch.deinit();
/// ```
pub fn alloc(db: *const Database) !Scratch {
    var scratch: ?*hs.hs_scratch_t = null;

    try check(hs.hs_alloc_scratch(@ptrCast(db.ptr), &scratch));

    return if (scratch) |s| .{
        .ptr = s,
    } else error.UnknownError;
}

/// Reallocate a "scratch" space for use with a different database.
///
/// Reallocates the existing scratch space to work with a different database.
/// This is more efficient than deallocating and reallocating when switching
/// between databases that require similar scratch space sizes.
///
/// ## Arguments
/// - `self`: The scratch space to reallocate
/// - `db`: The new database to allocate scratch space for
///
/// ## Returns
/// An error if reallocation fails.
///
/// ## Example
/// ```zig
/// const db1 = try Database.compile(&pattern1, .{});
/// defer db1.deinit();
///
/// var scratch = try Scratch.alloc(&db1);
/// defer scratch.deinit();
///
/// const db2 = try Database.compile(&pattern2, .{});
/// defer db2.deinit();
///
/// try scratch.realloc(&db2);
/// ```
pub fn realloc(self: *Scratch, db: *const Database) !void {
    try check(hs.hs_alloc_scratch(@ptrCast(db.ptr), @ptrCast(&self.ptr)));
}

/// Allocate a scratch space that is a clone of an existing scratch space.
///
/// Creates a new scratch space that is a copy of the existing one. This is useful
/// for parallel scanning operations where multiple threads need their own scratch space.
///
/// ## Arguments
/// - `self`: The scratch space to clone
///
/// ## Returns
/// A new `Scratch` object that is a copy of the original, or an error if cloning fails.
///
/// ## Example
/// ```zig
/// const scratch1 = try Scratch.alloc(&db);
/// defer scratch1.deinit();
///
/// const scratch2 = try scratch1.clone();
/// defer scratch2.deinit();
/// ```
pub fn clone(self: *const Scratch) !Scratch {
    var scratch: ?*hs.hs_scratch_t = null;

    try check(hs.hs_clone_scratch(self.ptr, &scratch));

    return if (scratch) |ptr| .{
        .ptr = ptr,
    } else error.UnknownError;
}

/// Provides the size of the given scratch space.
///
/// Returns the total memory size of the scratch space, which can be useful
/// for monitoring memory usage or debugging.
///
/// ## Arguments
/// - `self`: The scratch space to get the size of
///
/// ## Returns
/// The size of the scratch space in bytes, or an error if the operation fails.
///
/// ## Example
/// ```zig
/// const scratch = try Scratch.alloc(&db);
/// defer scratch.deinit();
///
/// const scratch_size = try scratch.size();
/// std.log.info("Scratch space size: {} bytes", .{scratch_size});
/// ```
pub fn size(self: *const Scratch) !usize {
    var sz: usize = 0;

    try check(hs.hs_scratch_size(self.ptr, &sz));

    return sz;
}

/// Free a scratch block previously allocated by `alloc` or `clone`.
///
/// Releases all memory associated with the scratch space. This should be called
/// when the scratch space is no longer needed to prevent memory leaks.
///
/// ## Arguments
/// - `self`: The scratch space to free
///
/// ## Example
/// ```zig
/// const scratch = try Scratch.alloc(&db);
/// defer scratch.deinit(); // Free the scratch space when done
///
/// // Use the scratch space...
/// ```
pub fn deinit(self: *const Scratch) void {
    check(hs.hs_free_scratch(self.ptr)) catch |e| {
        std.log.err("free scratch: {s}", .{@errorName(e)});
    };
}

// Unit tests

test alloc {
    const pattern: Pattern = try .parse("foo");
    const db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    const scratch = try alloc(&db);
    defer scratch.deinit();

    try std.testing.expect(try scratch.size() >= 1000);
}

test realloc {
    const foo: Pattern = try .parse("foo");
    const db: Database = try .compile(&foo, .{});
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const scratch_size = try scratch.size();

    const foobar: Pattern = try .parse("foobar");
    const db2: Database = try .compile(&foobar, .{});
    defer db2.deinit();

    try scratch.realloc(&db2);

    try std.testing.expect(try scratch.size() >= scratch_size);
}

test clone {
    const foo: Pattern = try .parse("foo");
    const db: Database = try .compile(&foo, .{});
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    const scratch2 = try scratch.clone();
    defer scratch2.deinit();

    try std.testing.expectEqual(try scratch.size(), try scratch2.size());
}

test size {
    const foo: Pattern = try .parse("foo");
    const db: Database = try .compile(&foo, .{});
    defer db.deinit();

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    try std.testing.expect(try scratch.size() >= 1000);
}
