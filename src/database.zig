//! A Hyperscan pattern database.

const std = @import("std");
const Allocator = std.mem.Allocator;

const cString = @cImport({
    @cInclude("string.h");
});

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const check = @import("error.zig").check;

const compile_ = @import("compile.zig");

pub const CompileOptions = compile_.CompileOptions;
pub const Mode = compile_.Mode;
pub const Pattern = compile_.Pattern;

const scan = @import("scan.zig");

pub const ScanOptions = scan.Options;

const Scratch = @import("scratch.zig");
const Stream = @import("stream.zig");

pub const Database = @This();

ptr: *const hs.hs_database_t,
mode: Mode,

/// The basic regular expression compiler.
pub fn compile(pattern: *const Pattern, opts: CompileOptions) !Database {
    const db = try compile_.compile(pattern, opts);

    return Database{
        .ptr = @ptrCast(db),
        .mode = opts.mode,
    };
}

///  The multiple regular expression compiler.
pub fn compile_multi(patterns: []const Pattern, opts: CompileOptions) !Database {
    const db = try compile_.compile_multi(patterns, opts);

    return Database{
        .ptr = @ptrCast(db),
        .mode = opts.mode,
    };
}

/// Free a compiled pattern database.
pub fn deinit(self: *const Database) void {
    check(hs.hs_free_database(@constCast(self.ptr))) catch |e| {
        std.log.err("deinit database: {s}", .{@errorName(e)});
    };
}

/// Utility function providing information about a database.
pub fn info(self: *const Database, allocator: Allocator) ![]const u8 {
    var db_info: ?[*]u8 = null;

    try check(hs.hs_database_info(self.ptr, &db_info));
    defer std.c.free(db_info);

    return if (db_info) |p|
        allocator.dupe(u8, p[0..cString.strlen(p)])
    else
        error.UnknownError;
}

/// Provides the size of the given database in bytes.
pub fn size(self: *const Database) !usize {
    var sz: usize = 0;

    try check(hs.hs_database_size(self.ptr, &sz));

    return sz;
}

/// Allocate a "scratch" space for use by Hyperscan.
pub fn alloc_scratch(self: *const Database) !Scratch {
    return Scratch.alloc(@ptrCast(self.ptr));
}

/// The block (non-streaming) regular expression scanner.
pub fn scan_block(self: *const Database, data: []const u8, scratch: Scratch, opts: scan.Options) !void {
    return scan.scan_block(@ptrCast(self.ptr), data, scratch, opts);
}

/// The vectored regular expression scanner.
pub fn scan_vector(self: *const Database, data: []const std.posix.iovec_const, scratch: Scratch, opts: scan.Options) !void {
    return scan.scan_vector(@ptrCast(self.ptr), data, scratch, opts);
}

/// Provides the size of the stream state allocated by a single stream opened against the given database.
pub fn stream_size(self: *const Database) !usize {
    var sz: usize = 0;

    try check(hs.hs_stream_size(self.ptr, &sz));

    return sz;
}

/// Open and initialise a stream.
pub fn open_stream(self: *const Database, opts: Stream.OpenOptions) !Stream {
    return Stream.open(@ptrCast(self.ptr), opts);
}
