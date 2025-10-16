//! A Hyperscan pattern database.

const std = @import("std");

const cstring = @cImport(@cInclude("string.h"));
const hs = @cImport(@cInclude("hs/hs.h"));

const Serialized = @import("Serialized.zig");

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

/// Initialize a database.
pub fn init(db: *const hs.hs_database_t) Database {
    return .{
        .ptr = db,
    };
}

/// Free a compiled pattern database.
///
/// Releases all memory associated with the compiled database. This should be called
/// when the database is no longer needed to prevent memory leaks.
///
/// ## Arguments
/// - `self`: The database to free
///
/// ## Example
/// ```zig
/// var db = try Database.compile(&pattern, .{});
/// defer db.deinit(); // Free the database when done
///
/// // Use the database...
/// ```
pub fn deinit(self: *Database) void {
    check(hs.hs_free_database(@constCast(self.ptr))) catch |e| {
        std.log.err("deinit database: {s}", .{@errorName(e)});
    };

    self.* = undefined;
}

/// Serialize a pattern database to a stream of bytes.
///
/// Converts a compiled database into a serialized format that can be saved to disk
/// or transmitted over a network. The serialized data can later be deserialized
/// to recreate the database without recompiling the patterns.
///
/// ## Arguments
/// - `self`: The database to serialize
///
/// ## Returns
/// A `Serialized` object containing the database data, or an error if serialization fails.
///
/// ## Example
/// ```zig
/// const db = try Database.compile(&pattern, .{});
/// defer db.deinit();
///
/// const serialized = try db.serialize();
/// defer serialized.deinit();
/// ```
pub fn serialize(self: *const Database) !Serialized {
    return .serialize(self);
}

/// The basic regular expression compiler.
///
/// Compiles a single pattern into a Hyperscan database that can be used for
/// high-performance pattern matching. The compiled database is optimized for
/// the target platform and can be reused for multiple scan operations.
///
/// ## Arguments
/// - `pattern`: The pattern to compile
/// - `opts`: Compilation options including mode, platform, and other settings
///
/// ## Returns
/// A compiled `Database` that can be used for scanning, or an error if compilation fails.
///
/// # Errors
/// - `error.DbModeError`: If the database mode is invalid
/// - `error.CompileError`: If the pattern contains invalid regex syntax
///
/// ## Example
/// ```zig
/// const pattern = try Pattern.parse("hello.*world");
/// defer db.deinit();
///
/// const db = try Database.compile(&pattern, .{ .mode = .{ .block = true } });
/// ```
pub fn compile(pattern: *const Pattern, opts: CompileOptions) !Database {
    return compile_.compile(pattern, opts);
}

/// The multiple regular expression compiler.
///
/// Compiles multiple patterns into a single Hyperscan database that can efficiently
/// match all patterns simultaneously. This is more efficient than compiling patterns
/// separately when scanning for multiple patterns.
///
/// ## Arguments
/// - `patterns`: A slice of patterns to compile together
/// - `opts`: Compilation options including mode, platform, and other settings
///
/// ## Returns
/// A compiled `Database` containing all patterns, or an error if compilation fails.
///
/// # Errors
/// - `error.CompileError`: If any pattern contains invalid regex syntax
/// - `error.OutOfMemory`: If insufficient memory is available
///
/// ## Example
/// ```zig
/// const patterns = [_]Pattern{
///     try .parse("hello"),
///     try .parse("world"),
///     try .parse("test.*pattern"),
/// };
///
/// const db = try Database.compileMulti(&patterns, .{});
/// defer db.deinit();
/// ```
pub fn compileMulti(patterns: []const Pattern, opts: CompileOptions) !Database {
    return compile_.compileMulti(patterns, opts);
}

