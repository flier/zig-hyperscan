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
const std = @import("std");
const hs = @import("hyperscan");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Compile a pattern
    const pattern = try hs.Pattern.parse("hello.*world");
    var db = try hs.compile(&pattern, .{});
    defer db.deinit();

    // Allocate scratch space
    const scratch = try db.allocScratch();
    defer scratch.deinit();

    // Scan some text
    const text = "hello beautiful world";
    try db.scanBlock(text, scratch, .{
        .onEvent = onMatch,
        .context = null,
    });
}

fn onMatch(event: hs.MatchEvent) !void {
    std.log.info("Match found at offset {} to {}", .{ event.from, event.to });
}
```

## API Overview

### Pattern Compilation

```zig
// Single pattern
const pattern = try hs.Pattern.parse("test.*pattern");
const db = try hs.compile(&pattern, .{});

// Multiple patterns
const patterns = [_]hs.Pattern{
    try .parse("pattern1"),
    try .parse("pattern2"),
};
const db = try hs.compileMulti(&patterns, .{});
```

### Scanning Modes

```zig
// Block mode (default)
const db = try hs.compile(&pattern, .{ .mode = .{ .block = true } });

// Streaming mode
const db = try hs.compile(&pattern, .{ .mode = .{ .stream = true } });

// Vectored mode
const db = try hs.compile(&pattern, .{ .mode = .{ .vectored = true } });
```

### Pattern Flags

```zig
const pattern = try hs.Pattern.parse("/test/i"); // Case insensitive
const pattern = try hs.Pattern.parse("/test/s"); // Dot matches newline
const pattern = try hs.Pattern.parse("/test/m"); // Multiline mode
```

### Advanced Features

```zig
// Pattern with extensions
const pattern = (try hs.Pattern.parse("test")).withExt(.{
    .min_offset = 10,
    .max_offset = 100,
    .min_length = 5,
});

// Platform-specific optimization
const db = try hs.compile(&pattern, .{
    .platform = .{ .tune = .haswell, .cpu_features = .avx2 },
});
```

## Examples

### Simple Grep Tool

See `examples/simplegrep.zig` for a complete grep-like tool implementation.

```bash
zig build simplegrep -- "pattern" input.txt
```

### Streaming Scanner

```zig
const stream = try db.createStream();

try stream.scan("chunk1", scratch, .{ .onEvent = onMatch });
try stream.scan("chunk2", scratch, .{ .onEvent = onMatch });
try stream.scan("chunk3", scratch, .{ .onEvent = onMatch });
try stream.close(scratch, .{ .onEvent = onMatch });
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
const result = hs.compile(&pattern, .{}) catch |err| switch (err) {
    error.CompileError => {
        std.log.err("Pattern compilation failed");
        return;
    },
    error.OutOfMemory => {
        std.log.err("Insufficient memory");
        return;
    },
    else => |e| {
        std.log.err("Unexpected error: {}", .{e});
        return;
    },
};
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