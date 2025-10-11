//! The Hyperscan compiler API definition.

const std = @import("std");

const hs = @cImport(@cInclude("hs/hs.h"));

const Database = @import("common.zig").Database;
const MatchEvent = @import("runtime.zig").MatchEvent;

pub const Pattern = @import("compile/pattern.zig");
pub const Platform = @import("compile/platform.zig");
pub const Flags = @import("compile/flags.zig").Flags;
pub const ExprExt = @import("compile/expr_ext.zig");
pub const ExprInfo = @import("compile/expr_info.zig");

const check = @import("common.zig").check;

/// Compile mode flags
pub const Mode = packed struct(u32) {
    /// Block scan (non-streaming) database.
    block: bool = false,
    /// Streaming database.
    stream: bool = false,
    /// Vectored scanning database.
    vectored: bool = false,

    _reserved: u21 = 0,

    /// Use full precision to track start of match offsets in stream state.
    som_horizon_large: bool = false,
    /// Use medium precision to track start of match offsets in stream state.
    som_horizon_medium: bool = false,
    /// Use limited precision to track start of match offsets in stream state.
    som_horizon_small: bool = false,

    _reserved2: u5 = 0,

    /// Get the value of the mode.
    pub inline fn value(self: Mode) !u32 {
        if ((self.block and self.stream) or (self.block and self.vectored) or (self.stream and self.vectored)) {
            return error.DbModeError;
        }

        if (!self.stream and (self.som_horizon_large or self.som_horizon_medium or self.som_horizon_small)) {
            return error.DbModeError;
        }

        if ((self.som_horizon_large and self.som_horizon_medium) or (self.som_horizon_large and self.som_horizon_small) or (self.som_horizon_medium and self.som_horizon_small)) {
            return error.DbModeError;
        }

        return @bitCast(self);
    }
};

/// Compile options.
pub const Options = struct {
    /// The allocator to use for the compile.
    allocator: ?std.mem.Allocator = null,
    /// The mode for the database.
    mode: Mode = .{ .block = true },
    /// The target platform for the database.
    platform: ?Platform = null,
    /// Whether to compile a pure literal expression.
    literal: bool = false,
};

/// The basic regular expression compiler.
pub fn compile(pattern: *const Pattern, opts: Options) !Database {
    var db: ?*hs.hs_database_t = null;
    var err: ?*hs.hs_compile_error_t = null;

    const flags = pattern.flags.value();
    const mode = try opts.mode.value();
    const platform_info: ?hs.hs_platform_info_t = if (opts.platform) |p| @bitCast(p.raw()) else null;
    const platform = if (platform_info) |p| &p else null;

    var res: c_int = 0;
    if (opts.literal) {
        res = hs.hs_compile_lit(pattern.expr.ptr, flags, pattern.expr.len, mode, platform, &db, &err);
    } else {
        res = hs.hs_compile(pattern.expr.ptr, flags, mode, platform, &db, &err);
    }

    freeCompileError(err);

    try check(res);

    return if (db) |ptr| .init(@ptrCast(ptr)) else error.UnknownError;
}

