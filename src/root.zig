//! The Hyperscan API definition.

// The Hyperscan version API definition.

const ver = @import("version.zig");

pub const current_version = ver.current_version;
pub const version = ver.version;
pub const Version = ver.Version;

// The Hyperscan common API definition.

const common = @import("common.zig");

pub const Error = common.Error;
pub const Database = common.Database;
pub const Serialized = common.Serialized;
pub const Regex = common.Regex;

// The Hyperscan compiler API definition.

const compile = @import("compile.zig");

pub const CompileOptions = compile.Options;
pub const Mode = compile.Mode;
pub const Pattern = compile.Pattern;
pub const Platform = compile.Platform;

// The Hyperscan runtime API definition.

const runtime = @import("runtime.zig");

pub const Scratch = runtime.Scratch;
pub const MatchEvent = runtime.MatchEvent;
pub const MatchEventHandler = runtime.MatchEventHandler;
pub const ScanOptions = runtime.ScanOptions;

const std = @import("std");

test {
    std.testing.refAllDecls(@This());
}
