//! The Hyperscan common API definition.

const std = @import("std");

pub const Database = @import("common/database.zig");
pub const Serialized = @import("common/serialized.zig");

const err = @import("common/error.zig");

pub const Error = err.Error;
pub const check = err.check;

test {
    std.testing.refAllDecls(@This());
}
