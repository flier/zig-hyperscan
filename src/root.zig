pub const Database = @import("database.zig");
pub const Error = @import("error.zig").Error;
pub const Platform = @import("compile.zig").Platform;
pub const Scratch = @import("scratch.zig");
pub const ScanOptions = @import("scan.zig").Options;

const match = @import("match.zig");

pub const MatchAction = match.Action;
pub const MatchEvent = match.Event;
pub const MatchEventHandler = match.EventHandler;

const ver = @import("version.zig");

pub const version = ver.version;
pub const version_string = ver.version_string;
pub const version_32bit = ver.version_32bit;
pub const version_major = ver.version_major;
pub const version_minor = ver.version_minor;
pub const version_patch = ver.version_patch;
