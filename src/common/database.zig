//! A Hyperscan pattern database.

const std = @import("std");
const Allocator = std.mem.Allocator;

const cString = @cImport({
    @cInclude("string.h");
});

const hs = @cImport({
    @cInclude("hs/hs.h");
});

const Serialized = @import("serialized.zig");

const compile_ = @import("../compile.zig");

pub const CompileOptions = compile_.Options;
pub const Mode = compile_.Mode;
pub const Pattern = compile_.Pattern;

const runtime = @import("../runtime.zig");

const ScanOptions = runtime.ScanOptions;
const Scratch = runtime.Scratch;
const Stream = runtime.Stream;

const check = @import("../common.zig").check;

pub const Database = @This();

ptr: *const hs.hs_database_t,

pub fn init(db: *const hs.hs_database_t) Database {
    return Database{
        .ptr = db,
    };
}

/// Serialize a pattern database to a stream of bytes.
pub fn serialize(self: *const Database) !Serialized {
    return Serialized.serialize(self);
}

/// The basic regular expression compiler.
pub fn compile(pattern: *const Pattern, opts: CompileOptions) !Database {
    return compile_.compile(pattern, opts);
}

///  The multiple regular expression compiler.
pub fn compile_multi(patterns: []const Pattern, opts: CompileOptions) !Database {
    return compile_.compile_multi(patterns, opts);
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
    return Scratch.alloc(self);
}

/// The block (non-streaming) regular expression scanner.
pub fn scan_block(self: *const Database, data: []const u8, scratch: Scratch, opts: ScanOptions) !void {
    return runtime.scan_block(self, data, scratch, opts);
}

/// The vectored regular expression scanner.
pub fn scan_vector(self: *const Database, data: []const std.posix.iovec_const, scratch: Scratch, opts: ScanOptions) !void {
    return runtime.scan_vector(self, data, scratch, opts);
}

/// Provides the size of the stream state allocated by a single stream opened against the given database.
pub fn stream_size(self: *const Database) !usize {
    var sz: usize = 0;

    try check(hs.hs_stream_size(self.ptr, &sz));

    return sz;
}

/// Open and initialise a stream.
pub fn open_stream(self: *const Database, opts: Stream.OpenOptions) !Stream {
    return Stream.open(self, opts);
}

// ===== Unit Tests =====

test compile {
    const pattern = try Pattern.parse("hello");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    try std.testing.expect(try db.size() > 0);
}

test "compile with custom options" {
    const pattern = try Pattern.parse("world");
    const opts = CompileOptions{
        .mode = .{ .stream = true },
        .literal = true,
    };
    const db = try Database.compile(&pattern, opts);
    defer db.deinit();

    try std.testing.expect(try db.size() > 0);
}

test compile_multi {
    const patterns = [_]Pattern{
        try Pattern.parse("hello"),
        try Pattern.parse("world"),
    };
    const db = try Database.compile_multi(&patterns, .{
        .mode = .{ .vectored = true },
        .literal = true,
    });
    defer db.deinit();

    try std.testing.expect(try db.size() > 0);
}

test info {
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const db_info = try db.info(std.testing.allocator);
    defer std.testing.allocator.free(db_info);

    // Should contain version information
    try std.testing.expect(std.mem.containsAtLeast(u8, db_info, 1, "Version"));
}

test size {
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const db_size = try db.size();

    try std.testing.expect(db_size > 0);
}

test stream_size {
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const stream_sz = try db.stream_size();

    try std.testing.expect(stream_sz > 0);
}

test open_stream {
    const pattern = try Pattern.parse("test");
    const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    const stream = try db.open_stream(.{});

    try stream.close(scratch, .{});
}

test alloc_scratch {
    const pattern = try Pattern.parse("foo");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    try std.testing.expect(try scratch.size() >= 1000);
}

test scan_block {
    const pattern = try Pattern.parse("hello");
    const db = try Database.compile(&pattern, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    var match_found = false;

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: runtime.MatchEvent) !void {
                evt.setData(bool, true);
            }
        }.handler,
        .context = &match_found,
    };

    try db.scan_block("hello world", scratch, opts);

    try std.testing.expect(match_found);
}

test scan_vector {
    const pattern = try Pattern.parse("hello");
    const db = try Database.compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    var match_found = false;

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: runtime.MatchEvent) !void {
                evt.setData(bool, true);
            }
        }.handler,
        .context = &match_found,
    };

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello ".ptr, .len = 6 },
        .{ .base = "world".ptr, .len = 5 },
    };

    try db.scan_vector(&data, scratch, opts);

    try std.testing.expect(match_found);
}

test "compile error handling" {
    // Test with invalid pattern
    const invalid_pattern = try Pattern.parse("(");

    try std.testing.expectError(error.CompileError, Database.compile(&invalid_pattern, .{}));
}

test "compile_multi error handling" {
    // Test with invalid patterns
    const invalid_patterns = [_]Pattern{
        try Pattern.parse("("),
        try Pattern.parse("valid"),
    };

    try std.testing.expectError(error.CompileError, Database.compile_multi(&invalid_patterns, .{}));
}

test "database with different modes" {
    const pattern = try Pattern.parse("test");

    // Test block mode
    {
        const db = try Database.compile(&pattern, .{ .mode = .{ .block = true } });
        defer db.deinit();

        try std.testing.expect(try db.size() > 0);
    }

    // Test stream mode
    {
        const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
        defer db.deinit();

        try std.testing.expect(try db.size() > 0);
    }

    // Test vectored mode
    {
        const db = try Database.compile(&pattern, .{ .mode = .{ .vectored = true } });
        defer db.deinit();

        try std.testing.expect(try db.size() > 0);
    }
}

test "database with literal mode" {
    const pattern = try Pattern.parse("hello");
    const db = try Database.compile(&pattern, .{ .literal = true });
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    var match_found = false;

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: runtime.MatchEvent) !void {
                evt.setData(bool, true);
            }
        }.handler,
        .context = &match_found,
    };

    // Should match literal "hello"
    try db.scan_block("hello world", scratch, opts);
    try std.testing.expect(match_found);

    // Should not match regex patterns
    match_found = false;
    try db.scan_block("h.*o world", scratch, opts);
    try std.testing.expect(!match_found);
}

test "database with multiple patterns" {
    const patterns = [_]Pattern{
        try Pattern.parse("hello"),
        try Pattern.parse("world"),
    };
    const db = try Database.compile_multi(&patterns, .{});
    defer db.deinit();

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    var ends = try std.ArrayList(u64).initCapacity(std.testing.allocator, 2);
    defer ends.deinit(std.testing.allocator);

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: runtime.MatchEvent) !void {
                evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch {
                    return error.Terminate;
                };
            }
        }.handler,
        .context = &ends,
    };

    try db.scan_block("hello world", scratch, opts);

    try std.testing.expectEqualSlices(u64, &[_]u64{ 5, 11 }, ends.items);
}
