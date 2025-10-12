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
    const ver = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{current_version});
    defer std.testing.allocator.free(ver);

    try std.testing.expectStringStartsWith(version(), ver);
}

/// A version struct to identify this release of Hyperscan.
pub const Version = struct {
    /// The major version number.
    major: u32,
    /// The minor version number.
    minor: u32,
    /// The patch version number.
    patch: u32,

    /// Format the version as a string.
    pub fn format(self: Version, writer: anytype) !void {
        try writer.print("{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
    }

    /// Get the value of the version.
    pub fn value(self: Version) u32 {
        return (self.major << 24) | (self.minor << 16) | (self.patch << 8);
    }
};

/// The current Hyperscan version.
pub const current_version: Version = .{
    .major = hs.HS_MAJOR,
    .minor = hs.HS_MINOR,
    .patch = hs.HS_PATCH,
};

test current_version {
    try std.testing.expectEqual(current_version.major, hs.HS_MAJOR);
    try std.testing.expectEqual(current_version.minor, hs.HS_MINOR);
    try std.testing.expectEqual(current_version.patch, hs.HS_PATCH);
}