/// Utility function providing information about a database.
///
/// Returns a human-readable string containing information about the compiled database,
/// including version details, pattern count, and other metadata.
///
/// ## Arguments
/// - `self`: The database to get information about
/// - `allocator`: The allocator to use for the returned string
///
/// ## Returns
/// A string containing database information, or an error if the operation fails.
/// The caller is responsible for freeing the returned string.
///
/// ## Example
/// ```zig
/// const db = try Database.compile(&pattern, .{});
/// defer db.deinit();
///
/// const info = try db.info(allocator);
/// defer allocator.free(info);
///
/// std.log.info("Database info: {s}", .{info});
/// ```
pub fn info(self: *const Database, allocator: std.mem.Allocator) ![]const u8 {
    var db_info: ?[*]u8 = null;

    try check(hs.hs_database_info(self.ptr, &db_info));
    defer std.c.free(db_info);

    return if (db_info) |p|
        allocator.dupe(u8, p[0..cstring.strlen(p)])
    else
        error.UnknownError;
}

/// Provides the size of the given database in bytes.
///
/// Returns the total memory size of the compiled database, which can be useful
/// for monitoring memory usage or estimating serialization size.
///
/// ## Arguments
/// - `self`: The database to get the size of
///
/// ## Returns
/// The size of the database in bytes, or an error if the operation fails.
///
/// ## Example
/// ```zig
/// const db = try Database.compile(&pattern, .{});
/// defer db.deinit();
///
/// const db_size = try db.size();
/// std.log.info("Database size: {} bytes", .{db_size});
/// ```
pub fn size(self: *const Database) !usize {
    var sz: usize = 0;

    try check(hs.hs_database_size(self.ptr, &sz));

    return sz;
}

/// Allocate a "scratch" space for use by Hyperscan.
///
/// Allocates scratch space that is required for scanning operations with this database.
/// The scratch space contains temporary state and should be reused across multiple
/// scan operations for better performance.
///
/// ## Arguments
/// - `self`: The database to allocate scratch space for
///
/// ## Returns
/// A `Scratch` object that can be used for scanning, or an error if allocation fails.
///
/// ## Example
/// ```zig
/// const db = try Database.compile(&pattern, .{});
/// defer db.deinit();
///
/// const scratch = try db.allocScratch();
/// defer scratch.deinit();
/// ```
pub fn allocScratch(self: *const Database) !Scratch {
    return .alloc(self);
}

/// The block (non-streaming) regular expression scanner.
///
/// Scans a block of data for matches using the compiled database. This is the
/// most common scanning mode and is suitable for scanning complete data blocks
/// where the entire data is available at once.
///
/// ## Arguments
/// - `self`: The compiled database to use for scanning
/// - `data`: The data to scan
/// - `scratch`: Scratch space allocated for the database
/// - `opts`: Scan options including event handler and context
///
/// ## Returns
/// An error if scanning fails.
///
/// ## Example
/// ```zig
/// const db = try Database.compile(&pattern, .{});
/// defer db.deinit();
///
/// const scratch = try db.allocScratch();
/// defer scratch.deinit();
///
/// try db.scanBlock("hello world", scratch, .{
///     .onEvent = onMatch,
///     .context = null,
/// });
/// ```
pub fn scanBlock(self: *const Database, data: []const u8, scratch: Scratch, opts: ScanOptions) !void {
    return runtime.scanBlock(self, data, scratch, opts);
}

/// The vectored regular expression scanner.
///
/// Scans multiple data vectors for matches using the compiled database.
/// This is useful when data is split across multiple buffers or
/// when scanning from multiple sources simultaneously.
///
/// ## Arguments
/// - `self`: The compiled database to use for scanning
/// - `data`: An array of iovec structures containing the data to scan
/// - `scratch`: Scratch space allocated for the database
/// - `opts`: Scan options including event handler and context
///
/// ## Returns
/// An error if scanning fails.
///
/// ## Example
/// ```zig
/// const db = try Database.compile(&pattern, .{});
/// defer db.deinit();
///
/// const scratch = try db.allocScratch();
/// defer scratch.deinit();
///
/// const vectors = [_]std.posix.iovec_const{
///     .{ .base = @ptrCast("hello "), .len = 6 },
///     .{ .base = @ptrCast("world"), .len = 5 },
/// };
///
/// try db.scanVector(&vectors, scratch, .{
///     .onEvent = onMatch,
///     .context = null,
/// });
/// ```
pub fn scanVector(self: *const Database, data: []const std.posix.iovec_const, scratch: Scratch, opts: ScanOptions) !void {
    return runtime.scanVector(self, data, scratch, opts);
}

