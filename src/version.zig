const cString = @cImport({
    @cInclude("string.h");
});

const hs = @cImport({
    @cInclude("hs/hs.h");
});

/// A version string to identify this release of Hyperscan.
pub const version_string = hs.HS_VERSION_STRING[0..hs.HS_VERSION_STRING.len];
/// A 32-bit version number to identify this release of Hyperscan.
pub const version_32bit = hs.HS_VERSION_32BIT;
/// The major version number of this release of Hyperscan.
pub const version_major = hs.HS_MAJOR;
/// The minor version number of this release of Hyperscan.
pub const version_minor = hs.HS_MINOR;
/// The patch version number of this release of Hyperscan.
pub const version_patch = hs.HS_PATCH;

/// Utility function for identifying this release version.
pub fn version() []const u8 {
    const s = hs.hs_version();

    return s[0..cString.strlen(s)];
}
