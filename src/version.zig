const hs = @cImport({
    @cInclude("hs/hs.h");
});

/// A version string to identify this release of Hyperscan.
pub const version_string = hs.HS_VERSION_STRING[0..hs.HS_VERSION_STRING.len];
pub const version_32bit = hs.HS_VERSION_32BIT;
pub const version_major = hs.HS_MAJOR;
pub const version_minor = hs.HS_MINOR;
pub const version_patch = hs.HS_PATCH;