/// The streaming regular expression scanner.
///
/// Scans data from a reader in streaming mode, processing data in chunks as it becomes
/// available. This is useful for scanning large files or network streams where the
/// entire data is not available at once.
///
/// ## Arguments
/// - `self`: The compiled database to use for scanning (must be compiled in stream mode)
/// - `reader`: The reader to read data from
/// - `scratch`: Scratch space allocated for the database
/// - `opts`: Scan options including event handler and context
///
/// ## Returns
/// An error if scanning fails.
///
/// ## Example
/// ```zig
/// const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
/// defer db.deinit();
///
/// const scratch = try db.allocScratch();
/// defer scratch.deinit();
///
/// const file = try std.fs.cwd().openFile("large_file.txt", .{});
/// defer file.close();
///
/// try db.scanStream(file.reader(), scratch, .{
///     .onEvent = onMatch,
///     .context = null,
/// });
/// ```
pub fn scanStream(self: *const Database, data: *std.Io.Reader, scratch: Scratch, opts: ScanOptions) !void {
    return runtime.scanStream(self, data, scratch, opts);
}

/// Returns the size of the stream state allocated by a single stream opened against the given database.
/// This is useful for monitoring memory usage or estimating serialization size.
///
/// ## Arguments
/// - `self`: The database to get the size of
///
/// ## Returns
/// The size of the stream state in bytes, or an error if the operation fails.
///
/// ## Example
/// ```zig
/// const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
/// defer db.deinit();
///
/// const stream_size = try db.streamSize();
/// std.log.info("Stream size: {} bytes", .{stream_size});
/// ```
pub fn streamSize(self: *const Database) !usize {
    var sz: usize = 0;

    try check(hs.hs_stream_size(self.ptr, &sz));

    return sz;
}

/// Open and initialise a stream.
///
/// Creates a new streaming context for the given database. The stream maintains
/// state between scan operations and is required for streaming mode scanning.
///
/// ## Arguments
/// - `self`: The database to create a stream for (must be compiled in stream mode)
/// - `opts`: Stream options including flags
///
/// ## Returns
/// A new `Stream` object, or an error if stream creation fails.
///
/// ## Example
/// ```zig
/// const db = try Database.compile(&pattern, .{ .mode = .{ .stream = true } });
/// defer db.deinit();
///
/// const stream = try db.openStream(.{});
/// defer stream.deinit();
/// ```
pub fn openStream(self: *const Database, opts: Stream.OpenOptions) !Stream {
    return .open(self, opts);
}

/// Decompresses a compressed representation created by `Stream.compress` into a new stream.
///
/// ## Arguments
/// - `self`: The database to decompress the stream for
/// - `buf`: The compressed stream to decompress
///
/// ## Returns
/// A new `Stream` object, or an error if decompression fails.
///
/// ## Example
/// ```zig
/// const stream = try db.expandStream(compressed);
/// defer stream.deinit();
/// ```
///
pub fn expandStream(self: *const Database, buf: []const u8) !Stream {
    return .expand(self, buf);
}

// ===== Unit Tests =====

test compile {
    const pattern: Pattern = try .parse("hello");
    var db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    try std.testing.expect(try db.size() > 0);
}

test "compile with custom options" {
    const pattern: Pattern = try .parse("world");
    var db: Database = try .compile(&pattern, .{
        .mode = .{ .stream = true },
        .literal = true,
    });
    defer db.deinit();

    try std.testing.expect(try db.size() > 0);
}

test compileMulti {
    const patterns = [_]Pattern{
        try .parse("hello"),
        try .parse("world"),
    };
    var db: Database = try .compileMulti(&patterns, .{
        .mode = .{ .vectored = true },
        .literal = true,
    });
    defer db.deinit();

    try std.testing.expect(try db.size() > 0);
}