/// The multiple regular expression compiler.
pub fn compileMulti(patterns: []const Pattern, opts: Options) !Database {
    const allocator = opts.allocator orelse std.heap.c_allocator;
    var exprs: std.ArrayList([*]const u8) = try .initCapacity(allocator, patterns.len);
    var flags: std.ArrayList(u32) = try .initCapacity(allocator, patterns.len);
    var ids: std.ArrayList(u32) = try .initCapacity(allocator, patterns.len);
    var lens: std.ArrayList(usize) = try .initCapacity(allocator, patterns.len);
    var exts: std.ArrayList(hs.hs_expr_ext_t) = try .initCapacity(allocator, patterns.len);
    var exts_ptrs: std.ArrayList(*const hs.hs_expr_ext_t) = try .initCapacity(allocator, patterns.len);

    defer exprs.deinit(allocator);
    defer flags.deinit(allocator);
    defer ids.deinit(allocator);
    defer lens.deinit(allocator);
    defer exts.deinit(allocator);
    defer exts_ptrs.deinit(allocator);

    var has_exts = false;

    for (patterns, 0..) |pattern, i| {
        try exprs.append(allocator, pattern.expr.ptr);
        try flags.append(allocator, pattern.flags.value());
        try ids.append(allocator, pattern.id orelse @intCast(i));
        try lens.append(allocator, pattern.expr.len);
        try exts.append(allocator, if (pattern.ext) |ext| @bitCast(ext.raw()) else .{});
        try exts_ptrs.append(allocator, &exts.items[exts.items.len - 1]);

        has_exts |= pattern.ext != null;
    }

    const elems: u32 = @intCast(patterns.len);
    const mode = try opts.mode.value();
    const platform_info: ?hs.hs_platform_info_t = if (opts.platform) |p| @bitCast(p.raw()) else null;
    const platform = if (platform_info) |p| &p else null;

    var db: ?*hs.hs_database_t = null;
    var err: ?*hs.hs_compile_error_t = null;

    var res: c_int = 0;

    if (opts.literal) {
        res = hs.hs_compile_lit_multi(exprs.items.ptr, flags.items.ptr, ids.items.ptr, lens.items.ptr, elems, mode, platform, &db, &err);
    } else if (has_exts) {
        res = hs.hs_compile_ext_multi(exprs.items.ptr, flags.items.ptr, ids.items.ptr, exts_ptrs.items.ptr, elems, mode, platform, &db, &err);
    } else {
        res = hs.hs_compile_multi(exprs.items.ptr, flags.items.ptr, ids.items.ptr, elems, mode, platform, &db, &err);
    }

    freeCompileError(err);

    try check(res);

    return if (db) |ptr| .init(@ptrCast(ptr)) else error.UnknownError;
}

/// Free an error structure generated by `compile`or `compile_multi`.
pub fn freeCompileError(err: ?*hs.hs_compile_error_t) void {
    if (err) |ce| {
        if (ce.expression >= 0) {
            std.log.warn("compile expression #{d} failed, {s}", .{ ce.expression, ce.message });
        } else {
            std.log.warn("compile failed, {s}", .{ce.message});
        }

        check(hs.hs_free_compile_error(ce)) catch |e| {
            std.log.err("free compile error: {s}", .{@errorName(e)});
        };
    }
}

// Unit tests

test Mode {
    // Test default mode
    try std.testing.expectEqual(0, try Mode.value(.{}));

    // Test individual modes
    try std.testing.expectEqual(hs.HS_MODE_BLOCK, try Mode.value(.{ .block = true }));
    try std.testing.expectEqual(hs.HS_MODE_STREAM, try Mode.value(.{ .stream = true }));
    try std.testing.expectEqual(hs.HS_MODE_VECTORED, try Mode.value(.{ .vectored = true }));

    // Test combinations of modes with SOM horizon flags
    try std.testing.expectEqual(hs.HS_MODE_STREAM | hs.HS_MODE_SOM_HORIZON_LARGE, try Mode.value(.{ .stream = true, .som_horizon_large = true }));
    try std.testing.expectEqual(hs.HS_MODE_STREAM | hs.HS_MODE_SOM_HORIZON_MEDIUM, try Mode.value(.{ .stream = true, .som_horizon_medium = true }));
    try std.testing.expectEqual(hs.HS_MODE_STREAM | hs.HS_MODE_SOM_HORIZON_SMALL, try Mode.value(.{ .stream = true, .som_horizon_small = true }));

    try std.testing.expectError(error.DbModeError, Mode.value(.{ .block = true, .stream = true }));
    try std.testing.expectError(error.DbModeError, Mode.value(.{ .block = true, .vectored = true }));
    try std.testing.expectError(error.DbModeError, Mode.value(.{ .stream = true, .vectored = true }));
    try std.testing.expectError(error.DbModeError, Mode.value(.{ .block = true, .stream = true, .vectored = true }));

    try std.testing.expectError(error.DbModeError, Mode.value(.{ .block = true, .som_horizon_large = true }));
    try std.testing.expectError(error.DbModeError, Mode.value(.{ .vectored = true, .som_horizon_medium = true }));
    try std.testing.expectError(error.DbModeError, Mode.value(.{ .block = true, .som_horizon_small = true }));

    try std.testing.expectError(error.DbModeError, Mode.value(.{ .stream = true, .som_horizon_large = true, .som_horizon_medium = true }));
    try std.testing.expectError(error.DbModeError, Mode.value(.{ .stream = true, .som_horizon_large = true, .som_horizon_small = true }));
    try std.testing.expectError(error.DbModeError, Mode.value(.{ .stream = true, .som_horizon_medium = true, .som_horizon_small = true }));
    try std.testing.expectError(error.DbModeError, Mode.value(.{ .stream = true, .som_horizon_large = true, .som_horizon_medium = true, .som_horizon_small = true }));
}

