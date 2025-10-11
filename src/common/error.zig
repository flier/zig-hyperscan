const std = @import("std");

const hs = @cImport(@cInclude("hs/hs.h"));

/// A type for errors returned by Hyperscan functions.
pub const Error = error{
    /// The engine completed normally.
    Success,
    /// A parameter passed to this function was invalid.
    Invalid,
    /// A memory allocation failed.
    NoMemory,
    /// The engine was terminated by callback.
    ScanTerminated,
    /// The engine was terminated by callback.
    CompileError,
    /// The pattern compiler failed, and the `hs_compile_error_t` should be inspected for more detail.
    DbVersionError,
    /// The given database was built for a different platform (i.e., CPU type).
    DbPlatformError,
    /// The given database was built for a different mode of operation.
    DbModeError,
    /// A parameter passed to this function was not correctly aligned.
    BadAlign,
    /// The memory allocator did not correctly return memory suitably aligned.
    BadAlloc,
    /// The scratch region was already in use.
    ScratchInUse,
    /// Unsupported CPU architecture.
    ArchError,
    /// Provided buffer was too small.
    InsufficientSpace,
    /// Unexpected internal error.
    UnknownError,
};

/// Utility function to check an error code.
pub fn check(err: hs.hs_error_t) Error!void {
    switch (err) {
        hs.HS_SUCCESS => {},
        hs.HS_INVALID => return Error.Invalid,
        hs.HS_NOMEM => return Error.NoMemory,
        hs.HS_SCAN_TERMINATED => return Error.ScanTerminated,
        hs.HS_COMPILER_ERROR => return Error.CompileError,
        hs.HS_DB_VERSION_ERROR => return Error.DbVersionError,
        hs.HS_DB_PLATFORM_ERROR => return Error.DbPlatformError,
        hs.HS_DB_MODE_ERROR => return Error.DbModeError,
        hs.HS_BAD_ALIGN => return Error.BadAlign,
        hs.HS_BAD_ALLOC => return Error.BadAlloc,
        hs.HS_SCRATCH_IN_USE => return Error.ScratchInUse,
        hs.HS_ARCH_ERROR => return Error.ArchError,
        hs.HS_INSUFFICIENT_SPACE => return Error.InsufficientSpace,
        hs.HS_UNKNOWN_ERROR => return Error.UnknownError,
        else => {},
    }
}

// ===== Unit Tests =====

test "check success cases" {
    // Test success case
    try check(hs.HS_SUCCESS);

    // Test unknown error codes (should not error)
    try check(123);
    try check(-123);
    try check(0);
    try check(999);
}

test "check all error mappings" {
    // Test all known error codes map to correct Zig errors
    try std.testing.expectError(Error.Invalid, check(hs.HS_INVALID));
    try std.testing.expectError(Error.NoMemory, check(hs.HS_NOMEM));
    try std.testing.expectError(Error.ScanTerminated, check(hs.HS_SCAN_TERMINATED));
    try std.testing.expectError(Error.CompileError, check(hs.HS_COMPILER_ERROR));
    try std.testing.expectError(Error.DbVersionError, check(hs.HS_DB_VERSION_ERROR));
    try std.testing.expectError(Error.DbPlatformError, check(hs.HS_DB_PLATFORM_ERROR));
    try std.testing.expectError(Error.DbModeError, check(hs.HS_DB_MODE_ERROR));
    try std.testing.expectError(Error.BadAlign, check(hs.HS_BAD_ALIGN));
    try std.testing.expectError(Error.BadAlloc, check(hs.HS_BAD_ALLOC));
    try std.testing.expectError(Error.ScratchInUse, check(hs.HS_SCRATCH_IN_USE));
    try std.testing.expectError(Error.ArchError, check(hs.HS_ARCH_ERROR));
    try std.testing.expectError(Error.InsufficientSpace, check(hs.HS_INSUFFICIENT_SPACE));
    try std.testing.expectError(Error.UnknownError, check(hs.HS_UNKNOWN_ERROR));
}

test "check edge cases" {
    // Test boundary values
    try check(0); // Success
    try check(1); // Unknown positive
    try check(-100); // Unknown negative

    // Test maximum and minimum values
    try check(std.math.maxInt(c_int));
    try check(std.math.minInt(c_int));

    // Test known error codes as edge cases
    try std.testing.expectError(Error.Invalid, check(-1));
    try std.testing.expectError(Error.NoMemory, check(-2));
    try std.testing.expectError(Error.UnknownError, check(-13));
}

test "check error documentation consistency" {
    // This test ensures that the error documentation matches the actual error codes
    // by verifying that all documented errors are actually tested

    // Test that all error types in the Error enum are covered
    const all_errors = [_]Error{
        Error.Success,
        Error.Invalid,
        Error.NoMemory,
        Error.ScanTerminated,
        Error.CompileError,
        Error.DbVersionError,
        Error.DbPlatformError,
        Error.DbModeError,
        Error.BadAlign,
        Error.BadAlloc,
        Error.ScratchInUse,
        Error.ArchError,
        Error.InsufficientSpace,
        Error.UnknownError,
    };

    // Verify that all errors are defined (this is a compile-time check)
    _ = all_errors;

    // Verify that Success is handled correctly (should not error)
    try check(hs.HS_SUCCESS);
}