test info {
    const pattern: Pattern = try .parse("test");
    var db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    const db_info = try db.info(std.testing.allocator);
    defer std.testing.allocator.free(db_info);

    // Should contain version information
    try std.testing.expect(std.mem.containsAtLeast(u8, db_info, 1, "Version"));
}

test size {
    const pattern: Pattern = try .parse("test");
    var db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    const db_size = try db.size();

    try std.testing.expect(db_size > 0);
}

test streamSize {
    const pattern: Pattern = try .parse("test");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    const stream_sz = try db.streamSize();

    try std.testing.expect(stream_sz > 0);
}

test openStream {
    const pattern: Pattern = try .parse("test");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    const stream = try db.openStream(.{});

    try stream.close(scratch, .{});
}

test allocScratch {
    const pattern: Pattern = try .parse("foo");
    var db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    try std.testing.expect(try scratch.size() >= 1000);
}

test scanBlock {
    const pattern: Pattern = try .parse("hello");
    var db: Database = try .compile(&pattern, .{});
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    var match_found = false;

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: runtime.MatchEvent) !void {
                evt.data(bool).* = true;
            }
        }.handler,
        .context = &match_found,
    };

    try db.scanBlock("hello world", scratch, opts);

    try std.testing.expect(match_found);
}

test scanVector {
    const pattern: Pattern = try .parse("hello");
    var db: Database = try .compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    var match_found = false;

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: runtime.MatchEvent) !void {
                evt.data(bool).* = true;
            }
        }.handler,
        .context = &match_found,
    };

    const data = [_]std.posix.iovec_const{
        .{ .base = "hello ".ptr, .len = 6 },
        .{ .base = "world".ptr, .len = 5 },
    };

    try db.scanVector(&data, scratch, opts);

    try std.testing.expect(match_found);
}

test "compile error handling" {
    // Test with invalid pattern
    const invalid_pattern: Pattern = try .parse("(");

    try std.testing.expectError(error.CompileError, Database.compile(&invalid_pattern, .{}));
}

test "compileMulti error handling" {
    // Test with invalid patterns
    const invalid_patterns = [_]Pattern{
        try .parse("("),
        try .parse("valid"),
    };

    try std.testing.expectError(error.CompileError, Database.compileMulti(&invalid_patterns, .{}));
}

test "database with different modes" {
    const pattern: Pattern = try .parse("test");

    // Test block mode
    {
        var db: Database = try .compile(&pattern, .{ .mode = .{ .block = true } });
        defer db.deinit();

        try std.testing.expect(try db.size() > 0);
    }

    // Test stream mode
    {
        var db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
        defer db.deinit();

        try std.testing.expect(try db.size() > 0);
    }

    // Test vectored mode
    {
        var db: Database = try .compile(&pattern, .{ .mode = .{ .vectored = true } });
        defer db.deinit();

        try std.testing.expect(try db.size() > 0);
    }
}

test "database with literal mode" {
    const pattern: Pattern = try .parse("hello");
    var db: Database = try .compile(&pattern, .{ .literal = true });
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    var match_found = false;

    const opts = ScanOptions{
        .onEvent = struct {
            fn handler(evt: runtime.MatchEvent) !void {
                evt.data(bool).* = true;
            }
        }.handler,
        .context = &match_found,
    };

    // Should match literal "hello"
    try db.scanBlock("hello world", scratch, opts);
    try std.testing.expect(match_found);

    // Should not match regex patterns
    match_found = false;
    try db.scanBlock("h.*o world", scratch, opts);
    try std.testing.expect(!match_found);
}

test "database with multiple patterns" {
    const patterns = [_]Pattern{
        try .parse("hello"),
        try .parse("world"),
    };
    var db: Database = try .compileMulti(&patterns, .{});
    defer db.deinit();

    var scratch = try db.allocScratch();
    defer scratch.deinit();

    var ends: std.ArrayList(u64) = try .initCapacity(std.testing.allocator, 2);
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

    try db.scanBlock("hello world", scratch, opts);

    try std.testing.expectEqualSlices(u64, &[_]u64{ 5, 11 }, ends.items);
}