test "Mode round trip" {
    // Test that we can reconstruct modes from their values
    const test_modes = [_]Mode{
        .{},
        .{ .block = true },
        .{ .stream = true },
        .{ .vectored = true },
        .{ .stream = true, .som_horizon_large = true },
        .{ .stream = true, .som_horizon_medium = true },
        .{ .stream = true, .som_horizon_small = true },
    };

    for (test_modes) |mode| {
        const value = try mode.value();
        const reconstructed = @as(Mode, @bitCast(value));
        try std.testing.expectEqualDeep(mode, reconstructed);
    }
}

// Unit tests for Options

test "Options default values" {
    const opts = Options{};
    try std.testing.expect(opts.allocator == null);
    try std.testing.expectEqual(Mode{ .block = true }, opts.mode);
    try std.testing.expect(opts.platform == null);
    try std.testing.expect(!opts.literal);
}

test "Options with custom values" {
    const custom_allocator = std.testing.allocator;
    const custom_mode = Mode{ .stream = true, .som_horizon_medium = true };
    const custom_platform = Platform{ .tune = .haswell, .cpu_features = .avx2 };

    const opts = Options{
        .allocator = custom_allocator,
        .mode = custom_mode,
        .platform = custom_platform,
        .literal = true,
    };

    try std.testing.expect(opts.allocator != null);
    try std.testing.expectEqual(custom_allocator, opts.allocator.?);
    try std.testing.expectEqual(custom_mode, opts.mode);
    try std.testing.expect(opts.platform != null);
    try std.testing.expectEqual(custom_platform.tune, opts.platform.?.tune);
    try std.testing.expectEqual(custom_platform.cpu_features, opts.platform.?.cpu_features);
    try std.testing.expect(opts.literal);
}

test compile {
    // Test basic pattern compilation
    const foobar: Pattern = try .parse("f[o]+bar");
    const db = try compile(&foobar, .{});
    defer db.deinit();

    // Test literal pattern compilation
    const hello: Pattern = try .parse("hello");
    const db2 = try compile(&hello, .{ .mode = .{ .stream = true }, .literal = true });
    defer db2.deinit();
}

test "compile with different modes" {
    const pattern: Pattern = try .parse("test");

    // Test block mode
    const block_db = try compile(&pattern, .{ .mode = .{ .block = true } });
    defer block_db.deinit();

    // Test stream mode
    const stream_db = try compile(&pattern, .{ .mode = .{ .stream = true } });
    defer stream_db.deinit();

    // Test vectored mode
    const vectored_db = try compile(&pattern, .{ .mode = .{ .vectored = true } });
    defer vectored_db.deinit();

    // Test with SOM horizon flags
    const som_db = try compile(&pattern, .{ .mode = .{ .stream = true, .som_horizon_medium = true } });
    defer som_db.deinit();
}

test "compile with different platforms" {
    const pattern: Pattern = try .parse("test");

    // Test with generic platform
    const generic_db = try compile(&pattern, .{ .platform = Platform{ .tune = .generic } });
    defer generic_db.deinit();

    // Test with specific platform
    const haswell_db = try compile(&pattern, .{ .platform = Platform{ .tune = .haswell, .cpu_features = .avx2 } });
    defer haswell_db.deinit();

    // Test with null platform (default)
    const null_platform_db = try compile(&pattern, .{ .platform = null });
    defer null_platform_db.deinit();
}

test "compile with literal flag" {
    const pattern: Pattern = try .parse("hello");

    // Test literal compilation
    const db = try compile(&pattern, .{ .literal = true });
    defer db.deinit();
}

