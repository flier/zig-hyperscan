// The Hyperscan common API definition.

pub const Database = @import("database.zig");
pub const Error = @import("error.zig").Error;

const ver = @import("version.zig");

pub const version = ver.version;
pub const version_string = ver.version_string;
pub const version_32bit = ver.version_32bit;
pub const version_major = ver.version_major;
pub const version_minor = ver.version_minor;
pub const version_patch = ver.version_patch;

// The Hyperscan compiler API definition.

const compile = @import("compile.zig");

pub const CompileOptions = compile.CompileOptions;
pub const Mode = compile.Mode;
pub const Pattern = compile.Pattern;
pub const Platform = compile.Platform;

// The Hyperscan runtime API definition.

pub const Scratch = @import("scratch.zig");
pub const ScanOptions = @import("scan.zig").Options;

const match = @import("match.zig");

pub const MatchAction = match.Action;
pub const MatchEvent = match.Event;
pub const MatchEventHandler = match.EventHandler;
