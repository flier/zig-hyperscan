//! A Hyperscan pattern database.

const std = @import("std");
const Allocator = std.mem.Allocator;

const cString = @cImport({
    @cInclude("string.h");
});

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const common = @import("common.zig");
const compile_ = @import("compile.zig");
const scan = @import("scan.zig");
const Scratch = @import("scratch.zig");
const Stream = @import("stream.zig");

pub const CompileOptions = compile_.CompileOptions;
pub const ScanOptions = scan.Options;
pub const Mode = compile_.Mode;

pub const Database = @This();

db: *const hs.hs_database_t,
mode: Mode,
alloc: hs.hs_alloc_t = null,
free: hs.hs_free_t = null,

/// Free a compiled pattern database.
pub fn deinit(self: *Database) !void {
    try common.check(hs.hs_free_database(self.db));

    self.db = null;
}

/// Utility function providing information about a database.
pub fn info(self: *const Database, allocator: Allocator) ![]const u8 {
    var db_info: ?[*]u8 = null;

    try common.check(hs.hs_database_info(self.db, &db_info));
    defer std.c.free(db_info);

    return if (db_info) |p|
        allocator.dupe(u8, p[0..cString.strlen(p)])
    else
        error.UnknownError;
}

/// Provides the size of the given database in bytes.
pub fn size(self: *const Database) !usize {
    var sz: usize = 0;

    try common.check(hs.hs_database_size(self.db, &sz));

    return sz;
}

/// The basic regular expression compiler.
pub fn compile(expr: []const u8, opts: CompileOptions) !Database {
    const db = try compile_.compile(expr, opts);

    return Database{
        .db = @ptrCast(db),
        .mode = opts.mode,
    };
}

/// Allocate a "scratch" space for use by Hyperscan.
pub fn alloc_scratch(self: *const Database) !Scratch {
    return Scratch.alloc(@ptrCast(self.db));
}

/// The block (non-streaming) regular expression scanner.
pub fn scan_block(self: *const Database, data: []const u8, scratch: Scratch, opts: scan.Options) !void {
    return scan.scan_block(@ptrCast(self.db), data, scratch, opts);
}

/// The vectored regular expression scanner.
pub fn scan_vector(self: *const Database, data: []const std.posix.iovec_const, scratch: Scratch, opts: scan.Options) !void {
    return scan.scan_vector(@ptrCast(self.db), data, scratch, opts);
}

/// Open and initialise a stream.
pub fn open_stream(self: *const Database, opts: Stream.OpenOptions) !Stream {
    return Stream.open(@ptrCast(self.db), opts);
}