test "compile with complex patterns" {
    // Test complex regex pattern
    const complex_pattern: Pattern = try .parse("\\b\\w+@\\w+\\.\\w+\\b");
    const complex_db = try compile(&complex_pattern, .{});
    defer complex_db.deinit();

    // Test pattern with flags
    const flagged_pattern: Pattern = try .parse("/test/i");
    const flagged_db = try compile(&flagged_pattern, .{});
    defer flagged_db.deinit();

    // Test pattern with extensions
    const test_pattern: Pattern = try .parse("test");
    const ext_pattern = test_pattern.withExt(.{ .min_offset = 10, .max_offset = 100 });
    const ext_db = try compile(&ext_pattern, .{});
    defer ext_db.deinit();
}

test "compile error handling" {
    // Test invalid pattern
    const invalid_pattern: Pattern = try .parse("(");
    try std.testing.expectError(error.CompileError, compile(&invalid_pattern, .{}));

    // Test malformed regex
    const malformed_pattern: Pattern = try .parse("[");
    try std.testing.expectError(error.CompileError, compile(&malformed_pattern, .{}));

    // Test unbalanced parentheses
    const unbalanced_pattern: Pattern = try .parse("(test");
    try std.testing.expectError(error.CompileError, compile(&unbalanced_pattern, .{}));
}

test "compile with empty patterns" {
    // Test empty pattern
    {
        const empty_pattern: Pattern = .init("", .{ .allow_empty = true });
        const empty_db = try compile(&empty_pattern, .{});
        defer empty_db.deinit();
    }

    // Test empty pattern with literal flag
    {
        const empty_pattern: Pattern = .init("", .{});

        // Pure literal API doesn't support empty string.
        try std.testing.expectError(error.CompileError, compile(&empty_pattern, .{ .literal = true }));
    }
}

test "compile with unicode patterns" {
    // Test unicode pattern
    const unicode_pattern: Pattern = try .parse("测试");
    const unicode_db = try compile(&unicode_pattern, .{});
    defer unicode_db.deinit();

    // Test unicode pattern with UTF-8 flag
    const unicode_flagged: Pattern = try .parse("/测试/8");
    const unicode_flagged_db = try compile(&unicode_flagged, .{});
    defer unicode_flagged_db.deinit();
}

test "compile with special characters" {
    // Test pattern with special regex characters
    const special_pattern: Pattern = try .parse("[a-z]+\\d*");
    const special_db = try compile(&special_pattern, .{});
    defer special_db.deinit();

    // Test pattern with anchors
    const anchor_pattern: Pattern = try .parse("^test$");
    const anchor_db = try compile(&anchor_pattern, .{});
    defer anchor_db.deinit();

    // Test pattern with quantifiers
    const quantifier_pattern: Pattern = try .parse("a{3,5}");
    const quantifier_db = try compile(&quantifier_pattern, .{});
    defer quantifier_db.deinit();
}

test "compile with different allocators" {
    const pattern: Pattern = try .parse("test");

    // Test with testing allocator
    const test_db = try compile(&pattern, .{ .allocator = std.testing.allocator });
    defer test_db.deinit();

    // Test with c allocator
    const c_db = try compile(&pattern, .{ .allocator = std.heap.c_allocator });
    defer c_db.deinit();
}

