//! The Hyperscan version API definition.

const std = @import("std");

const cstring = @cImport(@cInclude("string.h"));
const hs = @cImport(@cInclude("hs/hs.h"));

/// Utility function for identifying this release version.
pub fn version() []const u8 {
    const ver = hs.hs_version();

    return ver[0..cstring.strlen(ver)];
}

test version {
    try std.testing.expectEqualStrings(version(), hs.HS_VERSION_STRING);
}

/// The current Hyperscan version.
pub const current_version = .{
    .major = hs.HS_MAJOR,
    .minor = hs.HS_MINOR,
    .patch = hs.HS_PATCH,
};

test current_version {
    try std.testing.expectEqual(current_version.major, hs.HS_MAJOR);
    try std.testing.expectEqual(current_version.minor, hs.HS_MINOR);
    try std.testing.expectEqual(current_version.patch, hs.HS_PATCH);
}
