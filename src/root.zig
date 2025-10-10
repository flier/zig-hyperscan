//! The Hyperscan API definition.

// The Hyperscan version API definition.

const VERSION = @import("version.zig").VERSION;

// The Hyperscan common API definition.

const common = @import("common.zig");

pub const Database = common.Database;
pub const Error = common.Error;

pub const version = common.version;

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

test {
    _ = @import("common.zig");
    _ = @import("compile.zig");
    _ = @import("runtime.zig");
    _ = @import("version.zig");
}