test compileMulti {
    // Test basic multi-pattern compilation
    const helo: Pattern = try .parse("he[l]+o");
    const hello: Pattern = try .parse("hello");
    const world: Pattern = try .parse("world");

    // create the slice that will store the last match offset
    var ends: std.ArrayList(u64) = try .initCapacity(std.testing.allocator, 3);
    defer ends.deinit(std.testing.allocator);

    // compile multiple patterns into a block database.
    {
        const patterns = [_]Pattern{ helo, world };
        const db = try compileMulti(&patterns, .{ .allocator = std.testing.allocator });
        defer db.deinit();

        const scratch = try db.allocScratch();
        defer scratch.deinit();

        // scan the text
        try db.scanBlock("hello world", scratch, .{
            .allocator = std.testing.allocator,
            .onEvent = struct {
                fn handler(evt: MatchEvent) !void {
                    evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch |err| {
                        std.log.err("append to ends: {s}", .{@errorName(err)});
                        return error.Terminate;
                    };
                }
            }.handler,
            .context = @constCast(&ends),
        });

        // expect the last match offset to be found
        try std.testing.expectEqualSlices(u64, &[_]u64{ 5, 11 }, ends.items);
    }

    ends.clearAndFree(std.testing.allocator);

    // compile multiple patterns with extensions into a block database.
    {
        const patterns = [_]Pattern{ helo, world.withExt(.{ .min_offset = 1 }) };
        const db = try compileMulti(&patterns, .{ .allocator = std.testing.allocator });
        defer db.deinit();

        const scratch = try db.allocScratch();
        defer scratch.deinit();

        // scan the text
        try db.scanBlock("hello world", scratch, .{
            .allocator = std.testing.allocator,
            .onEvent = struct {
                fn handler(evt: MatchEvent) !void {
                    evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch |err| {
                        std.log.err("append to ends: {s}", .{@errorName(err)});
                        return error.Terminate;
                    };
                }
            }.handler,
            .context = @constCast(&ends),
        });

        // expect the last match offset to be found
        try std.testing.expectEqualSlices(u64, &[_]u64{ 5, 11 }, ends.items);
    }

    ends.clearAndFree(std.testing.allocator);

    // compile the pure literal pattern into a block database.
    {
        const patterns = [_]Pattern{ hello, world };
        const db = try compileMulti(&patterns, .{ .allocator = std.testing.allocator, .literal = true });
        defer db.deinit();

        const scratch = try db.allocScratch();
        defer scratch.deinit();

        try db.scanBlock("hello world", scratch, .{
            .allocator = std.testing.allocator,
            .onEvent = struct {
                fn handler(evt: MatchEvent) !void {
                    evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch |err| {
                        std.log.err("append to ends: {s}", .{@errorName(err)});
                        return error.Terminate;
                    };
                }
            }.handler,
            .context = @constCast(&ends),
        });

        try std.testing.expectEqualSlices(u64, &[_]u64{ 5, 11 }, ends.items);
    }
}

test "compile_multi with different modes" {
    const patterns = [_]Pattern{
        try .parse("test1"),
        try .parse("test2"),
        try .parse("test3"),
    };

    // Test block mode
    const block_db = try compileMulti(&patterns, .{ .mode = .{ .block = true } });
    defer block_db.deinit();

    // Test stream mode
    const stream_db = try compileMulti(&patterns, .{ .mode = .{ .stream = true } });
    defer stream_db.deinit();

    // Test vectored mode
    const vectored_db = try compileMulti(&patterns, .{ .mode = .{ .vectored = true } });
    defer vectored_db.deinit();
}

test "compile_multi with different platforms" {
    const patterns = [_]Pattern{
        try .parse("test1"),
        try .parse("test2"),
    };

    // Test with generic platform
    const generic_db = try compileMulti(&patterns, .{ .platform = .{ .tune = .generic } });
    defer generic_db.deinit();

    // Test with specific platform
    const haswell_db = try compileMulti(&patterns, .{ .platform = .{ .tune = .haswell, .cpu_features = .avx2 } });
    defer haswell_db.deinit();
}

test "compile_multi with patterns with IDs" {
    const patterns = [_]Pattern{
        .{ .expr = "test1", .id = 1 },
        .{ .expr = "test2", .id = 2 },
        .{ .expr = "test3", .id = 3 },
    };

    const db = try compileMulti(&patterns, .{});
    defer db.deinit();
}

test "compile_multi with patterns with extensions" {
    const patterns = [_]Pattern{
        (try Pattern.parse("test1")).withExt(.{ .min_offset = 10 }),
        (try Pattern.parse("test2")).withExt(.{ .max_offset = 100 }),
        (try Pattern.parse("test3")).withExt(.{ .min_length = 5 }),
    };

    const db = try compileMulti(&patterns, .{});
    defer db.deinit();
}

test "compile_multi with mixed patterns" {
    const patterns = [_]Pattern{
        .{ .expr = "test1", .id = 1 },
        (try Pattern.parse("test2")).withExt(.{ .min_offset = 10 }),
        try .parse("/test3/i"),
        .{ .expr = "test4", .id = 4, .flags = .{ .caseless = true } },
    };

    const db = try compileMulti(&patterns, .{});
    defer db.deinit();
}

test "compile_multi with empty pattern list" {
    const patterns = [_]Pattern{};
    try std.testing.expectError(error.CompileError, compileMulti(&patterns, .{}));
}

