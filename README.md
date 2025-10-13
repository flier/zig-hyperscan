# zig-hyperscan

[![CI](https://github.com/flier/zig-hyperscan/actions/workflows/ci.yml/badge.svg)](https://github.com/flier/zig-hyperscan/actions/workflows/ci.yml)
[![Zig](https://img.shields.io/badge/Zig-0.15.1+-blue.svg)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A high-performance Zig binding for [Hyperscan](https://github.com/intel/hyperscan), Intel's high-performance multiple regex matching library. This library provides fast, memory-efficient pattern matching capabilities for Zig applications.

## Features

- **High Performance**: Leverages Hyperscan's optimized regex engines for maximum throughput
- **Multiple Matching Modes**: Support for block, streaming, and vectored scanning modes
- **Pattern Compilation**: Compile single or multiple regex patterns into optimized databases
- **Memory Efficient**: Minimal memory footprint with efficient scratch space management
- **Type Safe**: Full Zig type safety with comprehensive error handling
- **Cross Platform**: Works on macOS, Linux, and other supported platforms
- **Unicode Support**: Full UTF-8 and Unicode pattern matching capabilities

## Installation

### Prerequisites

- Zig 0.15.1 or later
- Hyperscan library installed on your system

### Installing Hyperscan

#### macOS (Homebrew)
```bash
brew install hyperscan
```

#### Ubuntu/Debian
```bash
sudo apt-get install libhyperscan-dev
```

#### From Source
Follow the [official Hyperscan installation guide](http://intel.github.io/hyperscan/dev-reference/getting_started.html).

### Adding to Your Project

Depending on which developer you are, you need to run different `zig fetch` commands:

```shell
# Version of zig-hyperscan that works with a tagged release of Zig
# Replace `<REPLACE ME>` with the version of zig-hyperscan that you want to use
# See: https://github.com/flier/zig-hyperscan/releases
zig fetch --save https://github.com/flier/zig-hyperscan/archive/refs/tags/<REPLACE ME>.tar.gz

# Version of zig-hyperscan that works with latest build of Zigs master branch
zig fetch --save git+https://github.com/flier/zig-hyperscan
```

And in your `build.zig`:

```zig
const hyperscan = b.dependency("hyperscan", .{});
exe.root_module.addImport("hyperscan", hyperscan.module("hyperscan"));
exe.root_module.linkSystemLibrary("hs");
```

## Quick Start

```zig
// Parse a pattern
var pattern: Pattern = try .parse("hello.*world");

// Set the `som_leftmost` flag to true, this will make the match event callback function be called for the leftmost match
pattern.flags.som_leftmost = true;

// Compile the pattern into a Hyperscan database, default is block mode
const db: Database = try .compile(&pattern, .{});
defer db.deinit();

// Allocate scratch space
const scratch = try db.allocScratch();
defer scratch.deinit();

// Define a match struct to store the match
const Match = struct { from: u64, to: u64 };

var m: Match = undefined;

// Scan some text, onEvent is a callback function that will be called for each match
try db.scanBlock("hello beautiful world", scratch, .{
    .onEvent = struct {
        fn handler(event: hs.MatchEvent) !void {
            std.log.info("Match found at offset {d} to {d}", .{ event.from.?, event.to });

            // Store the match in the match struct
            event.data(Match).* = .{ .from = event.from.?, .to = event.to };
        }
    }.handler,
    .context = &m,
});

try std.testing.expectEqualDeep(Match{ .from = 0, .to = 21 }, m);
```

## API Overview

### Regex helper (high-level API)

```zig
const std = @import("std");

const Regex = @import("hyperscan").Regex;

test Regex {
    //Compile a pattern and create a Regex object
    const regex = try Regex.compile("he[l]+");
    defer regex.deinit();

    // Match the data
    try std.testing.expect(try regex.match("hello world"));

    // Find the first match, default is leftmost match
    var s = try regex.find("hello world", .{});
    try std.testing.expectEqualStrings("hel", s.?);

    // Find the longest match
    s = try regex.find("hello world", .{ .longest = true });
    try std.testing.expectEqualStrings("hell", s.?);

    // Find indices
    const m = try regex.findIndex("hello world", .{});
    try std.testing.expectEqualDeep(Regex.Match{ .from = 0, .to = 3 }, m.?);

    // Find all matches (views into original data)
    const matches = try regex.findAll(std.testing.allocator, "hello helo helo", .{});
    defer std.testing.allocator.free(matches.?);

    // The matches are views into the original data
    try std.testing.expectEqualDeep(&[_][]const u8{ "hel", "hell", "hel", "hel" }, matches.?);

    // Replace all (allocates new string). Uses longest matching internally.
    const replaced = try regex.replace(std.testing.allocator, "hello world", "HELL");
    defer std.testing.allocator.free(replaced);

    try std.testing.expectEqualStrings("HELLo world", replaced);

    // Replace with function. Return null to keep original. Non-null must be heap-allocated;
    // replaceFn copies bytes then frees the temporary returned buffer.
    const out = try regex.replaceFn(
        std.testing.allocator,
        "hello helo",
        struct {
            fn upper(allocator: std.mem.Allocator, str: []const u8) ?[]const u8 {
                return std.ascii.allocUpperString(allocator, str) catch return null;
            }
        }.upper,
    );
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("HELLo HELo", out);

    // Split the data into parts separated by the regex pattern
    const sep = try Regex.compile("-+");
    defer sep.deinit();

    // Split (delimiters omitted). Returns views into original input.
    const parts = try sep.split(std.testing.allocator, "he-llo--helo");
    defer std.testing.allocator.free(parts);

    try std.testing.expectEqualDeep(&[_][]const u8{ "he", "llo", "helo" }, parts);
}
```

### Pattern Compilation

```zig
// Single pattern
const pattern = try Pattern.parse("test");
const db: Database = try .compile(&pattern, .{});
defer db.deinit();

// Multiple patterns
const patterns = [_]Pattern{
    try .parse("foo"),
    try .parse("bar"),
};
const mdb: Database = try .compileMulti(&patterns, .{});
defer mdb.deinit();
```

### Scanning Modes

```zig
const pattern = try Pattern.parse("test");

// Block mode (default)
const block_db: Database = try .compile(&pattern, .{ .mode = .{ .block = true } });
defer block_db.deinit();

// Streaming mode
const stream_db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
defer stream_db.deinit();

// Vectored mode
const vectored_db: Database = try .compile(&pattern, .{ .mode = .{ .vectored = true } });
defer vectored_db.deinit();
```

### Pattern Flags

```zig
_ = try Pattern.parse("test");
_ = try Pattern.parse("/test/s"); // Dot matches newline
_ = try Pattern.parse("2:/test/m"); // Multiline mode with id
```

### Advanced Features

```zig
// Pattern with extensions
var pattern = try Pattern.parse("test!+");

pattern = pattern.withExt(.{
    .min_offset = 10,
    .max_offset = 100,
    .min_length = 5,
});

// Platform-specific optimization
const db: Database = try .compile(&pattern, .{
    .platform = .{
        .tune = .haswell,
        .cpu_features = .avx2,
    },
});
defer db.deinit();
```

## Examples

### Simple Grep Tool

See `examples/simplegrep.zig` for a complete grep-like tool implementation.

```bash
zig build simplegrep -- "pattern" input.txt
```

### Streaming Scanner

```zig
// Compile the pattern into a streaming database
const pattern: Pattern = try .parse("chunk\\d+");
const db: Database = try .compile(&pattern, .{ .mode = .{ .stream = true } });
const stream = try db.openStream(.{});

const scratch = try db.allocScratch();
defer scratch.deinit();

var matches: std.ArrayList(u64) = try .initCapacity(std.testing.allocator, 3);
defer matches.deinit(std.testing.allocator);

const opts: ScanOptions = .{
    .onEvent = struct {
        fn handler(evt: hs.MatchEvent) !void {
            evt.data(std.ArrayList(u64)).append(std.testing.allocator, evt.to) catch {};
        }
    }.handler,
    .context = &matches,
};

// Scan the data in streaming mode
try stream.scan("chunk1", scratch, opts);
try stream.scan("chunk2", scratch, opts);
try stream.scan("chunk3", scratch, opts);
try stream.close(scratch, opts);

try std.testing.expectEqualDeep(&[_]u64{ 6, 12, 18 }, matches.items);
```

## Performance

Hyperscan is designed for high-performance pattern matching:

- **Throughput**: Can process gigabytes of text per second
- **Memory**: Efficient memory usage with configurable scratch space
- **Scalability**: Handles thousands of patterns simultaneously
- **Optimization**: Automatic CPU feature detection and optimization

## Error Handling

The library provides comprehensive error handling:

```zig
const pattern: Pattern = try .parse("a+b");
const db = Database.compile(&pattern, .{}) catch |err| switch (err) {
    error.DbModeError => {
        std.log.err("Database mode error", .{});
        return;
    },
    error.CompileError => {
        std.log.err("Pattern compilation failed", .{});
        return;
    },
    else => |e| {
        std.log.err("Unexpected error: {s}", .{@errorName(e)});
        return;
    },
};

defer db.deinit();
```

## Testing

Run the test suite:

```bash
zig build test
```

## Linting

Run with linting:

```bash
zig build lint
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Intel Hyperscan](https://github.com/intel/hyperscan) - The underlying regex matching engine
- [Zig](https://ziglang.org/) - The programming language this binding is written in