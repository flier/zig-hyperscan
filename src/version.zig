//! The Hyperscan version API definition.

const std = @import("std");

const cString = @cImport(@cInclude("string.h"));
const hs = @cImport(@cInclude("hs/hs.h"));

/// Utility function for identifying this release version.
pub fn version() []const u8 {
    const s = hs.hs_version();

    return s[0..cString.strlen(s)];
}

test version {
    try std.testing.expectEqualStrings(version(), hs.HS_VERSION_STRING);
}

/// A version struct to identify this release of Hyperscan.
pub const Version = struct {
    /// A 32-bit version number.
    value: u32,
    /// The major version number.
    major: u32,
    /// The minor version number.
    minor: u32,
    /// The patch version number.
    patch: u32,
    /// A version string.
    string: []const u8,
};

/// The current Hyperscan version.
pub const VERSION = Version{
    .value = hs.HS_VERSION_32BIT,
    .major = hs.HS_MAJOR,
    .minor = hs.HS_MINOR,
    .patch = hs.HS_PATCH,
    .string = hs.HS_VERSION_STRING[0..hs.HS_VERSION_STRING.len],
};

test VERSION {
    try std.testing.expectEqual(VERSION.value, hs.HS_VERSION_32BIT);
    try std.testing.expectEqual(VERSION.major, hs.HS_MAJOR);
    try std.testing.expectEqual(VERSION.minor, hs.HS_MINOR);
    try std.testing.expectEqual(VERSION.patch, hs.HS_PATCH);
    try std.testing.expectEqualStrings(VERSION.string, hs.HS_VERSION_STRING[0..hs.HS_VERSION_STRING.len]);
}
