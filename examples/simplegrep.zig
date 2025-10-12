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

        var patterns: std.ArrayList(hs.Pattern) = try .initCapacity(allocator, args.len - idx - 1);

        for (args[idx .. args.len - 1]) |arg| {
            var pattern: hs.Pattern = try .parse(arg);

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
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    // Parse command line arguments

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var opts: Options = try .parse(allocator, args);
    defer opts.deinit(allocator);

    std.log.debug("Options: {f}", .{opts});

    // Compile patterns into a database

    var db: hs.Database = try .compileMulti(opts.patterns.items, .{
        .mode = .{ .stream = opts.stream, .block = !opts.stream, .som_horizon_large = opts.stream },
    });
    defer db.deinit();

    // Get database information

    const db_info = try db.info(allocator);
    defer allocator.free(db_info);

    std.log.debug("Hyperscan {s} Database size: {d} bytes", .{ db_info, try db.size() });

    // Allocate scratch space for scanning

    const scratch = try db.allocScratch();
    defer scratch.deinit();

    std.log.debug("Scratch size: {d} bytes", .{try scratch.size()});

    // Open input file

    var input = try std.fs.cwd().openFile(opts.input_file, .{});
    defer input.close();

    // Scan input file

    if (opts.stream) {
        try scanStream(input, &opts.patterns, db, scratch);
    } else {
        try scanBlock(allocator, input, &opts.patterns, db, scratch);
    }
}

fn scanBlock(allocator: std.mem.Allocator, f: std.fs.File, patterns: *std.ArrayList(hs.Pattern), db: hs.Database, scratch: hs.Scratch) !void {
    var buf: [std.heap.pageSize()]u8 = undefined;
    var reader = f.reader(&buf);
    const data = try reader.interface.allocRemaining(allocator, .unlimited);
    defer allocator.free(data);

    std.log.debug("Data size: {d} bytes", .{data.len});

    const ctx = Context{
        .patterns = patterns.items,
        .data = data,
    };

    try db.scanBlock(data, scratch, .{
        .onEvent = onEvent,
        .context = @constCast(&ctx),
    });
}

fn scanStream(f: std.fs.File, patterns: *std.ArrayList(hs.Pattern), db: hs.Database, scratch: hs.Scratch) !void {
    const ctx = Context{
        .patterns = patterns.items,
    };

    var buf: [std.heap.pageSize()]u8 = undefined;
    var reader = f.readerStreaming(&buf);

    try db.scanStream(&reader.interface, scratch, .{
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
