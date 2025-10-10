//! The Hyperscan runtime API definition.

pub const Stream = @import("runtime/stream.zig");
pub const Scratch = @import("runtime/scratch.zig");

const match = @import("runtime/match.zig");

pub const MatchError = match.Error;
pub const MatchEvent = match.Event;
pub const MatchEventHandler = match.EventHandler;

const scan = @import("runtime/scan.zig");

pub const ScanOptions = scan.Options;
pub const scan_block = scan.scan_block;
pub const scan_vector = scan.scan_vector;

test {
    _ = @import("runtime/match.zig");
    _ = @import("runtime/scan.zig");
    _ = @import("runtime/stream.zig");
    _ = @import("runtime/scratch.zig");
}