test "compile_multi with single pattern" {
    const patterns = [_]Pattern{try .parse("test")};
    const db = try compileMulti(&patterns, .{});
    defer db.deinit();
}

test "compile_multi with many patterns" {
    var patterns: [100]Pattern = undefined;
    var exprs: [100][]u8 = undefined;

    for (0..100) |i| {
        exprs[i] = try std.fmt.allocPrint(std.testing.allocator, "test{d}", .{i});
        patterns[i] = try .parse(exprs[i]);
    }

    defer {
        for (exprs) |expr| {
            std.testing.allocator.free(expr);
        }
    }

    const db = try compileMulti(patterns[0..100], .{});
    defer db.deinit();
}

test "compile_multi error handling" {
    // Test with invalid patterns
    const invalid_patterns = [_]Pattern{
        try .parse("("),
        try .parse("test"),
    };
    try std.testing.expectError(error.CompileError, compileMulti(&invalid_patterns, .{}));

    // Test with malformed patterns
    const malformed_patterns = [_]Pattern{
        try .parse("["),
        try .parse("test"),
    };
    try std.testing.expectError(error.CompileError, compileMulti(&malformed_patterns, .{}));
}

test "compile_multi with unicode patterns" {
    const patterns = [_]Pattern{
        try .parse("测试1"),
        try .parse("测试2"),
        try .parse("/测试3/8"),
    };

    const db = try compileMulti(&patterns, .{});
    defer db.deinit();
}

test "compile_multi with complex patterns" {
    const patterns = [_]Pattern{
        try .parse("\\b\\w+@\\w+\\.\\w+\\b"),
        try .parse("[a-z]+\\d*"),
        try .parse("^test$"),
        try .parse("a{3,5}"),
    };

    const db = try compileMulti(&patterns, .{});
    defer db.deinit();
}

test "compile_multi with different allocators" {
    const patterns = [_]Pattern{
        try .parse("test1"),
        try .parse("test2"),
    };

    // Test with testing allocator
    const test_db = try compileMulti(&patterns, .{ .allocator = std.testing.allocator });
    defer test_db.deinit();

    // Test with c allocator
    const c_db = try compileMulti(&patterns, .{ .allocator = std.heap.c_allocator });
    defer c_db.deinit();
}

test freeCompileError {
    // Test that freeCompileError handles null pointer correctly
    freeCompileError(null);

    // Test that freeCompileError is called during compile error
    const invalid_pattern: Pattern = try .parse("f(bar");
    try std.testing.expectError(error.CompileError, compile(&invalid_pattern, .{}));

    // Test with malformed regex
    const malformed_pattern: Pattern = try .parse("[");
    try std.testing.expectError(error.CompileError, compile(&malformed_pattern, .{}));

    // Test with unbalanced parentheses
    const unbalanced_pattern: Pattern = try .parse("(test");
    try std.testing.expectError(error.CompileError, compile(&unbalanced_pattern, .{}));
}

test "freeCompileError with multi-pattern errors" {
    // Test that freeCompileError is called during multi-pattern compile errors
    const invalid_patterns = [_]Pattern{
        try .parse("("),
        try .parse("test"),
    };
    try std.testing.expectError(error.CompileError, compileMulti(&invalid_patterns, .{}));

    const malformed_patterns = [_]Pattern{
        try .parse("["),
        try .parse("test"),
    };
    try std.testing.expectError(error.CompileError, compileMulti(&malformed_patterns, .{}));
}

test "freeCompileError error message validation" {
    // Test that error messages are properly logged
    const invalid_pattern: Pattern = try .parse("(");

    // TODO: Capture log output to verify error messages are logged
    // Note: This is a basic test - in a real implementation you might want to
    // capture and verify the actual log output
    try std.testing.expectError(error.CompileError, compile(&invalid_pattern, .{}));
}

// Integration tests