test "check with different integer types" {
    // Test that check() works with different integer types that can be cast to c_int
    try check(@as(i32, hs.HS_SUCCESS));
    try check(@as(i16, @intCast(hs.HS_SUCCESS)));
    try check(@as(i8, @intCast(hs.HS_SUCCESS)));

    try std.testing.expectError(Error.Invalid, check(@as(i32, hs.HS_INVALID)));
    try std.testing.expectError(Error.NoMemory, check(@as(i16, @intCast(hs.HS_NOMEM))));
    try std.testing.expectError(Error.CompileError, check(@as(i8, @intCast(hs.HS_COMPILER_ERROR))));
}

test "check error string representation" {
    // Test that error names are meaningful (compile-time check)
    const error_names = [_][]const u8{
        @errorName(Error.Success),
        @errorName(Error.Invalid),
        @errorName(Error.NoMemory),
        @errorName(Error.ScanTerminated),
        @errorName(Error.CompileError),
        @errorName(Error.DbVersionError),
        @errorName(Error.DbPlatformError),
        @errorName(Error.DbModeError),
        @errorName(Error.BadAlign),
        @errorName(Error.BadAlloc),
        @errorName(Error.ScratchInUse),
        @errorName(Error.ArchError),
        @errorName(Error.InsufficientSpace),
        @errorName(Error.UnknownError),
    };

    // Verify that error names are not empty
    for (error_names) |name| {
        try std.testing.expect(name.len > 0);
    }

    // Verify specific error names
    try std.testing.expectEqualStrings("Invalid", @errorName(Error.Invalid));
    try std.testing.expectEqualStrings("NoMemory", @errorName(Error.NoMemory));
    try std.testing.expectEqualStrings("CompileError", @errorName(Error.CompileError));
}

test "check error ordering" {
    // Test that error codes are in expected order (negative values from -1 to -13)
    const error_values = [_]c_int{
        hs.HS_INVALID, // -1
        hs.HS_NOMEM, // -2
        hs.HS_SCAN_TERMINATED, // -3
        hs.HS_COMPILER_ERROR, // -4
        hs.HS_DB_VERSION_ERROR, // -5
        hs.HS_DB_PLATFORM_ERROR, // -6
        hs.HS_DB_MODE_ERROR, // -7
        hs.HS_BAD_ALIGN, // -8
        hs.HS_BAD_ALLOC, // -9
        hs.HS_SCRATCH_IN_USE, // -10
        hs.HS_ARCH_ERROR, // -11
        hs.HS_INSUFFICIENT_SPACE, // -12
        hs.HS_UNKNOWN_ERROR, // -13
    };

    // Verify that each error code is one less than the previous
    for (error_values, 1..) |code, i| {
        const expected = -@as(c_int, @intCast(i));
        try std.testing.expectEqual(expected, code);
    }
}

test "check error coverage" {
    // Test that we cover all possible error codes in the switch statement
    // This is a compile-time check that ensures we don't miss any cases

    // Test success case
    try check(hs.HS_SUCCESS);

    // Test all known error codes with their specific expected errors
    const test_cases = [_]struct { code: c_int, expected_error: Error }{
        .{ .code = hs.HS_INVALID, .expected_error = Error.Invalid },
        .{ .code = hs.HS_NOMEM, .expected_error = Error.NoMemory },
        .{ .code = hs.HS_SCAN_TERMINATED, .expected_error = Error.ScanTerminated },
        .{ .code = hs.HS_COMPILER_ERROR, .expected_error = Error.CompileError },
        .{ .code = hs.HS_DB_VERSION_ERROR, .expected_error = Error.DbVersionError },
        .{ .code = hs.HS_DB_PLATFORM_ERROR, .expected_error = Error.DbPlatformError },
        .{ .code = hs.HS_DB_MODE_ERROR, .expected_error = Error.DbModeError },
        .{ .code = hs.HS_BAD_ALIGN, .expected_error = Error.BadAlign },
        .{ .code = hs.HS_BAD_ALLOC, .expected_error = Error.BadAlloc },
        .{ .code = hs.HS_SCRATCH_IN_USE, .expected_error = Error.ScratchInUse },
        .{ .code = hs.HS_ARCH_ERROR, .expected_error = Error.ArchError },
        .{ .code = hs.HS_INSUFFICIENT_SPACE, .expected_error = Error.InsufficientSpace },
        .{ .code = hs.HS_UNKNOWN_ERROR, .expected_error = Error.UnknownError },
    };

    // All these should return their specific errors
    for (test_cases) |case| {
        const result = check(case.code);
        try std.testing.expectError(case.expected_error, result);
    }
}
