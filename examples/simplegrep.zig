const std = @import("std");
const hs = @import("hyperscan");

const usage =
    \\Usage: {s} [options] <pattern> <input file>
    \\
    \\Options:
    \\  -h, --help       Show this help message and exit
    \\  -s, --stream     Use streaming mode
    \\
    \\Examples:
    \\  {s} -s foobar input.txt
    \\  {s} /foobar/i input.txt
    \\
;

fn showUsage(program: []const u8) noreturn {
    std.debug.print(usage, .{ program, program, program });

    std.process.exit(0);
}

const Options = struct {
    patterns: std.ArrayList(hs.Pattern),
    input_file: []const u8,
    stream: bool,

    pub fn deinit(s: *@This(), allocator: std.mem.Allocator) void {
        s.patterns.deinit(allocator);
    }

    pub fn format(s: @This(), writer: *std.Io.Writer) !void {
        try writer.print("input_file: {s}, stream: {}", .{ s.input_file, s.stream });

        if (s.patterns.items.len > 0) {
            try writer.print(", patterns: {{", .{});

            for (s.patterns.items, 0..) |pattern, i| {
                if (i > 0) {
                    try writer.print(", ", .{});
                }

                try writer.print("{d}: {f}", .{ pattern.id orelse 0, pattern });
            }

            try writer.print("}}", .{});
        }
    }

    pub fn parse(allocator: std.mem.Allocator, args: []const []const u8) !Options {
        const program = std.fs.path.basename(args[0]);
        var stream = false;
        var idx: usize = 1;

        while (idx < args.len) {
            const arg = args[idx];

            if (arg[0] != '-') {
                break;
            }

            if (std.mem.eql(u8, arg, "-h") | std.mem.eql(u8, arg, "--help")) {
                showUsage(program);
            } else if (std.mem.eql(u8, arg, "-s") | std.mem.eql(u8, arg, "--stream")) {
                stream = true;
            }

            idx += 1;
        }

        if (args.len < idx + 2) {
            showUsage(program);
        }

        var patterns = try std.ArrayList(hs.Pattern).initCapacity(allocator, args.len - idx - 1);

        for (args[idx .. args.len - 1]) |arg| {
            var pattern = try hs.Pattern.parse(arg);

            pattern.flags.som_leftmost = true;

            try patterns.append(allocator, pattern);
        }

        return Options{
            .patterns = patterns,
            .input_file = args[args.len - 1],
            .stream = stream,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    // Parse command line arguments

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var opts = try Options.parse(allocator, args);
    defer opts.deinit(allocator);

    std.log.debug("Options: {f}", .{opts});

    // Compile patterns into a database

    var db = try hs.Database.compile_multi(opts.patterns.items, .{
        .mode = .{ .stream = opts.stream, .block = !opts.stream, .som_horizon_large = opts.stream },
    });
    defer db.deinit();

    // Get database information

    const db_info = try db.info(allocator);
    defer allocator.free(db_info);

    std.log.debug("Hyperscan {s} Database size: {d} bytes", .{ db_info, try db.size() });

    // Allocate scratch space for scanning

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    std.log.debug("Scratch size: {d} bytes", .{try scratch.size()});

    // Open input file

    var f = try std.fs.cwd().openFile(opts.input_file, .{});
    defer f.close();

    // Scan input file

    if (opts.stream) {
        try scan_stream(f, &opts.patterns, db, scratch);
    } else {
        try scan_block(allocator, f, &opts.patterns, db, scratch);
    }
}

fn scan_block(allocator: std.mem.Allocator, f: std.fs.File, patterns: *std.ArrayList(hs.Pattern), db: hs.Database, scratch: hs.Scratch) !void {
    const data = try f.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    std.log.debug("Data size: {d} bytes", .{data.len});

    const ctx = Context{
        .patterns = patterns.items,
        .data = data,
    };

    try db.scan_block(data, scratch, .{
        .onEvent = onEvent,
        .context = @constCast(&ctx),
    });
}

fn scan_stream(f: std.fs.File, patterns: *std.ArrayList(hs.Pattern), db: hs.Database, scratch: hs.Scratch) !void {
    const stream = try db.open_stream(.{});
    const ctx = Context{
        .patterns = patterns.items,
    };

    var buf: [4096]u8 = undefined;
    var off: usize = 0;
    var r = f.readerStreaming(&buf);

    while (!r.atEnd()) {
        const rd = r.readStreaming(&buf) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        const data = buf[0..rd];

        try stream.scan(data, scratch, .{
            .onEvent = onEvent,
            .context = @constCast(&ctx),
        });

        off += rd;
    }

    try stream.close(scratch, .{
        .onEvent = onEvent,
        .context = @constCast(&ctx),
    });
}

const Context = struct {
    patterns: []const hs.Pattern,
    data: ?[]const u8 = null,
};

fn onEvent(evt: hs.MatchEvent) !void {
    const ctx = evt.data(Context);

    if (evt.from) |from| {
        if (ctx.data) |data| {
            std.log.info("Match for pattern #{} `{f}` at offset {}..{}: {s}", .{ evt.id, ctx.patterns[evt.id], from, evt.to, data[from..evt.to] });
        } else {
            std.log.info("Match for pattern #{} `{f}` at offset {}..{}", .{ evt.id, ctx.patterns[evt.id], from, evt.to });
        }
    } else {
        std.log.info("Match for pattern #{} `{f}` at offset ..{}", .{ evt.id, ctx.patterns[evt.id], evt.to });
    }
}