test "integration - complex workflow" {
    // Test a complete workflow with multiple patterns, different modes, and platforms
    const patterns = [_]Pattern{
        .{ .expr = "email", .ext = .{ .min_offset = 10 } },
        try .parse("/phone/i"),
        .{ .expr = "credit_card", .id = 1, .flags = .{ .caseless = true } },
        try .parse("\\b\\w+@\\w+\\.\\w+\\b"),
    };

    // Test with different modes
    const block_db = try compileMulti(&patterns, .{ .mode = .{ .block = true } });
    defer block_db.deinit();

    const stream_db = try compileMulti(&patterns, .{ .mode = .{ .stream = true } });
    defer stream_db.deinit();

    const vectored_db = try compileMulti(&patterns, .{ .mode = .{ .vectored = true } });
    defer vectored_db.deinit();

    // Test with different platforms
    const generic_db = try compileMulti(&patterns, .{ .platform = .{ .tune = .generic } });
    defer generic_db.deinit();

    const haswell_db = try compileMulti(&patterns, .{ .platform = .{ .tune = .haswell, .cpu_features = .avx2 } });
    defer haswell_db.deinit();
}

test "integration - literal vs regex compilation" {
    const p: Pattern = try .parse("test123");

    // Test literal compilation
    {
        const db = try compile(&p, .{ .literal = true });
        defer db.deinit();
    }

    // Test regex compilation
    {
        const db = try compile(&p, .{});
        defer db.deinit();
    }
}

test "integration - pattern with all features" {
    const complex_pattern = Pattern{
        .expr = "test.*pattern",
        .id = 42,
        .flags = .{ .caseless = true, .dot_all = true, .multiline = true },
        .ext = .{ .min_offset = 10, .max_offset = 100, .min_length = 5 },
    };

    const db = try compile(&complex_pattern, .{
        .mode = .{ .block = true },
        .platform = .{ .tune = .skylake, .cpu_features = .avx512 },
        .literal = false,
    });
    defer db.deinit();
}

// Error handling tests

test "error handling - invalid patterns" {
    const invalid_patterns = [_][]const u8{
        "(",
        "[",
        ")",
        "\\",
        "a{2,1}",
        "foo^bar",
        "foo$bar",
        "[]",
        "a{0}",
        "a{0,0}",
    };

    for (invalid_patterns) |pattern_str| {
        const pattern: Pattern = try .parse(pattern_str);

        try std.testing.expectError(error.CompileError, compile(&pattern, .{}));
    }
}

test "error handling - memory allocation errors" {
    const pattern: Pattern = try .parse("test");

    var buf: [8]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);

    const res = compileMulti(&[_]Pattern{pattern}, .{ .allocator = fba.allocator() });

    try std.testing.expectError(error.OutOfMemory, res);
}

// Edge case tests

test "edge cases - empty patterns" {
    const empty_pattern = Pattern.init("", .{ .allow_empty = true });
    const db = try compile(&empty_pattern, .{});
    defer db.deinit();
}

test "edge cases - very long patterns" {
    const long_expr = try std.testing.allocator.alloc(u8, 10000);
    defer std.testing.allocator.free(long_expr);
    @memset(long_expr, 'a');

    const long_pattern = try Pattern.parse(long_expr);
    const db = try compile(&long_pattern, .{});
    defer db.deinit();
}

test "edge cases - unicode patterns" {
    const unicode_patterns = [_][]const u8{
        "测试",
        "тест",
        "テスト",
        "اختبار",
        "בדיקה",
        "тест123",
        "测试456",
        "テスト789",
    };

    for (unicode_patterns) |s| {
        const p: Pattern = try .parse(s);
        const db = try compile(&p, .{});
        defer db.deinit();
    }
}

test "edge cases - special characters" {
    const special_patterns = [_][]const u8{
        "!@#%&*()",
        "{}|\\:;\"'<>?/.,",
        " \t\n\r",
        "a\tb\nc\rd",
        "a\\tb\\nc\\rd",
    };

    for (special_patterns) |s| {
        const p: Pattern = try .parse(s);
        const db = try compile(&p, .{});
        defer db.deinit();
    }
}

test "edge cases - extreme quantifiers" {
    const patterns = [_][]const u8{
        "a{1}",
        "/a{0,1}/V",
        "a{1,1}",
        "a{1000}",
        "/a{0,1000}/V",
        "a{1000,1000}",
        "/a{0,}/V",
        "a{1,}",
        "a{1000,}",
    };

    for (patterns) |s| {
        const p: Pattern = try .parse(s);
        const db = try compile(&p, .{});
        defer db.deinit();
    }
}

test {
    std.testing.refAllDecls(@This());
}
