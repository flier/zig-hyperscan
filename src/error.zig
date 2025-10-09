const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

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

pub fn check(err: hs.hs_error_t) Error!void {
    switch (err) {
        // hs.HS_SUCCESS => return Error.Success,
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
