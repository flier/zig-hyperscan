//! The Hyperscan API definition.

// The Hyperscan version API definition.

const ver = @import("version.zig");

pub const VERSION = ver.VERSION;
pub const version = ver.version;

// The Hyperscan common API definition.

const common = @import("common.zig");

pub const Error = common.Error;
pub const Database = common.Database;
pub const Serialized = common.Serialized;

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
